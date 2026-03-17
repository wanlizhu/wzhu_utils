#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Script name:
#     offcpu-wait-reasons.sh
#
# Purpose:
#     Analyze prolonged off-CPU waiting of a target Linux process and generate
#     one self-contained HTML report that explains what threads waited on,
#     which threads woke them, how much scheduler delay happened after wakeup,
#     and what stack context existed near the relevant scheduler events.
#
# Inputs:
#     Required:
#         PID
#             Target process ID to monitor.
#
#     Optional:
#         FUNCTION_NAME
#             If provided, function scope is used and only blocked waits that
#             overlap this function's execution windows are retained.
#             If omitted, process scope is used.
#
# Symbol resolution behavior:
#     When FUNCTION_NAME is provided, the script does not assume libvulkan.so or
#     any single vendor library. It scans executable mapped ELF files of the
#     target process and searches for the symbol in a priority order.
#
#     For NVIDIA, candidate priority is:
#         1) libnvidia-glcore.so / libnvidia-glcore.so.*
#         2) other libnvidia-*.so / libnvidia-*.so.*
#         3) all other executable mapped ELF files
#
# Outputs:
#     Only one final output file is retained:
#         OUT_DIR/out_report.html
#
#     The HTML report is intentionally all-in-one. It contains:
#         - overview and run configuration
#         - symbol resolution diagnostics
#         - wait-wake graph
#         - top longest waits
#         - per-thread summary
#         - root-cause buckets
#         - stack focus
#         - embedded scheduler text views
#         - embedded raw summary text
#
#     There is no separate retained text summary file. Any plain-text content
#     that cannot be visualized is embedded into its own HTML tab.
#
# Implementation overview:
#     - perf record captures scheduler tracepoints system-wide
#     - optional bpftrace uprobe/uretprobe traces FUNCTION_NAME enter/exit
#     - optional bpftrace captures stack context around scheduler events
#     - /proc sampling collects thread state and kernel wait reason
#     - embedded Python correlates all temporary artifacts and writes one HTML
#
# Notes:
#     - Uses sudo for commands that require root (perf, bpftrace, /proc access, readelf/nm on target).
#     - Stack capture is best-effort.
#     - User stacks may be incomplete depending on unwindability and symbols.
#     - Only active threads are kept in the final report:
#           active thread = a thread that produced at least one kept wait record
# -----------------------------------------------------------------------------

set -o pipefail

CAPTURE_SECONDS=0  # when 0, capture continues until interrupted by Ctrl-C
SAMPLE_MS=10
LONG_WAIT_MS=2.0
OUT_DIR=./offcpu_wait_reasons.d

ENABLE_STACKS=1
STACK_SCOPE=all
STACK_LIMIT=32

FUNCTION_LIBRARY_PATH=

TARGET_PID=
FUNCTION_NAME=
ANALYSIS_SCOPE=

TEMP_DIR=
RESOLVED_FUNCTION_LIBRARY=

perf_pid=
function_trace_pid=
stack_trace_pid=
kernel_wait_reason_sampler_pid=
timeout_pid=

# -----------------------------------------------------------------------------
# print_help
#
# Input:
#     None.
#
# Output:
#     Prints detailed usage information to stdout.
#
# Description:
#     This function is the user-facing command reference for the script. It
#     explains the positional arguments, the single retained HTML output, and
#     the configuration variables that control trace duration, sampling rate,
#     stack capture, and symbol resolution behavior.
#
#     Help handling lives in a standalone function so it can be invoked before
#     any privileged tracing setup or temporary file creation. That keeps the
#     command safe to inspect on any machine without side effects.
# -----------------------------------------------------------------------------
print_help() {
    echo "Usage:"
    echo "    $0 <pid> [function_name]"
    echo
    echo "Description:"
    echo "    Analyze off-CPU wait reasons of a target process and write one HTML report."
    echo
    echo "Arguments:"
    echo "    <pid>"
    echo "        Target process ID."
    echo
    echo "    [function_name]"
    echo "        Optional symbol name."
    echo "        If present, function scope is used."
    echo "        If omitted, process scope is used."
    echo
    echo "Examples:"
    echo "    sudo $0 12345"
    echo "    sudo $0 12345 vkQueuePresentKHR"
    echo "    sudo $0 12345 __some_nvidia_internal_symbol"
    echo
    echo "Retained output:"
    echo "    $OUT_DIR/out_report.html"
    echo
    echo "Config variables near top of script:"
    echo "    CAPTURE_SECONDS  (0 = capture until Ctrl-C)"
    echo "    SAMPLE_MS"
    echo "    LONG_WAIT_MS"
    echo "    OUT_DIR"
    echo "    ENABLE_STACKS"
    echo "    STACK_SCOPE"
    echo "    STACK_LIMIT"
    echo "    FUNCTION_LIBRARY_PATH"
    echo
    echo "STACK_SCOPE:"
    echo "    all"
    echo "        show stack context broadly"
    echo
    echo "    long_wait"
    echo "        emphasize only long waits in stack focus"
}

# -----------------------------------------------------------------------------
# cleanup
#
# Input:
#     None.
#
# Output:
#     None.
#
# Description:
#     This function shuts down every background worker that may have been
#     started during tracing, including perf, optional bpftrace sessions, the
#     kernel wait reason sampler, and the timeout helper. It also removes the
#     temporary working directory created for intermediate artifacts.
#
#     The cleanup path is intentionally tolerant of partial setup and partial
#     failure. It checks every process handle before kill/wait so the script can
#     exit cleanly after startup failures, Ctrl-C, timeout, or missing-symbol
#     cases without leaving collectors running in the background.
# -----------------------------------------------------------------------------
cleanup() {
    [[ -n $perf_pid ]] && kill -INT $perf_pid
    [[ -n $function_trace_pid ]] && kill -INT $function_trace_pid
    [[ -n $stack_trace_pid ]] && kill -INT $stack_trace_pid
    [[ -n $kernel_wait_reason_sampler_pid ]] && kill -TERM $kernel_wait_reason_sampler_pid
    [[ -n $timeout_pid ]] && kill $timeout_pid

    [[ -n $perf_pid ]] && wait $perf_pid
    [[ -n $function_trace_pid ]] && wait $function_trace_pid
    [[ -n $stack_trace_pid ]] && wait $stack_trace_pid
    [[ -n $kernel_wait_reason_sampler_pid ]] && wait $kernel_wait_reason_sampler_pid
    [[ -n $timeout_pid ]] && wait $timeout_pid

    [[ -n $TEMP_DIR && -d $TEMP_DIR ]] && rm -rf "$TEMP_DIR"
}

trap cleanup EXIT INT TERM

# -----------------------------------------------------------------------------
# sample_kernel_wait_reasons
#
# Input:
#     Uses global TARGET_PID, SAMPLE_MS, TEMP_DIR.
#
# Output:
#     Writes:
#         $TEMP_DIR/kernel_wait_reason_samples.tsv
#
# Description:
#     This function periodically samples every thread under the target process
#     and records its scheduler-visible state together with the current kernel
#     wait reason name from /proc/<tid>/wchan. These samples provide the extra
#     semantic hint that raw scheduler tracepoints do not provide by themselves.
#
#     The later correlation stage will intersect these samples with each blocked
#     interval reconstructed from perf and infer the most common kernel wait
#     reason during that interval. That is why the output is a timestamped time
#     series rather than a single final value.
# -----------------------------------------------------------------------------
sample_kernel_wait_reasons() {
    sudo bash -c "
        echo -e 'ts_ns\ttid\tstate\tkernel_wait_reason\tcomm' > \"$TEMP_DIR/kernel_wait_reason_samples.tsv\"
        while [[ -d /proc/$TARGET_PID ]]; do
            ts_ns=\$(date +%s%N)
            [[ \$ts_ns =~ ^[0-9]+\$ ]] || ts_ns=0

            for task_dir in /proc/$TARGET_PID/task/*; do
                [[ -d \$task_dir ]] || continue

                tid=\${task_dir##*/}
                state=\$(awk '/^State:/ { print \$2 }' \$task_dir/status)
                kernel_wait_reason=\$(cat \$task_dir/wchan)
                comm=\$(cat \$task_dir/comm)

                [[ -n \$state ]] || state=-
                [[ -n \$kernel_wait_reason ]] || kernel_wait_reason=-
                [[ -n \$comm ]] || comm=-

                printf '%s\t%s\t%s\t%s\t%s\n' \"\$ts_ns\" \"\$tid\" \"\$state\" \"\$kernel_wait_reason\" \"\$comm\"
            done >> \"$TEMP_DIR/kernel_wait_reason_samples.tsv\"

            python3 -c \"import time; time.sleep($SAMPLE_MS / 1000.0)\" || sleep 0.02
        done
    " &
    kernel_wait_reason_sampler_pid=$!
}

