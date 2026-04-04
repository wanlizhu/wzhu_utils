#!/usr/bin/env bash
set -o pipefail
source ~/.bashrc_extended

WAIT_SECONDS=0 # delay before perf recording starts.
RECORD_SECONDS=5 # recording duration in seconds.
TRACE_WAKERS=true
LOCK_CONTENTION=true
INSTALL_DEBUG_SYMBOL=false
SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")
unset PID COMM

while (( $# )); do
    case $1 in
        -wait=*) WAIT_SECONDS=${1#-wait=} ;;
        -record=*) RECORD_SECONDS=${1#-record=} ;;
        *) break ;;
    esac
    shift
 done

if ! sudo -n true 2>/dev/null; then
    echo_in_red "Error: NOPASSWD is NOT enabled for $(id -un)"
    echo_in_red "Aborting"
    exit 1
fi

# Avoid "Too many open files" / "stack traces lost" (tool opens /proc/PID/root per sample).
[[ $(ulimit -n 2>/dev/null) -lt 65536 ]] 2>/dev/null && ulimit -n 65536 2>/dev/null || true

# Install required tools on demand.
[[ -z $(which perf) ]] && sudo apt install -y linux-tools-$(uname -r) linux-cloud-tools-$(uname -r) linux-tools-generic linux-cloud-tools-generic
[[ -z $(which flamegraph.pl) ]] && git clone https://github.com/brendangregg/FlameGraph.git /tmp/fg && sudo cp -f /tmp/fg/*.pl /usr/local/bin/

# Delay before recording starts.
if (( WAIT_SECONDS > 0 )); then
    echo_in_cyan "Wait $WAIT_SECONDS seconds before recording"
    sleep $WAIT_SECONDS
fi

# Resolve the target process or launch a new command.
if [[ ! -z $1 ]]; then
    if [[ $1 =~ ^[0-9]+$ ]]; then
        PID=$1
    elif [[ $1 == steam && ! -z $(pidof steam) ]]; then
        pstree -aspT $(pidof steam)
        read -p "Select steam game PID: " PID
    else
        "$@" >$HOME/profiling-logs.txt 2>&1 &
        PID=$!
        echo_in_green "Launched and detached process $PID"
    fi

    # Resolve the command name of the target process.
    COMM=$(cat /proc/$PID/comm 2>/dev/null)
    [[ -z $COMM ]] && COMM=untitled

    # Install debug symbol packages for the target process.
    if [[ ! -z $(which find-dbgsym-packages) ]]; then 
        echo_in_cyan "Dumping dbgsym packages to $HOME/${COMM}_dbgsym_packages.txt"
        [[ ! -z $(which find-dbgsym-packages) ]] && find-dbgsym-packages $PID 2>/dev/null | tr ' ' '\n' >$HOME/${COMM}_dbgsym_packages.txt
        [[ ! -s $HOME/${COMM}_dbgsym_packages.txt ]] && rm -f $HOME/${COMM}_dbgsym_packages.txt
    fi 
    if [[ $INSTALL_DEBUG_SYMBOL == true && -f $HOME/${COMM}_dbgsym_packages.txt ]]; then
        echo_in_cyan "Installing debug symbols for process $PID..."
        cat $HOME/${COMM}_dbgsym_packages.txt | while read -r pkg; do
            find_or_install $pkg
        done
    fi
fi

# Remove previous output from earlier runs so the new result is easier to inspect.
sudo rm -rf /tmp/offwake.folded $HOME/${COMM}_waitgraph.svg $HOME/${COMM}_tid*_waitgraph.svg $HOME/${COMM}_wakers.txt $HOME/${COMM}_lock_contention.txt $HOME/${COMM}_profiling_stderr.log

# Running waker tracer in background (tracepoint sched:sched_waking; logs who wakes the target).
WAKER_PID=
if [[ $TRACE_WAKERS == true ]]; then
    # Pass PID (main thread) then up to 9 more tids so we catch wakeups for any thread in the process.
    WAKER_TIDS="$PID $(ls /proc/$PID/task 2>/dev/null | grep -v "^${PID}$" | sort -n | head -9 | tr '\n' ' ')"
    echo_in_cyan "[Detached] Running waker tracer (bpftrace) for $RECORD_SECONDS seconds -> $HOME/${COMM}_wakers.txt"
    (
        echo "timestamp_sec,waker_pid,waker_comm,waker_tid,woke_tid"
        sudo timeout $RECORD_SECONDS bpftrace "$SCRIPT_DIR/trace-wakers-bpftrace.bt" $WAKER_TIDS 2>>"$HOME/${COMM}_profiling_stderr.log"
    ) >$HOME/${COMM}_wakers.txt &
    WAKER_PID=$!
fi

# Run lock contention in parallel. Use BPF if built-in, else record + report.
LOCK_PID=
if [[ $LOCK_CONTENTION == true ]]; then
    if [[ ! -z $(perf lock contention -h 2>&1 | grep "no BUILD_BPF_SKEL") ]]; then
        # perf was built without BPF skeleton; use two-step record then report.
        echo_in_cyan "[Detached] Running perf lock record (without BPF) -p $PID for $RECORD_SECONDS seconds -> $HOME/${COMM}_lock_contention.txt"
        (
            sudo perf lock record -p $PID -o /tmp/perf_lock_$$.data sleep $RECORD_SECONDS 2>>"$HOME/${COMM}_profiling_stderr.log"
            if [[ -f /tmp/perf_lock_$$.data ]]; then
                sudo perf lock contention -i /tmp/perf_lock_$$.data 2>&1 | tee $HOME/${COMM}_lock_contention.txt
                sudo rm -f /tmp/perf_lock_$$.data
            else
                echo "perf lock record produced no data (no lock events?). Check $HOME/${COMM}_profiling_stderr.log" >>$HOME/${COMM}_lock_contention.txt
            fi
        ) &
        LOCK_PID=$!
    else
        echo_in_cyan "[Detached] Running perf lock contention --use-bpf -p $PID for $RECORD_SECONDS seconds -> $HOME/${COMM}_lock_contention.txt"
        sudo timeout $RECORD_SECONDS perf lock contention --use-bpf -p $PID -a 2>&1 | tee $HOME/${COMM}_lock_contention.txt &
        LOCK_PID=$!
    fi
fi

# Start sampling (requires a target PID; pass a numeric PID or use steam/command launch above).
echo_in_cyan "Sampling $COMM ($PID) for $RECORD_SECONDS seconds ..."
sudo offwaketime-bpfcc -p $PID -f $RECORD_SECONDS >/tmp/offwake.folded || exit 1

# Wait for background jobs (they use the same duration, so they exit on their own).
[[ -n $WAKER_PID ]] && wait $WAKER_PID 2>/dev/null || true
[[ -n $LOCK_PID ]] && wait $LOCK_PID 2>/dev/null || true

# Ensure lock contention file is never left empty (perf often has no output for futex/GPU workloads).
if [[ $LOCK_CONTENTION == true ]] && [[ -n "$COMM" ]]; then
    LOCKFILE="$HOME/${COMM}_lock_contention.txt"
    if [[ -f "$LOCKFILE" ]] && ! grep -q . "$LOCKFILE" 2>/dev/null; then
        printf '%s\n' \
            "No lock contention events recorded for this run." \
            "" \
            "perf lock tracks mutex/rwsem/spinlock; many waits (futex, GPU, Wayland) do not appear here." \
            "How to investigate those waits:" \
            "  1. Off-CPU flamegraph (${COMM}_waitgraph.svg) – where time is spent waiting (futex_wait, drm_*, etc.)." \
            "  2. Wakers file (${COMM}_wakers.txt) – which process/thread wakes this one (e.g. Xwayland, compositor)." \
            "  3. See profiling/offcpu/INVESTIGATE-WAITS.md for futex/GPU/Wayland-specific steps." \
            "" \
            "To try system-wide lock recording: sudo perf lock record -a sleep 10 && sudo perf lock contention -i perf.data" \
            > "$LOCKFILE"
    fi
fi

# Post-process: convert folded stacks into flame graph.
if [[ -f /tmp/offwake.folded ]]; then
    cat /tmp/offwake.folded | flamegraph.pl >$HOME/${COMM}_waitgraph.svg && echo "Generated $HOME/${COMM}_waitgraph.svg"

    # If the process has multiple threads, also generate one SVG per thread.
    if [[ -d /proc/$PID/task ]] && (( $(ls /proc/$PID/task 2>/dev/null | wc -l) > 1 )); then
        echo >/dev/null 
        # TODO
    fi
fi

# Post-process: show waker output (top 3 waker names with % of total wakeups)
if [[ $TRACE_WAKERS == true ]] && [[ -f "$HOME/${COMM}_wakers.txt" ]]; then
    TOP3=
    if [[ $(wc -l <"$HOME/${COMM}_wakers.txt") -gt 1 ]]; then
        # Total wakeup count for percentage; then top 3 by count with name and %.
        WAKER_TOTAL=$(awk -F',' 'NR>1 { n[$2]++ } END { t=0; for (p in n) t+=n[p]; print t+0 }' "$HOME/${COMM}_wakers.txt")
        TOP3=$(awk -F',' 'NR>1 { n[$2]++ }
            END { for (p in n) print n[p], p }' "$HOME/${COMM}_wakers.txt" | sort -rn | head -3 | awk -v total="$WAKER_TOTAL" '
            {
                count = $1
                pid = $2
                comm = ""
                if ((getline comm < ("/proc/" pid "/comm")) > 0) {
                    close("/proc/" pid "/comm")
                    gsub(/\r?\n$/, "", comm)
                }
                if (comm == "") {
                    if (pid == 0) comm = "swapper (idle)"
                    else comm = "pid:" pid
                }
                pct = (total > 0) ? sprintf("%.0f", count * 100 / total) : 0
                printf "%s%s (%s%%)", (NR > 1 ? ", " : ""), comm, pct
            }')
    fi
    if [[ -n "$TOP3" ]]; then
        echo_in_green "Generated $HOME/${COMM}_wakers.txt ($TOP3)"
    else
        echo_in_green "Generated $HOME/${COMM}_wakers.txt (no wakeup events captured)"
        if [[ -f "$HOME/${COMM}_profiling_stderr.log" ]] && [[ -s "$HOME/${COMM}_profiling_stderr.log" ]]; then
            echo_in_red "  Check for errors: $HOME/${COMM}_profiling_stderr.log"
            tail -5 "$HOME/${COMM}_profiling_stderr.log" | sed 's/^/  /'
        fi
    fi
fi

# Post-process: show lock contention output
if [[ $LOCK_CONTENTION == true ]] && [[ -f "$HOME/${COMM}_lock_contention.txt" ]]; then
    if head -1 "$HOME/${COMM}_lock_contention.txt" 2>/dev/null | grep -q "No lock contention"; then
        echo_in_green "Generated $HOME/${COMM}_lock_contention.txt (no lock events; see file for explanation)"
    else
        echo_in_green "Generated $HOME/${COMM}_lock_contention.txt"
    fi
fi