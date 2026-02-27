#!/usr/bin/env bash

set -o pipefail 

WAIT_SECONDS=0
RECORD_SECONDS=5
SCOPED_SYMBOL= 
SCOPED_DSO= # optional (can be found at runtime)
INSTALL_DEBUG_SYMBOL=true 

while (( $# )); do 
    case $1 in 
        -wait=*) WAIT_SECONDS=${1#-wait=} ;;
        -record=*) RECORD_SECONDS=${1#-record=} ;;
        -symbol=*) SCOPED_SYMBOL=${1#-symbol=} ;;
        -dso=*) SCOPED_DSO=${1#-dso=} ;;
        -dbgsym=*) INSTALL_DEBUG_SYMBOL=${1#-dbgsym=} ;;
        *) break ;;
    esac 
    shift 
done 

if ! sudo -n true 2>/dev/null; then 
    echo "NOPASSWD is NOT enabled for $(id -un)"
    echo "Aborting"
    exit 1
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

    # find dso path for specified symbol
    if [[ -z $SCOPED_DSO ]]; then 
        awk '{ print $6 }' /proc/$PID/maps 2>/dev/null | grep -E '^/' | sort -u | grep -E '\.so(\.|$)|/[^/]+$' | while read -r dso; do
            nm -D --defined-only $dso 2>/dev/null | awk '{ print $3 }' | grep -qx $SCOPED_SYMBOL || continue
            SCOPED_DSO=$dso
            echo "Found $SCOPED_SYMBOL in $SCOPED_DSO"
        done
        if [[ -z $SCOPED_DSO ]]; then 
            echo "Failed to find $SCOPED_SYMBOL in /proc/$PID/maps"
            echo "Aborting"
            exit 1
        fi 
    fi 
else
    echo "System-wide offcpu recording is not supported"
    echo "Aborting"
    exit 1
fi 

if (( WAIT_SECONDS > 0 )); then 
    echo "Wait $WAIT_SECONDS seconds before recording"
    sleep $WAIT_SECONDS
fi 

pstree -aspT $PID 
pidstat -t -p $PID
echo "Recording PID $PID for $RECORD_SECONDS seconds"
sudo rm -rf /tmp/bpftrace-offcpu.txt $HOME/bpftrace-offcpu/
sudo bpftrace -v pid=$PID -v duration=$RECORD_SECONDS -v dso=$SCOPED_DSO -v symbol=$SCOPED_SYMBOL $HOME/wzhu_utils/profiling/bpftrace-offcpu.bt >/tmp/bpftrace-offcpu.txt 

# flamegraph post process for /tmp/bpftrace-offcpu.txt
if [[ -f /tmp/bpftrace-offcpu.txt ]]; then 
    mkdir -p $HOME/bpftrace-offcpu/
    awk '
  /^=== folded begin ===$/ { in=1; next }
  /^=== folded end ===$/   { exit }
  !in { next }

  {
    tid = $1
    val = $NF

    if (tid !~ /^[0-9]+$/) next
    if (val !~ /^[0-9]+$/) next
    if (val == 0) next

    stack = ""
    for (i = 2; i <= NF - 1; i++) {
      if (stack != "") stack = stack " "
      stack = stack $i
    }

    gsub(/^[[:space:]]*\[/, "", stack)
    gsub(/\][[:space:]]*$/, "", stack)
    gsub(/,[[:space:]]*/, ";", stack)

    if (stack == "") next

    printf("%s\t%s %s\n", tid, stack, val)
  }
' /tmp/bpftrace-offcpu.txt > /tmp/bpftrace-offcpu.folded

    cut -f1 /tmp/bpftrace-offcpu.folded | sort -nu | while read -r TID; do 
        awk -F'\t' -v tid=$TID '$1==tid { print $2 }' /tmp/bpftrace-offcpu.folded | flamegraph.pl >$HOME/bpftrace-offcpu/pid$PID-tid$TID.svg && echo "Generated $HOME/bpftrace-offcpu/pid$PID-tid$TID.svg"
    done 
fi 

# wait for direct child to exit
[[ ! -z ${PID-} && -d /proc/$PID && $(awk '{print $4}' /proc/$PID/stat 2>/dev/null) -eq $$ ]] && {
    echo "Wait for process $PID to exit"
    wait $PID 
}
