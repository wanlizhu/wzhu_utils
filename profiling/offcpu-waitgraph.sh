#!/usr/bin/env bash

set -o pipefail

NAME_PREFIX=
WAIT_SECONDS=0 # delay before perf recording starts.
RECORD_SECONDS=5 # recording duration in seconds.
unset PID COMM

while (( $# )); do
    case $1 in
        -name=*) NAME_PREFIX=${1#-name=} ;;
        -wait=*) WAIT_SECONDS=${1#-wait=} ;;
        -record=*) RECORD_SECONDS=${1#-record=} ;;
        *) break ;;
    esac
    shift
 done

if ! sudo -n true 2>/dev/null; then
    echo "Error: NOPASSWD is NOT enabled for $(id -un)"
    echo "Aborting"
    exit 1
fi

# Avoid "Too many open files" / "stack traces lost" (tool opens /proc/PID/root per sample).
[[ $(ulimit -n 2>/dev/null) -lt 65536 ]] 2>/dev/null && ulimit -n 65536 2>/dev/null || true

# Install required tools on demand.
[[ -z $(which perf) ]] && sudo apt install -y linux-tools-$(uname -r) linux-cloud-tools-$(uname -r) linux-tools-generic linux-cloud-tools-generic
[[ -z $(which flamegraph.pl) ]] && git clone https://github.com/brendangregg/FlameGraph.git /tmp/fg && sudo cp -f /tmp/fg/*.pl /usr/local/bin/

# Delay before recording starts.
if (( WAIT_SECONDS > 0 )); then
    echo "Wait $WAIT_SECONDS seconds before recording"
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
        echo "Launched and detached process $PID"
    fi

    # Resolve the command name of the target process.
    COMM=$(cat /proc/$PID/comm 2>/dev/null)
    [[ -z $COMM ]] && COMM=untitled

    # Install debug symbol packages for the target process.
    [[ ! -z $(which find-dbgsym-packages) ]] && find-dbgsym-packages $PID 2>/dev/null | tr ' ' '\n' >$HOME/${COMM}_dbgsym_packages.txt
    if [[ $INSTALL_DEBUG_SYMBOL == true ]]; then
        echo "Installing debug symbols for process $PID..."
        cat $HOME/${COMM}_dbgsym_packages.txt | while read -r pkg; do
            install-pkg.sh $pkg
        done
    fi
fi

# Remove previous output from earlier runs so the new result is easier to inspect.
sudo rm -rf /tmp/offwake.folded $HOME/${COMM}_waitgraph.svg $HOME/${COMM}_tid*_waitgraph.svg

# Start sampling (requires a target PID; pass a numeric PID or use steam/command launch above).
echo "Sampling $COMM ($PID) for $RECORD_SECONDS seconds ..."
sudo offwaketime-bpfcc -p $PID -f $RECORD_SECONDS >/tmp/offwake.folded || exit 1

# Post-process folded stacks into flame graph.
if [[ -f /tmp/offwake.folded ]]; then
    cat /tmp/offwake.folded | flamegraph.pl >$HOME/${COMM}_waitgraph.svg && echo "Generated $HOME/${COMM}_waitgraph.svg"

    # If the process has multiple threads, also generate one SVG per thread.
    if [[ -d /proc/$PID/task ]] && (( $(ls /proc/$PID/task 2>/dev/null | wc -l) > 1 )); then
        echo "$COMM ($PID) has $(ls /proc/$PID/task 2>/dev/null | wc -l) threads"
        # TODO 
    fi 
fi 