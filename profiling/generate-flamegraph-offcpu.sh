#!/usr/bin/env bash

set -o pipefail 

NAME_PREFIX=
WAIT_SECONDS=0
RECORD_SECONDS=5
SCOPED_SYMBOL= 
SCOPED_DSO=$(find /usr/lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.*) # optional (can be found at runtime)
INSTALL_DEBUG_SYMBOL=true 

while (( $# )); do 
    case $1 in 
        -name=*) NAME_PREFIX=${1#-name=} ;;
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
    echo "Error: NOPASSWD is NOT enabled for $(id -un)"
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
else
    echo "Error: system-wide offcpu recording is not supported"
    echo "Aborting"
    exit 1
fi 

if (( WAIT_SECONDS > 0 )); then 
    echo "Wait $WAIT_SECONDS seconds before recording"
    sleep $WAIT_SECONDS
fi 

COMM=$(cat /proc/$PID/comm 2>/dev/null)
pstree -aspT $PID 
pidstat -t -p $PID
echo "Target PID/TGID is $PID"
sudo rm -rf /tmp/bpftrace.offcpu.txt $HOME/bpftrace.offcpu.d/

# find the real dso contains symbol impl
if [[ -z $SCOPED_DSO ]]; then 
    func_probe_test() {
        local dso=$1
        sudo bpftrace -q -e "uprobe:$dso:$SCOPED_SYMBOL /comm == \"$COMM\"/ { @h = count(); } interval:s:1 { exit(); } END { print(@h); }" 2>/dev/null | awk '/@h:/ { print $2; exit }'
    }
    if (( WAIT_SECONDS == 0 )); then 
        sleep 1
    fi 
    candidates=$(awk '{ print $6 }' /proc/$PID/maps 2>/dev/null | grep -E '^/' | sort -u | grep -E '\.so(\.|$)')
    if [[ -z $candidates ]]; then
        echo "Error: can't find $SCOPED_SYMBOL in /proc/$PID/maps"
        echo "Aborting"
        exit 1
    fi
    while read -r dso; do
        [[ -z $dso ]] && continue
        hits=$(func_probe_test $dso)
        [[ -z $hits ]] && hits=0
        echo "Candidate $dso hits=$hits"
        if (( hits > 0 )); then
            SCOPED_DSO=$dso
            echo "Selected $SCOPED_DSO"
            break
        fi
    done <<<"$candidates"
    if [[ -z $SCOPED_DSO ]]; then
        echo "No candidate DSO produced hits for $SCOPED_SYMBOL"
        echo "Keeping first candidate as fallback"
        SCOPED_DSO=$(echo "$candidates" | head -n1)
    fi
fi 
echo "Recording $SCOPED_SYMBOL in $SCOPED_DSO for $RECORD_SECONDS seconds"

tmp_bt_file=/tmp/bpftrace.offcpu.bt
cat >$tmp_bt_file <<'BT_END'
#!/usr/bin/env bpftrace
tracepoint:sched:sched_switch
/args->prev_pid && @depth[args->prev_pid]/
{
    $t = args->prev_pid;
    @t0[$t] = nsecs;
    @u0[$t] = ustack;
}
tracepoint:sched:sched_switch
/args->next_pid && @t0[args->next_pid]/
{
    $t = args->next_pid;
    $dt_us = (nsecs - @t0[$t]) / 1000;
    @offcpu_total_us = @offcpu_total_us + $dt_us;
    @offcpu[$t, @u0[$t]] = sum($dt_us);
    delete(@t0[$t]);
    delete(@u0[$t]);
}
interval:s:1
{
    @secs = @secs + 1;
}
END
{
    printf("=== folded begin ===\n");
    print(@offcpu);
    printf("=== folded end ===\n");
}
BT_END
echo "BEGIN"                                                                               >>$tmp_bt_file
echo "{"                                                                                   >>$tmp_bt_file
echo "    printf(\"bpftrace.offcpu: target_pid=%d duration=%d dso=%s symbol=%s\\n\", $PID, $RECORD_SECONDS, \"$SCOPED_DSO\", \"$SCOPED_SYMBOL\");" >>$tmp_bt_file
echo "    @secs = 0;"                                                                      >>$tmp_bt_file
echo "    @offcpu_total_us = 0;"                                                           >>$tmp_bt_file
echo "    @hit_total = 0;"                                                                 >>$tmp_bt_file
echo "}"                                                                                   >>$tmp_bt_file
echo "uprobe:$SCOPED_DSO:$SCOPED_SYMBOL"                                                   >>$tmp_bt_file
echo "/comm == \"$COMM\"/"                                                                 >>$tmp_bt_file
echo "{"                                                                                   >>$tmp_bt_file
echo "    @depth[tid] = @depth[tid] + 1;"                                                  >>$tmp_bt_file
echo "}"                                                                                   >>$tmp_bt_file
echo "uprobe:$SCOPED_DSO:$SCOPED_SYMBOL"                                                   >>$tmp_bt_file
echo "/comm == \"$COMM\"/"                                                                 >>$tmp_bt_file
echo "{"                                                                                   >>$tmp_bt_file
echo "    @hit[tid] = count();"                                                            >>$tmp_bt_file
echo "    @hit_total = @hit_total + 1;"                                                    >>$tmp_bt_file
echo "}"                                                                                   >>$tmp_bt_file
echo "uretprobe:$SCOPED_DSO:$SCOPED_SYMBOL"                                                >>$tmp_bt_file
echo "/comm == \"$COMM\" && @depth[tid]/"                                                  >>$tmp_bt_file
echo "{"                                                                                   >>$tmp_bt_file
echo "    @depth[tid] = @depth[tid] - 1;"                                                  >>$tmp_bt_file
echo "    if (@depth[tid] <= 0) { delete(@depth[tid]); }"                                  >>$tmp_bt_file
echo "}"                                                                                   >>$tmp_bt_file
echo "interval:s:1 /@secs >= $RECORD_SECONDS/"                                             >>$tmp_bt_file
echo "{"                                                                                   >>$tmp_bt_file
echo "    printf(\"status: secs=%d/%d target_pid=%d offcpu_total_us=%lld hit_total=%lld\\n\", @secs, $RECORD_SECONDS, $PID, @offcpu_total_us, @hit_total);" >>$tmp_bt_file
echo "    exit();"                                                                         >>$tmp_bt_file
echo "}"                                                                                   >>$tmp_bt_file
sudo bpftrace $tmp_bt_file >/tmp/bpftrace.offcpu.txt

# flamegraph post process for /tmp/bpftrace.offcpu.txt
if [[ -f /tmp/bpftrace.offcpu.txt ]]; then 
    mkdir -p $HOME/bpftrace.offcpu.d/
    awk '
    /^=== folded begin ===$/ { inside=1; next }
    /^=== folded end ===$/   { flush(); exit }
    !inside { next }

    function trim(s) {
        sub(/^[[:space:]]+/, "", s)
        sub(/[[:space:]]+$/, "", s)
        return s
    }

    function flush(   i, tid, val, k, line, stack) {
        if (!in_entry) return

        tid = ""
        val = ""
        stack = ""
        k = 0

        line = entry[1]
        sub(/^@offcpu\[/, "", line)
        sub(/,.*/, "", line)
        tid = trim(line)

        line = entry[n]
        if (line ~ /\]:[[:space:]]*[0-9]+[[:space:]]*$/) {
            sub(/^.*\]:[[:space:]]*/, "", line)
            val = trim(line)
        } else {
            val = ""
        }

        # collect frames (skip blank + pure hex lines)
        for (i = 2; i <= n - 1; i++) {
            line = trim(entry[i])
            if (line == "") continue
            if (line ~ /^0x[0-9a-fA-F]+$/) continue
            frames[++k] = line
        }

        # reverse to root->leaf for flamegraph.pl
        for (i = k; i >= 1; i--) {
            if (stack != "") stack = stack ";"
            stack = stack frames[i]
            delete frames[i]
        }

        if (tid ~ /^[0-9]+$/ && val ~ /^[0-9]+$/ && val != "0" && stack != "")
            printf("%s\t%s %s\n", tid, stack, val)

        delete entry
        n = 0
        in_entry = 0
    }

    /^@offcpu\[/ {
        flush()
        in_entry = 1
        n = 0
    }

    in_entry {
        entry[++n] = $0
        if ($0 ~ /\]:[[:space:]]*[0-9]+[[:space:]]*$/) flush()
        next
    }
' /tmp/bpftrace.offcpu.txt > /tmp/bpftrace.offcpu.folded

    if [[ -s /tmp/bpftrace.offcpu.folded ]]; then 
        cut -f1 /tmp/bpftrace.offcpu.folded | sort -nu | while read -r TID; do 
            awk -F'\t' -v tid=$TID '$1==tid { print $2 }' /tmp/bpftrace.offcpu.folded | flamegraph.pl >$HOME/bpftrace.offcpu.d/pid$PID-tid$TID.svg && echo "Generated $HOME/bpftrace.offcpu.d/pid$PID-tid$TID.svg"
        done 
        if [[ ! -z $NAME_PREFIX ]]; then 
            sudo mv -f $HOME/bpftrace.offcpu.d $HOME/$NAME_PREFIX.bpftrace.offcpu.d
        fi 
    else
        echo "Error: /tmp/bpftrace.offcpu.folded is empty"
        echo "Aborting"
        exit 1
    fi 
else
    echo "Error: /tmp/bpftrace.offcpu.txt is missing"
    exit 1
fi 
