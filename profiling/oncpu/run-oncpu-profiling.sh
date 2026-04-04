#!/usr/bin/env bash
set -o pipefail

WAIT_SECONDS=0 # delay before perf recording starts.
RECORD_SECONDS=5 # perf recording duration in seconds.
RECORD_FREQ=1000 # perf sampling frequency in Hz.
UNWIND_METHOD=dwarf # dwarf or fp (frame pointer)
INSTALL_DEBUG_SYMBOL=false
SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")
unset PID COMM

while (( $# )); do
    case $1 in
        -wait=*) WAIT_SECONDS=${1#-wait=} ;;
        -record=*) RECORD_SECONDS=${1#-record=} ;;
        -freq=*) RECORD_FREQ=${1#-freq=} ;;
        -unwind=*) UNWIND_METHOD=${1#-unwind=} ;;
        -dbgsym=*) INSTALL_DEBUG_SYMBOL=${1#-dbgsym=} ;;
        *) break ;;
    esac
    shift
 done

[[ "$RECORD_SECONDS" =~ ^[0-9]+$ ]] && [[ $RECORD_SECONDS -gt 0 ]] || { echo "run-oncpu-profiling.sh: RECORD_SECONDS must be a positive integer" >&2; exit 1; }
[[ "$RECORD_FREQ" =~ ^[0-9]+$ ]] && [[ $RECORD_FREQ -gt 0 ]] || { echo "run-oncpu-profiling.sh: RECORD_FREQ must be a positive integer" >&2; exit 1; }
[[ "$UNWIND_METHOD" == "dwarf" || "$UNWIND_METHOD" == "fp" ]] || { echo "run-oncpu-profiling.sh: UNWIND_METHOD must be 'dwarf' or 'fp'" >&2; exit 1; }

if ! sudo -n true 2>/dev/null; then
    echo_in_red "Error: NOPASSWD is NOT enabled for $(id -un)"
    echo_in_red "Aborting"
    exit 1
fi

# Print a few kernel knobs that commonly affect perf usability and symbol visibility.
echo "=== sysctl knobs (runtime kernel params) ==="
echo "/proc/sys/kernel/perf_event_paranoid => $(cat /proc/sys/kernel/perf_event_paranoid)"
echo "/proc/sys/kernel/kptr_restrict => $(cat /proc/sys/kernel/kptr_restrict)"
echo "/proc/sys/kernel/perf_event_max_sample_rate => $(cat /proc/sys/kernel/perf_event_max_sample_rate)"
echo

# Avoid "Too many open files" / "stack traces lost" (tool opens /proc/PID/root per sample).
[[ $(ulimit -n 2>/dev/null) -lt 65536 ]] 2>/dev/null && ulimit -n 65536 2>/dev/null || true

# Install required tools on demand.
[[ -z $(which eu-stack) ]] && sudo apt install -y elfutils >/dev/null 2>&1
[[ -z $(which perf) ]] && sudo apt install -y linux-tools-$(uname -r) linux-cloud-tools-$(uname -r) linux-tools-generic linux-cloud-tools-generic
[[ -z $(which flamegraph.pl) ]] && git clone https://github.com/brendangregg/FlameGraph.git /tmp/fg && sudo cp -f /tmp/fg/*.pl /usr/local/bin/

# Delay before recording starts.
if (( WAIT_SECONDS > 0 )); then
    echo_in_cyan "Wait $WAIT_SECONDS seconds before recording"
    sleep $WAIT_SECONDS
fi

# Resolve the target process or launch a new command.
PID_TO_KILL=
if [[ ! -z $1 ]]; then
    if [[ $1 =~ ^[0-9]+$ ]]; then
        PID=$1
        echo_in_cyan "Received PID: $PID"
    elif [[ $1 == steam && ! -z $(pidof steam) ]]; then
        pstree -aspT $(pidof steam)
        read -p "Select steam game PID: " PID
    else
        "$@" >$HOME/profiling-logs.txt 2>&1 &
        PID=$!
        PID_TO_KILL=$PID 
        echo_in_cyan "Launched and detached process $PID"
    fi

    # Resolve the command name of the target process.
    COMM=$(cat /proc/$PID/comm 2>/dev/null)
    [[ -z $COMM ]] && COMM=untitled

    # Install debug symbol packages for the target process.
    if [[ $INSTALL_DEBUG_SYMBOL == true && -f $HOME/${COMM}_dbgsym_packages.txt ]]; then
        if [[ ! -z $(which find-dbgsym-packages) ]]; then 
            echo_in_cyan "Dumping dbgsym packages to $HOME/${COMM}_dbgsym_packages.txt"
            find-dbgsym-packages $PID 2>/dev/null | tr ' ' '\n' >$HOME/${COMM}_dbgsym_packages.txt
            [[ ! -s $HOME/${COMM}_dbgsym_packages.txt ]] && rm -f $HOME/${COMM}_dbgsym_packages.txt
        fi 
        echo_in_cyan "Installing debug symbols for process $PID..."
        cat $HOME/${COMM}_dbgsym_packages.txt | while read -r pkg; do
            find_or_install $pkg
        done
    fi
fi

# Guardian: ensure required inputs for perf-record-and-postprocess.sh are set and valid.
[[ -z "$COMM" ]] && COMM=untitled

# Refresh $HOME/system_info.txt for the merged HTML report (generate-html-report.sh).
if [[ ! -z $(which collect-system-info.sh 2>/dev/null) ]]; then
    collect-system-info.sh >/dev/null 
fi

# Perf record and postprocess (flamegraphs); HTML report is generated inside when applicable.
. "$SCRIPT_DIR/perf-record-and-postprocess.sh"

if [[ ! -z $PID_TO_KILL && -d /proc/$PID_TO_KILL ]]; then 
    sudo kill $PID_TO_KILL || sudo kill -9 $PID_TO_KILL
    echo_in_green "Killed $PID_TO_KILL"
fi 