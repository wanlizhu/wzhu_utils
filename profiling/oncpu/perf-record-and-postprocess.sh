#!/usr/bin/env bash
# Called from run-oncpu-profiling.sh in the same dir. Do not run directly.
# Expects: PID, COMM, RECORD_SECONDS, RECORD_FREQ, UNWIND_METHOD (from run-oncpu-profiling.sh).

set -o pipefail

# Guardian: required variables and values.
: "${COMM:?perf-record-and-postprocess.sh: COMM must be set (e.g. from run-oncpu-profiling.sh)}"
: "${RECORD_SECONDS:?perf-record-and-postprocess.sh: RECORD_SECONDS must be set}"
: "${RECORD_FREQ:?perf-record-and-postprocess.sh: RECORD_FREQ must be set}"
: "${UNWIND_METHOD:?perf-record-and-postprocess.sh: UNWIND_METHOD must be set}"
[[ "$RECORD_SECONDS" =~ ^[0-9]+$ ]] && [[ $RECORD_SECONDS -gt 0 ]] || { echo "perf-record-and-postprocess.sh: RECORD_SECONDS must be a positive integer" >&2; exit 1; }
[[ "$RECORD_FREQ" =~ ^[0-9]+$ ]] && [[ $RECORD_FREQ -gt 0 ]] || { echo "perf-record-and-postprocess.sh: RECORD_FREQ must be a positive integer" >&2; exit 1; }
[[ "$UNWIND_METHOD" == "dwarf" || "$UNWIND_METHOD" == "fp" ]] || { echo "perf-record-and-postprocess.sh: UNWIND_METHOD must be 'dwarf' or 'fp'" >&2; exit 1; }

SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")

# Remove previous output from earlier runs so the new result is easier to inspect.
# Per-thread SVGs live in /tmp; combined flamegraph and HTML report in $HOME.
sudo rm -rf /tmp/perf.data /tmp/${COMM}_thread*_flamegraph.svg \
  $HOME/system_flamegraph.svg $HOME/${COMM}_flamegraph.svg $HOME/${COMM}_thread*_flamegraph.svg $HOME/${COMM}_flamegraph_tabs.html

# Start sampling
echo "Sampling $COMM ($PID) for $RECORD_SECONDS seconds ..."
sudo perf record $([[ -z $PID ]] && echo "-a" || echo "--pid=$PID") --freq=$RECORD_FREQ -g --call-graph $UNWIND_METHOD -o /tmp/perf.data -- sleep $RECORD_SECONDS

# Post-process perf.data into flame graphs.
if [[ -f /tmp/perf.data ]]; then
    sudo perf script --no-inline --force -F +pid -i /tmp/perf.data >/tmp/perf.txt
    chmod 666 /tmp/perf.txt

    # In case of system-wide flamegraph
    if [[ -z $PID ]]; then
        cat /tmp/perf.txt | stackcollapse-perf.pl 2>/dev/null | stackcollapse-recursive.pl 2>/dev/null | flamegraph.pl >$HOME/system_flamegraph.svg && echo "Generated $HOME/system_flamegraph.svg"
    else
        cat /tmp/perf.txt | stackcollapse-perf.pl 2>/dev/null | stackcollapse-recursive.pl 2>/dev/null | flamegraph.pl >$HOME/${COMM}_flamegraph.svg && echo "Generated $HOME/${COMM}_flamegraph.svg"

        # Per-thread flamegraphs and tabbed HTML (when multiple threads) are generated here.
        . "$SCRIPT_DIR/generate-perthread-flamegraph.sh"
    fi
fi