# -----------------------------------------------------------------------------
# run_python_postprocessor
#
# Input:
#     Uses global variables and temporary working files created by earlier
#     tracing stages.
#
# Output:
#     Writes the single final retained output:
#         OUT_DIR/out_report.html
#
# Description:
#     This function is the correlation and presentation stage of the script.
#     Earlier stages deliberately collect narrow raw evidence sources: scheduler
#     events from perf, function windows from optional uprobes, stack snapshots
#     from optional bpftrace, and kernel wait reason hints from /proc sampling.
#     None of those sources is user-friendly or complete on its own.
#
#     The embedded Python code loads every temporary artifact, rebuilds blocked
#     intervals from scheduler timing, overlays optional function scope windows,
#     infers likely kernel wait reasons from samples, associates nearby stack
#     captures, aggregates patterns into root-cause buckets, and renders one
#     self-contained HTML report with tab UI and cross-linked evidence.
# -----------------------------------------------------------------------------
run_python_postprocessor() {
    python3 - "$TARGET_PID" "$ANALYSIS_SCOPE" "$FUNCTION_NAME" "$LONG_WAIT_MS" "$OUT_DIR" "$ENABLE_STACKS" "$STACK_SCOPE" "$TEMP_DIR" <<'PYBLOCK'
import html
import os
import re
import sys
from collections import Counter, defaultdict


def h(s):
    return html.escape(str(s), quote=True)


def load_text_file(path, fallback):
    """
    Load a text artifact into memory for embedding into the final HTML report.
    This helper is used for symbol resolution diagnostics and merged scheduler
    views so missing files can degrade into readable fallback text instead of
    breaking the whole report generation path.
    """
    if not os.path.isfile(path):
        return fallback
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        text = f.read().rstrip()
    return text if text else fallback


def load_function_intervals(function_trace_file):
    """
    Reconstruct per-thread function execution windows from raw enter/exit rows.
    The result is used to implement function scope by interval overlap rather
    than naive timestamp equality. Nested or repeated calls are handled by a
    per-thread enter stack.
    """
    intervals_by_tid = defaultdict(list)
    seen_tids = set()
    enter_stack_by_tid = defaultdict(list)

    if not os.path.isfile(function_trace_file):
        return intervals_by_tid, seen_tids

    with open(function_trace_file, 'r', encoding='utf-8', errors='replace') as f:
        next(f, None)
        for line in f:
            line = line.rstrip('\n')
            if not line:
                continue
            parts = line.split('\t', 3)
            if len(parts) != 4:
                continue
            kind, ts_ns, tid, _comm = parts
            try:
                ts_ns = int(ts_ns)
                tid = int(tid)
            except ValueError:
                continue
            seen_tids.add(tid)
            if kind == 'enter':
                enter_stack_by_tid[tid].append(ts_ns)
            elif kind == 'exit' and enter_stack_by_tid[tid]:
                start_ns = enter_stack_by_tid[tid].pop()
                if ts_ns > start_ns:
                    intervals_by_tid[tid].append((start_ns / 1e9, ts_ns / 1e9))
    return intervals_by_tid, seen_tids


def load_kernel_wait_reason_samples(kernel_wait_reason_file):
    """
    Load the per-thread /proc sampling time series into memory. Each sample row
    records thread state and kernel wait reason at one point in time. Later
    correlation code intersects these samples with reconstructed blocked waits
    to infer the dominant kernel wait reason for each interval.
    """
    samples_by_tid = defaultdict(list)
    seen_tids = set()

    if not os.path.isfile(kernel_wait_reason_file):
        return samples_by_tid, seen_tids

    with open(kernel_wait_reason_file, 'r', encoding='utf-8', errors='replace') as f:
        next(f, None)
        for line in f:
            line = line.rstrip('\n')
            if not line:
                continue
            parts = line.split('\t', 4)
            if len(parts) != 5:
                continue
            ts_ns, tid, state, kernel_wait_reason, comm = parts
            try:
                ts = int(ts_ns) / 1e9
                tid = int(tid)
            except ValueError:
                continue
            seen_tids.add(tid)
            samples_by_tid[tid].append({
                'ts': ts,
                'state': state,
                'kernel_wait_reason': kernel_wait_reason,
                'comm': comm,
            })
    return samples_by_tid, seen_tids


def load_stack_events(stack_file, enable_stacks):
    """
    Parse the textual stack-event stream emitted by bpftrace into dictionaries.
    The collector records structured blocks around scheduler events, and this
    loader normalizes them so later code can search by event kind, tid, and
    timestamp and attach nearby stack context to wait records.
    """
    events = []
    if not enable_stacks or not os.path.isfile(stack_file):
        return events

    with open(stack_file, 'r', encoding='utf-8', errors='replace') as f:
        lines = [x.rstrip('\n') for x in f]

    i = 0
    while i < len(lines):
        if lines[i] != 'EVENT_BEGIN':
            i += 1
            continue
        i += 1
        metadata = {}
        kernel_stack = []
        user_stack = []
        while i < len(lines) and lines[i] != 'EVENT_END':
            line = lines[i]
            if line == 'KERNEL_STACK_BEGIN':
                i += 1
                while i < len(lines) and lines[i] != 'KERNEL_STACK_END':
                    kernel_stack.append(lines[i])
                    i += 1
            elif line == 'USER_STACK_BEGIN':
                i += 1
                while i < len(lines) and lines[i] != 'USER_STACK_END':
                    user_stack.append(lines[i])
                    i += 1
            elif '=' in line:
                key, value = line.split('=', 1)
                metadata[key] = value
            i += 1
        if 'ts_ns' in metadata:
            try:
                events.append({
                    'kind': metadata.get('kind', ''),
                    'ts': int(metadata['ts_ns']) / 1e9,
                    'cpu': int(metadata.get('cpu', '-1')),
                    'actor_tid': int(metadata.get('actor_tid', '0')),
                    'actor_comm': metadata.get('actor_comm', '?'),
                    'target_tid': int(metadata.get('target_tid', '0')) if metadata.get('target_tid') else None,
                    'target_comm': metadata.get('target_comm', '?'),
                    'target_cpu': int(metadata.get('target_cpu', '-1')) if metadata.get('target_cpu') else None,
                    'prev_state': metadata.get('prev_state', ''),
                    'kernel_stack': [x for x in kernel_stack if x and x != '[]'],
                    'user_stack': [x for x in user_stack if x and x != '[]'],
                })
            except ValueError:
                pass
        i += 1
    return events


def format_stack(lines):
    """
    Normalize one stack block into printable multi-line text. Empty lines are
    removed while original order is preserved, so kernel/user stack sections are
    rendered consistently throughout the report with a simple '-' fallback when
    nothing useful was captured.
    """
    if not lines:
        return '-'
    out = []
    for line in lines:
        line = line.strip()
        if line:
            out.append(line)
    return '\n'.join(out) if out else '-'


def is_blocked_state(state):
    """
    Decide whether a sched_switch prev_state should start a blocked wait
    interval. Runnable states are filtered out so ordinary descheduling is not
    misclassified as sleeping.
    """
    state = state.strip()
    if state in ('R', 'R+', 'TASK_RUNNING', '0x0', '0'):
        return False
    if state.startswith('R'):
        return False
    return True


def event_is_in_scope(analysis_scope, function_intervals, tid, start_s, end_s):
    """
    Apply the selected scope rule to one reconstructed blocked interval.
    Process scope keeps all valid waits, while function scope keeps only waits
    whose blocked interval overlaps at least one traced function window on the
    same thread.
    """
    if analysis_scope == 'process':
        return True
    for begin_s, end_scope_s in function_intervals.get(tid, []):
        if start_s < end_scope_s and end_s > begin_s:
            return True
    return False


def most_common_kernel_wait_reason(kernel_wait_reason_samples, tid, start_s, end_s):
    """
    Infer the dominant kernel wait reason during one blocked interval by
    counting /proc samples whose timestamps fall inside that interval. This is
    the bridge between the scheduler timeline and the sampled semantic hint from
    wchan.
    """
    counter = Counter()
    for item in kernel_wait_reason_samples.get(tid, []):
        if start_s <= item['ts'] <= end_s:
            value = item['kernel_wait_reason']
            if value not in ('-', '0', ''):
                counter[value] += 1
    return counter.most_common(1)[0][0] if counter else '-'


def nearest_stack_event(stack_events, kind, tid, ts, window_s):
    """
    Find the closest captured stack snapshot near a scheduler timestamp of
    interest. This is how a wait record gains nearby sleep-out or wakeup stack
    context even though stacks and scheduler events come from separate streams.
    """
    best_event = None
    best_dt = None
    for event in stack_events:
        if event['kind'] != kind:
            continue
        if kind == 'switch_out' and event['actor_tid'] != tid:
            continue
        if kind == 'wakeup' and event['target_tid'] != tid:
            continue
        dt = abs(event['ts'] - ts)
        if dt > window_s:
            continue
        if best_event is None or dt < best_dt:
            best_event = event
            best_dt = dt
    return best_event


target_pid = int(sys.argv[1])
analysis_scope = sys.argv[2]
function_name = sys.argv[3]
long_wait_ms = float(sys.argv[4])
out_dir = sys.argv[5]
enable_stacks = int(sys.argv[6])
stack_scope = sys.argv[7]
temp_dir = sys.argv[8]

function_trace_file = os.path.join(temp_dir, 'function_trace.tsv')
kernel_wait_reason_file = os.path.join(temp_dir, 'kernel_wait_reason_samples.tsv')
stack_file = os.path.join(temp_dir, 'stack_events.txt')
perf_script_file = os.path.join(temp_dir, 'perf_script.txt')
symbol_resolution_file = os.path.join(temp_dir, 'symbol_resolution.txt')
scheduler_views_file = os.path.join(temp_dir, 'scheduler_views.txt')
report_file = os.path.join(out_dir, 'out_report.html')

# Regular expressions that parse perf script output into structured scheduler
# records. These are the raw input grammar for the timeline reconstruction step.
header_re = re.compile(
    r'^\s*(?P<comm>.+?)\s+'
    r'(?:(?P<pid>\d+)\/(?P<tid>\d+)|(?P<tid_only>\d+))\s+'
    r'\[(?P<cpu>\d+)\]\s+'
    r'(?P<time>\d+\.\d+):\s+'
    r'(?P<event>[^:]+):\s+'
    r'(?P<trace>.*)$'
)

switch_re = re.compile(
    r'prev_comm=(?P<prev_comm>.+?)\s+'
    r'prev_pid=(?P<prev_pid>\d+)\s+'
    r'prev_prio=(?P<prev_prio>\d+)\s+'
    r'prev_state=(?P<prev_state>.+?)\s+==>\s+'
    r'next_comm=(?P<next_comm>.+?)\s+'
    r'next_pid=(?P<next_pid>\d+)\s+'
    r'next_prio=(?P<next_prio>\d+)'
)

wakeup_re = re.compile(
    r'comm=(?P<wakee_comm>.+?)\s+'
    r'pid=(?P<wakee_tid>\d+)\s+'
    r'prio=(?P<prio>\d+)\s+'
    r'(?:success=\d+\s+)?'
    r'target_cpu=(?P<target_cpu>\d+)'
)

migrate_re = re.compile(
    r'comm=(?P<comm>.+?)\s+pid=(?P<tid>\d+)\s+prio=(?P<prio>\d+)\s+orig_cpu=(?P<orig>\d+)\s+dest_cpu=(?P<dest>\d+)'
)

symbol_resolution_text = load_text_file(symbol_resolution_file, 'symbol resolution diagnostics unavailable')
scheduler_views_text = load_text_file(scheduler_views_file, 'scheduler views unavailable')
function_intervals, function_trace_tids = load_function_intervals(function_trace_file)
kernel_wait_reason_samples, sampled_tids = load_kernel_wait_reason_samples(kernel_wait_reason_file)
stack_events = load_stack_events(stack_file, enable_stacks)
interesting_tids = set(sampled_tids) | set(function_trace_tids)

# Parse perf script and reconstruct blocked intervals, wakeup timing, waker
# identity, scheduler delay, and migration markers. This is the main timeline
# correlation step that turns raw scheduler events into user-meaningful waits.
thread_names = {}
offcpu_start = {}
offcpu_state = {}
wake_time = {}
wake_info = {}
wait_records = []
migration_records = []
all_times = []

if os.path.isfile(perf_script_file):
    with open(perf_script_file, 'r', encoding='utf-8', errors='replace') as f:
        for raw_line in f:
            line = raw_line.rstrip('\n')
            match = header_re.match(line)
            if not match:
                continue
            current_comm = match.group('comm').strip()
            try:
                current_tid = int(match.group('tid') or match.group('tid_only'))
                ts = float(match.group('time'))
            except (TypeError, ValueError):
                continue
            event_name = match.group('event').strip()
            trace = match.group('trace')
            all_times.append(ts)
            thread_names.setdefault(current_tid, current_comm)

            if event_name == 'sched:sched_switch':
                switch_match = switch_re.search(trace)
                if not switch_match:
                    continue
                try:
                    prev_tid = int(switch_match.group('prev_pid'))
                    next_tid = int(switch_match.group('next_pid'))
                except ValueError:
                    continue
                prev_comm = switch_match.group('prev_comm').strip()
                next_comm = switch_match.group('next_comm').strip()
                prev_state = switch_match.group('prev_state').strip()
                thread_names.setdefault(prev_tid, prev_comm)
                thread_names.setdefault(next_tid, next_comm)

                if prev_tid in interesting_tids and is_blocked_state(prev_state):
                    offcpu_start[prev_tid] = ts
                    offcpu_state[prev_tid] = prev_state

                if next_tid in interesting_tids and next_tid in wake_time:
                    sched_delay_ms = (ts - wake_time[next_tid]) * 1000.0
                    wake_data = wake_info.get(next_tid, {})
                    record = {
                        'tid': next_tid,
                        'comm': thread_names.get(next_tid, str(next_tid)),
                        'wait_start': offcpu_start.get(next_tid),
                        'wake_time': wake_time[next_tid],
                        'run_time': ts,
                        'wait_ms': None,
                        'sched_delay_ms': sched_delay_ms,
                        'prev_state': offcpu_state.get(next_tid, '?'),
                        'waker_tid': wake_data.get('waker_tid'),
                        'waker_comm': wake_data.get('waker_comm', '?'),
                        'wake_cpu': wake_data.get('wake_cpu'),
                        'target_cpu': wake_data.get('target_cpu'),
                        'kernel_wait_reason': '-',
                        'sleep_stack_event': None,
                        'wake_stack_event': None,
                    }
                    if record['wait_start'] is not None and record['wake_time'] >= record['wait_start']:
                        record['wait_ms'] = (record['wake_time'] - record['wait_start']) * 1000.0
                        record['kernel_wait_reason'] = most_common_kernel_wait_reason(kernel_wait_reason_samples, next_tid, record['wait_start'], record['wake_time'])
                        if enable_stacks:
                            record['sleep_stack_event'] = nearest_stack_event(stack_events, 'switch_out', next_tid, record['wait_start'], 0.002)
                            record['wake_stack_event'] = nearest_stack_event(stack_events, 'wakeup', next_tid, record['wake_time'], 0.002)
                        if event_is_in_scope(analysis_scope, function_intervals, next_tid, record['wait_start'], record['run_time']):
                            wait_records.append(record)
                    wake_time.pop(next_tid, None)
                    wake_info.pop(next_tid, None)
                    offcpu_start.pop(next_tid, None)
                    offcpu_state.pop(next_tid, None)

            elif event_name in ('sched:sched_wakeup', 'sched:sched_wakeup_new'):
                wake_match = wakeup_re.search(trace)
                if not wake_match:
                    continue
                try:
                    wakee_tid = int(wake_match.group('wakee_tid'))
                    target_cpu = int(wake_match.group('target_cpu'))
                    wake_cpu = int(match.group('cpu'))
                except ValueError:
                    continue
                wakee_comm = wake_match.group('wakee_comm').strip()
                thread_names.setdefault(wakee_tid, wakee_comm)
                if wakee_tid in interesting_tids:
                    wake_time[wakee_tid] = ts
                    wake_info[wakee_tid] = {
                        'waker_tid': current_tid,
                        'waker_comm': current_comm,
                        'wake_cpu': wake_cpu,
                        'target_cpu': target_cpu,
                    }

            elif event_name == 'sched:sched_migrate_task':
                migrate_match = migrate_re.search(trace)
                if not migrate_match:
                    continue
                try:
                    tid = int(migrate_match.group('tid'))
                    orig_cpu = int(migrate_match.group('orig'))
                    dest_cpu = int(migrate_match.group('dest'))
                except ValueError:
                    continue
                if tid in interesting_tids:
                    migration_records.append({
                        'time': ts,
                        'tid': tid,
                        'comm': migrate_match.group('comm').strip(),
                        'orig_cpu': orig_cpu,
                        'dest_cpu': dest_cpu,
                    })

if not all_times:
    report = f'<!DOCTYPE html><html><head><meta charset="utf-8"><title>offcpu wait reasons report</title></head><body><h1>no scheduler events parsed</h1><h2>symbol resolution</h2><pre>{h(symbol_resolution_text)}</pre><h2>scheduler views</h2><pre>{h(scheduler_views_text)}</pre></body></html>'
    with open(report_file, 'w', encoding='utf-8') as f:
        f.write(report)
    sys.exit(0)

active_tids = sorted({record['tid'] for record in wait_records})
wait_records = [record for record in wait_records if record['tid'] in active_tids]
migration_records = [record for record in migration_records if record['tid'] in active_tids]

lane_index = {tid: i for i, tid in enumerate(active_tids)}
start_time = min(all_times)
end_time = max(all_times)
time_span = max(end_time - start_time, 0.001)
width = 1800
left = 280
right = 40
top = 80
lane_height = 28
lane_gap = 18
height = top + max(1, len(active_tids)) * (lane_height + lane_gap) + 140
usable_width = width - left - right

x_of = lambda ts: left + (ts - start_time) / time_span * usable_width

top_global = sorted([record for record in wait_records if record['wait_ms'] is not None], key=lambda x: x['wait_ms'], reverse=True)[:40]
for index, record in enumerate(top_global, 1):
    record['event_id'] = f'event-{index}'

event_id_map = {id(record): record['event_id'] for record in top_global}

per_tid_records = defaultdict(list)
for record in wait_records:
    per_tid_records[record['tid']].append(record)

per_thread_rows = []
for tid in active_tids:
    items = [record for record in per_tid_records.get(tid, []) if record['wait_ms'] is not None]
    if not items:
        continue
    waits = [record['wait_ms'] for record in items]
    delays = [record['sched_delay_ms'] for record in items]
    top_wakers = Counter(f"{record['waker_comm']}[{record['waker_tid']}]" for record in items if record['waker_tid'] is not None)
    top_kernel_wait_reasons = Counter(record['kernel_wait_reason'] for record in items if record['kernel_wait_reason'] not in ('-', ''))
    per_thread_rows.append({
        'tid': tid,
        'comm': thread_names.get(tid, str(tid)),
        'count': len(items),
        'avg_wait': sum(waits) / len(waits),
        'max_wait': max(waits),
        'avg_delay': sum(delays) / len(delays),
        'max_delay': max(delays),
        'long_waits': sum(1 for x in waits if x >= long_wait_ms),
        'top_waker': top_wakers.most_common(1)[0][0] if top_wakers else '-',
        'top_kernel_wait_reason': top_kernel_wait_reasons.most_common(1)[0][0] if top_kernel_wait_reasons else '-',
    })
per_thread_rows.sort(key=lambda x: x['max_wait'], reverse=True)


def top_frame_from_event(event, which):
    if not event:
        return '-'
    frames = event.get(which) or []
    for frame in frames:
        frame = frame.strip()
        if frame:
            return frame
    return '-'

bucket_by_wait_reason = defaultdict(list)
bucket_by_waker = defaultdict(list)
bucket_by_sleep_top = defaultdict(list)
bucket_by_wake_top = defaultdict(list)
for record in wait_records:
    bucket_by_wait_reason[record['kernel_wait_reason']].append(record)
    waker_key = f"{record['waker_comm']}[{record['waker_tid']}]" if record['waker_tid'] is not None else '-'
    bucket_by_waker[waker_key].append(record)
    bucket_by_sleep_top[top_frame_from_event(record.get('sleep_stack_event'), 'kernel_stack')].append(record)
    bucket_by_wake_top[top_frame_from_event(record.get('wake_stack_event'), 'kernel_stack')].append(record)


def summarize_bucket_map(bucket_map, title):
    rows = []
    for key, items in bucket_map.items():
        waits = [x['wait_ms'] for x in items if x['wait_ms'] is not None]
        delays = [x['sched_delay_ms'] for x in items]
        if not waits:
            continue
        example_ids = []
        for event in top_global:
            if event in items:
                example_ids.append(event['event_id'])
            if len(example_ids) >= 5:
                break
        rows.append({
            'key': key,
            'count': len(items),
            'avg_wait': sum(waits) / len(waits),
            'max_wait': max(waits),
            'avg_delay': sum(delays) / len(delays) if delays else 0.0,
            'max_delay': max(delays) if delays else 0.0,
            'example_event_ids': example_ids,
        })
    rows.sort(key=lambda x: (x['max_wait'], x['count']), reverse=True)
    return title, rows[:20]

bucket_sections = [
    summarize_bucket_map(bucket_by_wait_reason, 'root-cause bucket: kernel wait reason'),
    summarize_bucket_map(bucket_by_waker, 'root-cause bucket: waker thread'),
    summarize_bucket_map(bucket_by_sleep_top, 'root-cause bucket: sleep-out top kernel frame'),
    summarize_bucket_map(bucket_by_wake_top, 'root-cause bucket: wakeup top kernel frame'),
]

stack_focus = top_global
if stack_scope == 'long_wait':
    stack_focus = [record for record in top_global if record['wait_ms'] is not None and record['wait_ms'] >= long_wait_ms]

summary_lines = []
summary_lines.append(f'target_pid={target_pid}')
summary_lines.append(f'scope={analysis_scope}')
summary_lines.append(f'function_name={function_name if function_name else "-"}')
summary_lines.append(f'time_window={start_time:.6f}..{end_time:.6f}')
summary_lines.append(f'active_thread_count={len(active_tids)}')
summary_lines.append(f'enable_stacks={enable_stacks}')
summary_lines.append(f'stack_scope={stack_scope}')
summary_lines.append('')
summary_lines.append('symbol resolution:')
summary_lines.append(symbol_resolution_text)
summary_lines.append('')
summary_lines.append('top longest waits:')
for record in top_global:
    summary_lines.append(
        f"  {record['event_id']} {record['comm']}[{record['tid']}] wait_ms={record['wait_ms']:.3f} delay_ms={record['sched_delay_ms']:.3f} state={record['prev_state']} kernel_wait_reason={record['kernel_wait_reason']} waker={record['waker_comm']}[{record['waker_tid']}] t={record['wait_start']:.6f}->{record['wake_time']:.6f}->{record['run_time']:.6f}"
    )
summary_lines.append('')
summary_lines.append('per-thread summary:')
for row in per_thread_rows:
    summary_lines.append(
        f"  {row['comm']}[{row['tid']}] count={row['count']} avg_wait_ms={row['avg_wait']:.3f} max_wait_ms={row['max_wait']:.3f} avg_delay_ms={row['avg_delay']:.3f} max_delay_ms={row['max_delay']:.3f} long_waits={row['long_waits']} top_waker={row['top_waker']} top_kernel_wait_reason={row['top_kernel_wait_reason']}"
    )
summary_lines.append('')
for title, rows in bucket_sections:
    summary_lines.append(title + ':')
    for row in rows:
        summary_lines.append(
            f"  key={row['key']} count={row['count']} avg_wait_ms={row['avg_wait']:.3f} max_wait_ms={row['max_wait']:.3f} avg_delay_ms={row['avg_delay']:.3f} max_delay_ms={row['max_delay']:.3f} example_events={','.join(row['example_event_ids']) if row['example_event_ids'] else '-'}"
        )
    summary_lines.append('')
summary_text = '\n'.join(summary_lines).rstrip() + '\n'

svg_parts = []
svg_parts.append(f'<svg width="{width}" height="{height}" xmlns="http://www.w3.org/2000/svg">')
svg_parts.append('<style>.label{font:12px monospace;fill:#222}.minor{font:11px monospace;fill:#555}.axis{stroke:#888;stroke-width:1}.lane{stroke:#ddd;stroke-width:1}.wait{fill:#f6b26b;stroke:#c27c2c;stroke-width:1}.delay{fill:#e06666;stroke:#a61c1c;stroke-width:1}.wake{stroke:#4a86e8;stroke-width:1.2;marker-end:url(#arrow);opacity:.8}.migrate{stroke:#6aa84f;stroke-width:1;stroke-dasharray:4 2}.event-highlight{stroke:#000;stroke-width:3}</style>')
svg_parts.append('<defs><marker id="arrow" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto"><polygon points="0 0, 10 3.5, 0 7" fill="#4a86e8"/></marker></defs>')
svg_title = f'wait-wake graph  pid={target_pid}  scope={analysis_scope}'
if function_name:
    svg_title += f'  function={function_name}'
svg_title += f'  active_threads={len(active_tids)}  window={start_time:.6f}s .. {end_time:.6f}s'
svg_parts.append(f'<text x="{left}" y="24" class="label">{h(svg_title)}</text>')
svg_parts.append('<text x="280" y="46" class="minor">orange=blocked wait, red=scheduler delay, blue arrow=waker -&gt; wakee, green dashed=migration</text>')
for i, tid in enumerate(active_tids):
    y = top + i * (lane_height + lane_gap)
    name = thread_names.get(tid, str(tid))
    svg_parts.append(f'<line x1="{left}" y1="{y + lane_height / 2}" x2="{width - right}" y2="{y + lane_height / 2}" class="lane"/>')
    svg_parts.append(f'<text x="12" y="{y + 14}" class="label">{h(name)} [{tid}]</text>')
for record in wait_records:
    tid = record['tid']
    if tid not in lane_index:
        continue
    y = top + lane_index[tid] * (lane_height + lane_gap)
    event_id = record.get('event_id', '')
    event_attr = f' data-event-id="{h(event_id)}"' if event_id else ''
    onclick_attr = f' onclick="selectEvent(\'{h(event_id)}\'); return false;" style="cursor:pointer"' if event_id else ''
    if record['wait_start'] is not None and record['wake_time'] is not None and record['wait_ms'] is not None:
        x1 = x_of(record['wait_start'])
        x2 = x_of(record['wake_time'])
        rect_width = max(1.0, x2 - x1)
        tooltip = f"tid={tid} comm={record['comm']} wait_ms={record['wait_ms']:.3f} state={record['prev_state']} kernel_wait_reason={record['kernel_wait_reason']} waker={record['waker_comm']}[{record['waker_tid']}]"
        svg_parts.append(f'<rect x="{x1:.2f}" y="{y:.2f}" width="{rect_width:.2f}" height="{lane_height:.2f}" class="wait"{event_attr}{onclick_attr}><title>{h(tooltip)}</title></rect>')
    if record['wake_time'] is not None and record['run_time'] is not None:
        x1 = x_of(record['wake_time'])
        x2 = x_of(record['run_time'])
        rect_width = max(1.0, x2 - x1)
        tooltip = f"tid={tid} comm={record['comm']} scheduler_delay_ms={record['sched_delay_ms']:.3f} target_cpu={record['target_cpu']}"
        svg_parts.append(f'<rect x="{x1:.2f}" y="{y + 6:.2f}" width="{rect_width:.2f}" height="{max(4.0, lane_height - 12):.2f}" class="delay"{event_attr}{onclick_attr}><title>{h(tooltip)}</title></rect>')
    waker_tid = record.get('waker_tid')
    if waker_tid in lane_index and record['wake_time'] is not None:
        y1 = top + lane_index[waker_tid] * (lane_height + lane_gap) + lane_height / 2
        y2 = top + lane_index[tid] * (lane_height + lane_gap) + lane_height / 2
        x = x_of(record['wake_time'])
        svg_parts.append(f'<line x1="{x:.2f}" y1="{y1:.2f}" x2="{x:.2f}" y2="{y2:.2f}" class="wake"/>')
for migration in migration_records:
    tid = migration['tid']
    if tid not in lane_index:
        continue
    y = top + lane_index[tid] * (lane_height + lane_gap)
    x = x_of(migration['time'])
    tooltip = f"migrate {migration['orig_cpu']} -> {migration['dest_cpu']} tid={tid} {migration['comm']}"
    svg_parts.append(f'<line x1="{x:.2f}" y1="{y:.2f}" x2="{x:.2f}" y2="{y + lane_height:.2f}" class="migrate"><title>{h(tooltip)}</title></line>')
for i in range(11):
    ts = start_time + time_span * i / 10
    x = x_of(ts)
    svg_parts.append(f'<line x1="{x:.2f}" y1="{top - 8}" x2="{x:.2f}" y2="{height - 70}" class="axis"/>')
    svg_parts.append(f'<text x="{x - 25:.2f}" y="{height - 42}" class="minor">{ts:.6f}</text>')
svg_parts.append('</svg>')
svg_text = ''.join(svg_parts)

header_text = f'pid={target_pid} scope={analysis_scope} active_threads={len(active_tids)} long_wait_ms={long_wait_ms}'
if function_name:
    header_text += f' function_name={function_name}'
header_text += f' enable_stacks={enable_stacks} stack_scope={stack_scope}'

topwait_rows = []
for record in top_global:
    eid = record['event_id']
    waker = f"{record['waker_comm']}[{record['waker_tid']}]"
    topwait_rows.append(
        f'<tr id="{h(eid)}" data-event-row="{h(eid)}" onclick="selectEvent(\'{h(eid)}\')" style="cursor:pointer">'
        f'<td><a href="#" onclick="selectEvent(\'{h(eid)}\'); return false;">{h(eid)}</a></td>'
        f'<td>{h(record["comm"])}[{record["tid"]}]</td>'
        f'<td>{record["wait_ms"]:.3f}</td>'
        f'<td>{record["sched_delay_ms"]:.3f}</td>'
        f'<td>{h(record["prev_state"])}</td>'
        f'<td>{h(record["kernel_wait_reason"])}</td>'
        f'<td>{h(waker)}</td>'
        f'<td>{record["wait_start"]:.6f} -&gt; {record["wake_time"]:.6f} -&gt; {record["run_time"]:.6f}</td>'
        '</tr>'
    )

thread_rows = []
for row in per_thread_rows:
    thread_rows.append(
        '<tr>'
        f'<td>{h(row["comm"])}[{row["tid"]}]</td>'
        f'<td>{row["count"]}</td>'
        f'<td>{row["avg_wait"]:.3f}</td>'
        f'<td>{row["max_wait"]:.3f}</td>'
        f'<td>{row["avg_delay"]:.3f}</td>'
        f'<td>{row["max_delay"]:.3f}</td>'
        f'<td>{row["long_waits"]}</td>'
        f'<td>{h(row["top_waker"])}</td>'
        f'<td>{h(row["top_kernel_wait_reason"])}</td>'
        '</tr>'
    )

bucket_html = []
for title, rows in bucket_sections:
    bucket_html.append(f'<h3>{h(title)}</h3>')
    bucket_html.append('<table>')
    bucket_html.append('<tr><th>key</th><th>count</th><th>avg wait ms</th><th>max wait ms</th><th>avg delay ms</th><th>max delay ms</th><th>example events</th></tr>')
    for row in rows:
        links = []
        for event_id in row['example_event_ids']:
            links.append(f'<a href="#" onclick="showTab(\'tab-topwaits\', document.querySelectorAll(\'.tabbtn\')[3]); selectEvent(\'{h(event_id)}\'); return false;">{h(event_id)}</a>')
        bucket_html.append(
            '<tr>'
            f'<td>{h(row["key"])}</td>'
            f'<td>{row["count"]}</td>'
            f'<td>{row["avg_wait"]:.3f}</td>'
            f'<td>{row["max_wait"]:.3f}</td>'
            f'<td>{row["avg_delay"]:.3f}</td>'
            f'<td>{row["max_delay"]:.3f}</td>'
            f'<td>{" ".join(links) if links else "-"}</td>'
            '</tr>'
        )
    bucket_html.append('</table>')

stack_html = []
if not enable_stacks:
    stack_html.append('<p>stack capture was disabled or unavailable</p>')
else:
    for index, record in enumerate(stack_focus, 1):
        eid = record['event_id']
        waker = f"{record['waker_comm']}[{record['waker_tid']}]"
        stack_html.append(
            f'<h3>[{index}] <a href="#" onclick="showTab(\'tab-topwaits\', document.querySelectorAll(\'.tabbtn\')[3]); selectEvent(\'{h(eid)}\'); return false;">{h(eid)}</a> '
            f'{h(record["comm"])}[{record["tid"]}] '
            f'wait_ms={record["wait_ms"]:.3f} '
            f'delay_ms={record["sched_delay_ms"]:.3f} '
            f'kernel_wait_reason={h(record["kernel_wait_reason"])} '
            f'waker={h(waker)}</h3>'
        )
        sleep_event = record.get('sleep_stack_event')
        if sleep_event:
            stack_html.append('<h4>sleep-out kernel stack</h4>')
            stack_html.append(f'<pre>{h(format_stack(sleep_event["kernel_stack"]))}</pre>')
            stack_html.append('<h4>sleep-out user stack</h4>')
            stack_html.append(f'<pre>{h(format_stack(sleep_event["user_stack"]))}</pre>')
        else:
            stack_html.append('<p>sleep-out stack: -</p>')
        wake_event = record.get('wake_stack_event')
        if wake_event:
            stack_html.append('<h4>wakeup kernel stack</h4>')
            stack_html.append(f'<pre>{h(format_stack(wake_event["kernel_stack"]))}</pre>')
            stack_html.append('<h4>wakeup user stack</h4>')
            stack_html.append(f'<pre>{h(format_stack(wake_event["user_stack"]))}</pre>')
        else:
            stack_html.append('<p>wakeup stack: -</p>')

html_parts = []
html_parts.append('<!DOCTYPE html>')
html_parts.append('<html><head><meta charset="utf-8">')
html_parts.append('<title>offcpu wait reasons report</title>')
html_parts.append('<style>body{font-family:monospace;margin:20px;color:#222}table{border-collapse:collapse;margin-top:16px;width:100%}th,td{border:1px solid #bbb;padding:6px 8px;vertical-align:top}th{background:#eee;position:sticky;top:0}pre{background:#f7f7f7;padding:12px;border:1px solid #ddd;white-space:pre-wrap}code{background:#f7f7f7;padding:1px 4px}.small{color:#555;font-size:12px}.tabbar{display:flex;flex-wrap:wrap;gap:8px;margin:18px 0 14px 0}.tabbtn{border:1px solid #bbb;background:#f3f3f3;padding:8px 12px;cursor:pointer;border-radius:6px}.tabbtn.active{background:#ddd;font-weight:bold}.tabpanel{display:none}.tabpanel.active{display:block}.selected-row td{background:#fff3bf}</style>')
html_parts.append('<script>function showTab(id,btn){for(const p of document.querySelectorAll(".tabpanel"))p.classList.remove("active");for(const b of document.querySelectorAll(".tabbtn"))b.classList.remove("active");document.getElementById(id).classList.add("active");btn.classList.add("active");}function selectEvent(eventId){for(const row of document.querySelectorAll("[data-event-row]"))row.classList.remove("selected-row");for(const node of document.querySelectorAll("[data-event-id]"))node.classList.remove("event-highlight");for(const row of document.querySelectorAll(`[data-event-row="${eventId}"]`))row.classList.add("selected-row");for(const node of document.querySelectorAll(`[data-event-id="${eventId}"]`))node.classList.add("event-highlight");const row=document.querySelector(`[data-event-row="${eventId}"]`);if(row)row.scrollIntoView({behavior:"smooth",block:"center"});}</script>')
html_parts.append('</head><body>')
html_parts.append('<h1>offcpu wait reasons report</h1>')
html_parts.append(f'<p>{h(header_text)}</p>')
html_parts.append('<div class="tabbar">')
for tab_id, tab_name, active in [
    ('tab-overview', 'Overview', True),
    ('tab-symbol', 'Symbol Resolution', False),
    ('tab-graph', 'Graph', False),
    ('tab-topwaits', 'Top Waits', False),
    ('tab-threads', 'Thread Summary', False),
    ('tab-buckets', 'Root-Cause Buckets', False),
    ('tab-stacks', 'Stack Focus', False),
    ('tab-sched', 'Scheduler Views', False),
    ('tab-raw', 'Raw Summary', False),
]:
    klass = 'tabbtn active' if active else 'tabbtn'
    html_parts.append(f'<button class="{klass}" onclick="showTab(\'{tab_id}\', this)">{h(tab_name)}</button>')
html_parts.append('</div>')
html_parts.append('<div id="tab-overview" class="tabpanel active"><h2>overview</h2><p>This report keeps only active threads that produced at least one blocked wait in the selected scope.</p><table><tr><th>field</th><th>value</th></tr>')
html_parts.append(f'<tr><td>target pid</td><td>{target_pid}</td></tr>')
html_parts.append(f'<tr><td>scope</td><td>{h(analysis_scope)}</td></tr>')
html_parts.append(f'<tr><td>function name</td><td>{h(function_name if function_name else "-")}</td></tr>')
html_parts.append(f'<tr><td>trace window</td><td>{start_time:.6f} .. {end_time:.6f}</td></tr>')
html_parts.append(f'<tr><td>active threads</td><td>{len(active_tids)}</td></tr>')
html_parts.append(f'<tr><td>stack capture</td><td>{enable_stacks}</td></tr>')
html_parts.append(f'<tr><td>stack scope</td><td>{h(stack_scope)}</td></tr></table>')
html_parts.append('<p class="small">Use the tabs above to switch between visual timeline, bucketed root-cause patterns, stack context, and embedded scheduler text views.</p></div>')
html_parts.append(f'<div id="tab-symbol" class="tabpanel"><h2>symbol resolution</h2><pre>{h(symbol_resolution_text)}</pre></div>')
html_parts.append(f'<div id="tab-graph" class="tabpanel"><h2>wait-wake graph</h2>{svg_text}</div>')
html_parts.append('<div id="tab-topwaits" class="tabpanel"><h2>top longest waits</h2><p class="small">Click a row, a bucket example link, or a graph rectangle to highlight the corresponding evidence in both the table and the graph.</p><table><tr><th>event id</th><th>thread</th><th>wait ms</th><th>delay ms</th><th>state</th><th>kernel wait reason</th><th>waker</th><th>timeline</th></tr>')
html_parts.extend(topwait_rows)
html_parts.append('</table></div>')
html_parts.append('<div id="tab-threads" class="tabpanel"><h2>per-thread summary</h2><table><tr><th>thread</th><th>count</th><th>avg wait ms</th><th>max wait ms</th><th>avg delay ms</th><th>max delay ms</th><th>long waits</th><th>top waker</th><th>top kernel wait reason</th></tr>')
html_parts.extend(thread_rows)
html_parts.append('</table></div>')
html_parts.append('<div id="tab-buckets" class="tabpanel"><h2>root-cause buckets</h2><p class="small">Each bucket row includes links to representative top wait events.</p>')
html_parts.extend(bucket_html)
html_parts.append('</div>')
html_parts.append('<div id="tab-stacks" class="tabpanel"><h2>stack focus</h2>')
html_parts.extend(stack_html)
html_parts.append('</div>')
html_parts.append(f'<div id="tab-sched" class="tabpanel"><h2>scheduler views</h2><pre>{h(scheduler_views_text)}</pre></div>')
html_parts.append(f'<div id="tab-raw" class="tabpanel"><h2>raw summary</h2><pre>{h(summary_text)}</pre></div>')
html_parts.append('</body></html>')

with open(report_file, 'w', encoding='utf-8') as f:
    f.write(''.join(html_parts))
PYBLOCK
}

