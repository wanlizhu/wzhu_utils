#!/usr/bin/env bash
# for steam launch options: gnome-terminal -- bash -lc '$HOME/wanliz_tools/profiling/generate-flamegraph.sh %command% > $HOME/steam-logs.txt'
set -o pipefail 

WAIT_SECONDS=5
RECORD_SECONDS=5
USE_EU_STACK=false # true or false
UNWIND_METHOD=fp # dwarf or fp (frame pointer) 
export DEBUGINFOD_URLS="https://debuginfod.ubuntu.com"

if ! sudo -n true 2>/dev/null; then 
    echo "NOPASSWD is NOT enabled for $(id -un)"
    echo "Aborting"
    exit 1
fi 

echo "=== sysctl knobs (runtime kernel params) ==="
echo "/proc/sys/kernel/perf_event_paranoid => $(cat /proc/sys/kernel/perf_event_paranoid)"
echo "/proc/sys/kernel/kptr_restrict => $(cat /proc/sys/kernel/kptr_restrict)"
echo "/proc/sys/kernel/kptr_restrict => $(cat /proc/sys/kernel/perf_event_max_sample_rate)"
echo 

[[ -z $(which eu-stack) ]] && sudo apt install -y elfutils >/dev/null 2>&1
[[ -z $(which perf) ]] && sudo apt install -y linux-tools-$(uname -r) linux-cloud-tools-$(uname -r) linux-tools-generic linux-cloud-tools-generic
[[ -z $(which flamegraph.pl) ]] && git clone https://github.com/brendangregg/FlameGraph.git /tmp/fg && sudo cp -f /tmp/fg/*.pl /usr/local/bin/ 

if [[ ! -z $1 ]]; then
    if [[ $1 =~ ^[0-9]+$ ]]; then 
        PID=$1
    elif [[ $1 == steam && ! -z $(pidof steam) ]]; then 
        pstree -aspT $(pidof steam)
        read -p "Input steam game PID: " PID
    else 
        "$@" >$HOME/profiling-logs.txt 2>&1 & 
        PID=$!
        echo "Detached process $PID"
    fi 
    
    # install debug symbols for PID
    if [[ ! -f /tmp/$(cat /proc/$PID/comm)-dbgsym-installed && ! -z $(which find-dbgsym-packages) ]]; then 
        echo "Installing debug symbols for process $PID..."
        find-dbgsym-packages $PID 2>/dev/null | tr ' ' '\n' | while read -r pkg; do
            sudo apt install -y $pkg 
        done
        touch /tmp/$(cat /proc/$PID/comm)-dbgsym-installed
    fi 
fi 

if (( WAIT_SECONDS > 0 )); then 
    echo "Wait $WAIT_SECONDS seconds before recording"
    sleep $WAIT_SECONDS
fi 

if [[ -z $1 ]]; then # system-wide recording
    sudo rm -rf /tmp/perf.data $HOME/perf.svg 
    sudo --preserve-env=DEBUGINFOD_URLS perf record -a -F $RECORD_FREQ -e sched:sched_switch -e sched:sched_wakeup  -g --call-graph $UNWIND_METHOD -o /tmp/perf.data -- sleep $RECORD_SECONDS
else # per process recording
    pstree -aspT $PID 
    pidstat -t -p $PID
    echo "Recording PID $PID for $RECORD_SECONDS seconds..."
    if [[ $USE_EU_STACK == true ]]; then 
        SECONDS=0
        sudo rm -rf /tmp/eu-stack.data $HOME/eu-stack.svg 
        while kill -0 $PID 2>/dev/null; do 
            sudo eu-stack -p $PID >>/tmp/eu-stack.data
            (( SECONDS >= RECORD_SECONDS )) && break 
        done 
    else
        sudo rm -rf /tmp/perf.data $HOME/perf.svg 
        sudo --preserve-env=DEBUGINFOD_URLS perf record -p $PID -g --call-graph $UNWIND_METHOD -o /tmp/perf.data -- sleep $RECORD_SECONDS 
    fi 
fi 

# flamegraph post process /tmp/perf.data
if [[ -f /tmp/perf.data ]]; then 
    sudo --preserve-env=DEBUGINFOD_URLS perf script -i /tmp/perf.data >/tmp/perf.txt
    chmod 666 /tmp/perf.txt
    cat /tmp/perf.txt | stackcollapse-perf.pl 2>/dev/null | flamegraph.pl >$HOME/perf.svg && echo "Generated $HOME/perf.svg" && sudo mv /tmp/perf.data /tmp/perf.data.old 
fi 
# flamegraph post process /tmp/eu-stack.data 
if [[ -f /tmp/eu-stack.data ]]; then 
    sudo chmod 666 /tmp/eu-stack.data
    cat /tmp/eu-stack.data | stackcollapse-elfutils.pl 2>/dev/null | flamegraph.pl >$HOME/eu-stack.svg && echo "Generated $HOME/eu-stack.svg" && sudo mv /tmp/eu-stack.data /tmp/eu-stack.data.old 
fi 

# wait for direct child to exit
[[ ! -z ${PID-} && -d /proc/$PID && $(awk '{print $4}' /proc/$PID/stat 2>/dev/null) -eq $$ ]] && {
    echo "Wait for process $PID to exit"
    wait $PID 
}
