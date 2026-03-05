#!/usr/bin/env bash

set -o pipefail 

NAME_PREFIX=
WAIT_SECONDS=0
RECORD_SECONDS=5
RECORD_FREQ=1000
UNWIND_METHOD=dwarf # dwarf or fp (frame pointer) 
INSTALL_DEBUG_SYMBOL=true 
DEBUGINFOD_URLS="https://debuginfod.ubuntu.com"
unset PID COMM 

while (( $# )); do 
    case $1 in 
        -name=*) NAME_PREFIX=${1#-name=} ;;
        -wait=*) WAIT_SECONDS=${1#-wait=} ;;
        -record=*) RECORD_SECONDS=${1#-record=} ;;
        -freq=*) RECORD_FREQ=${1#-freq=} ;;
        -unwind=*) UNWIND_METHOD=${1#-unwind=} ;;
        -dbgsym=*) INSTALL_DEBUG_SYMBOL=${1#-dbgsym=} ;;
        *) break ;;
    esac 
    shift 
done 

if ! sudo -n true 2>/dev/null; then 
    echo "Error: NOPASSWD is NOT enabled for $(id -un)"
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

sudo rm -rf /tmp/perf.data $HOME/perf-system-wide.svg $HOME/perf.svg.d/

if (( WAIT_SECONDS > 0 )); then 
    echo "Wait $WAIT_SECONDS seconds before recording"
    sleep $WAIT_SECONDS
fi 

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

    # get comm name of target PID 
    COMM=$(cat /proc/$PID/comm 2>/dev/null)
    [[ -z $COMM ]] && COMM=unknown
    
    # install debug symbols for PID
    if [[ $INSTALL_DEBUG_SYMBOL == true ]]; then 
        if [[ ! -f /tmp/$(cat /proc/$PID/comm)-dbgsym-installed && ! -z $(which find-dbgsym-packages) ]]; then 
            echo "Installing debug symbols for process $PID..."
            find-dbgsym-packages $PID 2>/dev/null | tr ' ' '\n' | while read -r pkg; do
                sudo apt install -y $pkg 
            done
            touch /tmp/$(cat /proc/$PID/comm)-dbgsym-installed
        fi 
    fi 

    pstree -aspT $PID 
    pidstat -t -p $PID
fi 

# the perf recording starts here 
echo "Recording for $RECORD_SECONDS seconds ..."
sudo perf record $([[ -z $PID ]] && echo "-a" || echo "--pid=$PID") --freq=$RECORD_FREQ -g --call-graph $UNWIND_METHOD -o /tmp/perf.data -- sleep $RECORD_SECONDS 

# flamegraph post process for /tmp/perf.data
if [[ -f /tmp/perf.data ]]; then 
    sudo perf script -i /tmp/perf.data >/tmp/perf.txt
    chmod 666 /tmp/perf.txt

    if [[ -z $PID ]]; then 
        # 1) system-wide recording 
        cat /tmp/perf.txt | stackcollapse-perf.pl 2>/dev/null | flamegraph.pl >$HOME/perf-system-wide.svg && echo "Generated $HOME/perf-system-wide.svg"
    else
        # 2) generate all-threads combined svg 
        mkdir -p $HOME/perf.svg.d/
        cat /tmp/perf.txt | stackcollapse-perf.pl 2>/dev/null | flamegraph.pl >$HOME/perf.svg.d/perf-all-threads.svg && echo "Generated $HOME/perf.svg.d/perf-all-threads.svg"
        # 3) generate per-thread svgs  
        if [[ -d /proc/$PID/task ]] && (( $(ls /proc/$PID/task 2>/dev/null | wc -l) > 1 )); then
            sudo rm -rf /tmp/perf-tid* 
            awk '
                BEGIN { RS=""; ORS="" }
                {
                    split($0, lines, "\n")
                    split(lines[1], w, /[ \t]+/)
                    tid=""
                    for (i = 1; i <= length(w); i++) {
                        if (match(w[i], /^[0-9]+\/[0-9]+$/)) {
                            split(w[i], a, "/")
                            tid=a[2]
                            break
                        }
                    }
                    if (tid == "") tid="unknown"
                    file="/tmp/perf-tid" tid ".txt"
                    print $0 "\n\n" >> file
                }
            ' /tmp/perf.txt
            tid_count=$(ls /tmp/perf-tid*.txt 2>/dev/null | sed -n 's|.*/perf\.tid\.\([0-9]\+\)\.txt$|\1|p' | sort -u | wc -l)
            if (( tid_count > 1 )); then
                for file in /tmp/perf-tid*.txt; do
                    [[ -f $file ]] || continue
                    tid=${file#/tmp/perf-tid}
                    tid=${tid%.txt}
                    [[ $tid == unknown ]] && continue
                    cat $file | stackcollapse-perf.pl 2>/dev/null | flamegraph.pl >$HOME/perf.svg.d/tid$tid.svg
                    echo "Generated $HOME/perf.svg.d/tid$tid.svg"
                done
            fi
        fi 

        if [[ ! -z $NAME_PREFIX ]]; then 
            sudo mv -f $HOME/perf.svg.d $HOME/$NAME_PREFIX.perf.svg.d
            echo "Renamed output dir to $HOME/$NAME_PREFIX.perf.svg.d"
        fi 
    fi 
fi 