# Parse arguments.
if [[ $# -eq 1 && ( $1 == -h || $1 == --help ) ]]; then
    print_help
    exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
    print_help >&2
    exit 1
fi

TARGET_PID=$1
if [[ ! $TARGET_PID =~ ^[0-9]+$ ]]; then
    echo "error: pid must be a positive integer" >&2
    exit 1
fi

if [[ $# -eq 2 ]]; then
    FUNCTION_NAME=$2
    ANALYSIS_SCOPE=function
else
    FUNCTION_NAME=
    ANALYSIS_SCOPE=process
fi

# Real user/group for chown after sudo-created files in TEMP_DIR.
REAL_UID=$(id -u)
REAL_GID=$(id -g)

for cmd in perf python3 awk sed grep readelf nm sort uniq bpftrace; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "error: missing command: $cmd" >&2
        exit 1
    fi
done

if ! sudo test -d /proc/$TARGET_PID; then
    echo "error: pid $TARGET_PID does not exist or cannot be accessed" >&2
    exit 1
fi

if [[ ! $CAPTURE_SECONDS =~ ^[0-9]+$ ]]; then
    echo "error: CAPTURE_SECONDS must be a non-negative integer" >&2
    exit 1
fi

if [[ ! $SAMPLE_MS =~ ^[0-9]+$ || $SAMPLE_MS -le 0 ]]; then
    echo "error: SAMPLE_MS must be a positive integer" >&2
    exit 1
fi

if [[ ! $STACK_LIMIT =~ ^[0-9]+$ || $STACK_LIMIT -le 0 ]]; then
    echo "error: STACK_LIMIT must be a positive integer" >&2
    exit 1
fi

if [[ $STACK_SCOPE != all && $STACK_SCOPE != long_wait ]]; then
    echo "error: STACK_SCOPE must be either 'all' or 'long_wait'" >&2
    exit 1
fi

mkdir -p $OUT_DIR || {
    echo "error: failed to create output directory: $OUT_DIR" >&2
    exit 1
}

TEMP_DIR=/tmp/offcpu-wait-reasons
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR" || {
    echo "error: failed to create temporary directory: $TEMP_DIR" >&2
    exit 1
}

# Resolve symbol if needed.
if [[ $ANALYSIS_SCOPE == function ]]; then
    mapfile -t mapped_exec_files < <(
        sudo cat /proc/$TARGET_PID/maps | awk '$3 ~ /x/ && $6 ~ /^\// { print $6 }' | sort -u
    )

    : > $TEMP_DIR/symbol_resolution.txt
    echo "function_name=$FUNCTION_NAME" >> $TEMP_DIR/symbol_resolution.txt
    echo "mapped_executable_file_count=${#mapped_exec_files[@]}" >> $TEMP_DIR/symbol_resolution.txt
    echo >> $TEMP_DIR/symbol_resolution.txt

    prioritized_candidates=()
    for file_path in "${mapped_exec_files[@]}"; do
        [[ -f $file_path ]] || continue
        if [[ -n $FUNCTION_LIBRARY_PATH && $file_path != $FUNCTION_LIBRARY_PATH ]]; then
            continue
        fi
        if ! sudo readelf -h "$file_path" >/dev/null; then
            continue
        fi
        base=${file_path##*/}
        priority=3
        if [[ $base == libnvidia-glcore.so || $base == libnvidia-glcore.so.* ]]; then
            priority=1
        elif [[ $base == libnvidia-*.so || $base == libnvidia-*.so.* ]]; then
            priority=2
        fi
        prioritized_candidates+=("$priority|$file_path")
    done

    if [[ ${#prioritized_candidates[@]} -gt 0 ]]; then
        mapfile -t prioritized_candidates < <(printf "%s\n" "${prioritized_candidates[@]}" | sort -t'|' -k1,1n -k2,2)
    else
        prioritized_candidates=()
    fi

    echo "candidate_search_order:" >> $TEMP_DIR/symbol_resolution.txt
    for item in "${prioritized_candidates[@]}"; do
        echo "  $item" >> $TEMP_DIR/symbol_resolution.txt
    done
    echo >> $TEMP_DIR/symbol_resolution.txt

    resolved_candidates=()
    candidate_index=0
    for item in "${prioritized_candidates[@]}"; do
        file_path=${item#*|}
        found=0
        if sudo readelf -Ws "$file_path" | awk -v sym=$FUNCTION_NAME '$8 == sym { found = 1 } END { exit(found ? 0 : 1) }'; then
            found=1
        fi
        if [[ $found -eq 0 ]] && sudo nm -D --defined-only "$file_path" | awk -v sym=$FUNCTION_NAME '$3 == sym { found = 1 } END { exit(found ? 0 : 1) }'; then
            found=1
        fi
        if [[ $found -eq 0 ]] && sudo nm -a "$file_path" | awk -v sym=$FUNCTION_NAME '$NF == sym { found = 1 } END { exit(found ? 0 : 1) }'; then
            found=1
        fi
        if [[ $found -eq 1 ]]; then
            candidate_index=$((candidate_index + 1))
            resolved_candidates+=("$file_path")
            echo "matched_candidate[$candidate_index]=$file_path" >> $TEMP_DIR/symbol_resolution.txt
        fi
    done

    echo >> $TEMP_DIR/symbol_resolution.txt

    if [[ ${#resolved_candidates[@]} -eq 0 ]]; then
        echo "resolution_status=failed" >> $TEMP_DIR/symbol_resolution.txt
        echo "reason=no mapped executable ELF exported the requested symbol" >> $TEMP_DIR/symbol_resolution.txt
        echo "error: failed to resolve symbol '$FUNCTION_NAME' from target process executable mappings" >&2
        exit 1
    fi

    RESOLVED_FUNCTION_LIBRARY=${resolved_candidates[0]}
    echo "resolution_status=success" >> $TEMP_DIR/symbol_resolution.txt
    echo "selected_library=$RESOLVED_FUNCTION_LIBRARY" >> $TEMP_DIR/symbol_resolution.txt
    if [[ ${#resolved_candidates[@]} -gt 1 ]]; then
        echo "note=multiple mapped files exported the same symbol; the first matched candidate was selected after priority ordering" >> $TEMP_DIR/symbol_resolution.txt
    fi
else
    echo "analysis_scope=process" > $TEMP_DIR/symbol_resolution.txt
    echo "function_name=-" >> $TEMP_DIR/symbol_resolution.txt
    echo "resolution_status=not_applicable" >> $TEMP_DIR/symbol_resolution.txt
fi

echo "target pid      : $TARGET_PID"
echo "scope           : $ANALYSIS_SCOPE"
echo "capture seconds : $CAPTURE_SECONDS"
echo "sample ms       : $SAMPLE_MS"
echo "long wait ms    : $LONG_WAIT_MS"
echo "enable stacks   : $ENABLE_STACKS"
echo "stack scope     : $STACK_SCOPE"
echo "stack limit     : $STACK_LIMIT"
echo "out dir         : $OUT_DIR"
if [[ $ANALYSIS_SCOPE == function ]]; then
    echo "function name   : $FUNCTION_NAME"
    echo "function library: $RESOLVED_FUNCTION_LIBRARY"
fi
echo

if [[ $ANALYSIS_SCOPE == function ]]; then
    cat > $TEMP_DIR/trace_function.bt <<EOFUNC
BEGIN
{
    printf("kind\tts_ns\ttid\tcomm\n");
}

uprobe:$RESOLVED_FUNCTION_LIBRARY:$FUNCTION_NAME
/pid == $TARGET_PID/
{
    @depth[tid] = @depth[tid] + 1;
    printf("enter\t%llu\t%d\t%s\n", nsecs, tid, comm);
}

uretprobe:$RESOLVED_FUNCTION_LIBRARY:$FUNCTION_NAME
/pid == $TARGET_PID/
{
    printf("exit\t%llu\t%d\t%s\n", nsecs, tid, comm);
    if (@depth[tid] > 0) {
        @depth[tid] = @depth[tid] - 1;
    }
}
EOFUNC
fi

if [[ $ENABLE_STACKS -eq 1 ]]; then
    cat > $TEMP_DIR/trace_stacks.bt <<EOSTACK
BEGIN
{
    printf("ready\n");
}

tracepoint:sched:sched_switch
/args->prev_pid > 0 && pid == $TARGET_PID/
{
    printf("EVENT_BEGIN\n");
    printf("kind=switch_out\n");
    printf("ts_ns=%llu\n", nsecs);
    printf("cpu=%d\n", cpu);
    printf("actor_tid=%d\n", args->prev_pid);
    printf("actor_comm=%s\n", args->prev_comm);
    printf("target_tid=%d\n", args->next_pid);
    printf("target_comm=%s\n", args->next_comm);
    printf("prev_state=%s\n", args->prev_state);
    printf("KERNEL_STACK_BEGIN\n");
    print(kstack($STACK_LIMIT));
    printf("KERNEL_STACK_END\n");
    printf("USER_STACK_BEGIN\n");
    print(ustack($STACK_LIMIT));
    printf("USER_STACK_END\n");
    printf("EVENT_END\n");
}

tracepoint:sched:sched_wakeup,
tracepoint:sched:sched_wakeup_new
/args->pid > 0 && pid == $TARGET_PID/
{
    printf("EVENT_BEGIN\n");
    printf("kind=wakeup\n");
    printf("ts_ns=%llu\n", nsecs);
    printf("cpu=%d\n", cpu);
    printf("actor_tid=%d\n", tid);
    printf("actor_comm=%s\n", comm);
    printf("target_tid=%d\n", args->pid);
    printf("target_comm=%s\n", args->comm);
    printf("target_cpu=%d\n", args->target_cpu);
    printf("KERNEL_STACK_BEGIN\n");
    print(kstack($STACK_LIMIT));
    printf("KERNEL_STACK_END\n");
    printf("USER_STACK_BEGIN\n");
    print(ustack($STACK_LIMIT));
    printf("USER_STACK_END\n");
    printf("EVENT_END\n");
}
EOSTACK
fi

if [[ $ANALYSIS_SCOPE == function ]]; then
    sudo bpftrace "$TEMP_DIR/trace_function.bt" > "$TEMP_DIR/function_trace.tsv" &
    function_trace_pid=$!
    sleep 0.2
    if ! kill -0 $function_trace_pid; then
        echo "error: failed to start function trace bpftrace" >&2
        exit 1
    fi
else
    printf "kind\tts_ns\ttid\tcomm\n" > $TEMP_DIR/function_trace.tsv
fi

if [[ $ENABLE_STACKS -eq 1 ]]; then
    sudo bpftrace "$TEMP_DIR/trace_stacks.bt" > "$TEMP_DIR/stack_events.txt" &
    stack_trace_pid=$!
    sleep 0.2
    if ! kill -0 $stack_trace_pid; then
        echo "warning: failed to start stack trace bpftrace, continuing without stacks" >&2
        ENABLE_STACKS=0
        : > $TEMP_DIR/stack_events.txt
    fi
else
    : > $TEMP_DIR/stack_events.txt
fi

sample_kernel_wait_reasons

sleep 0.1
if ! kill -0 $kernel_wait_reason_sampler_pid; then
    echo "error: failed to start kernel wait reason sampler" >&2
    exit 1
fi

sudo perf record -a \
    -o "$TEMP_DIR/perf_sched.data" \
    -e sched:sched_switch \
    -e sched:sched_wakeup \
    -e sched:sched_wakeup_new \
    -e sched:sched_migrate_task \
    --timestamp-filename &
perf_pid=$!

sleep 0.2
if ! kill -0 $perf_pid; then
    echo "error: failed to start perf record" >&2
    exit 1
fi

if [[ $CAPTURE_SECONDS -gt 0 ]]; then
    (
        sleep $CAPTURE_SECONDS
        kill -INT $perf_pid
    ) &
    timeout_pid=$!
    echo "Capturing for $CAPTURE_SECONDS seconds (or until target process exits)..."
else
    echo "Capturing until interrupted by Ctrl-C..."
fi

# Wait until perf is stopped (by timeout, or by Ctrl-C when CAPTURE_SECONDS=0). Do not wait for target process.
while kill -0 $perf_pid; do
    sleep 0.2
done

kill -INT $perf_pid
wait $perf_pid

kill -INT $function_trace_pid
wait $function_trace_pid

kill -INT $stack_trace_pid
wait $stack_trace_pid

kill -TERM $kernel_wait_reason_sampler_pid
wait $kernel_wait_reason_sampler_pid

echo "Post-processing (perf script, report generation)..."
# Handle missing or empty perf data: skip perf script and produce minimal report.
if [[ ! -f "$TEMP_DIR/perf_sched.data" || ! -s "$TEMP_DIR/perf_sched.data" ]]; then
    echo "warning: no perf data captured (perf_sched.data missing or empty), generating minimal report" >&2
    : > "$TEMP_DIR/perf_script.txt"
else
    if ! sudo perf script -i "$TEMP_DIR/perf_sched.data" \
        -F comm,pid,tid,cpu,time,event,trace > "$TEMP_DIR/perf_script.txt"; then
        echo "warning: perf script failed, generating minimal report" >&2
        : > "$TEMP_DIR/perf_script.txt"
    fi
fi

# Make sudo-created files in TEMP_DIR readable by the current user for the Python postprocessor.
sudo chown -R $REAL_UID:$REAL_GID "$TEMP_DIR" || true

# Scheduler views require valid perf data; otherwise write a placeholder.
if [[ -f "$TEMP_DIR/perf_sched.data" && -s "$TEMP_DIR/perf_sched.data" ]]; then
    {
        echo "===== perf sched timehist ====="
        sudo perf sched timehist -i "$TEMP_DIR/perf_sched.data" -p $TARGET_PID -w -M -n --state -S || true
        echo
        echo "===== perf sched latency ====="
        sudo perf sched latency -i "$TEMP_DIR/perf_sched.data" -p || true
        echo
        echo "===== perf sched map ====="
        sudo perf sched map -i "$TEMP_DIR/perf_sched.data" --compact || true
    } > "$TEMP_DIR/scheduler_views.txt"
else
    echo "perf data not available (perf_sched.data missing or empty)" > "$TEMP_DIR/scheduler_views.txt"
fi

if ! run_python_postprocessor; then
    echo "error: Python post-processing failed" >&2
    exit 1
fi

echo "generated: $OUT_DIR/out_report.html"
