#!/usr/bin/env bash

set -o pipefail

WAIT_SECONDS=0 # delay before perf recording starts.
RECORD_SECONDS=5 # perf recording duration in seconds.
RECORD_FREQ=1000 # perf sampling frequency in Hz.
UNWIND_METHOD=dwarf # dwarf or fp (frame pointer)
INSTALL_DEBUG_SYMBOL=false
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

if ! sudo -n true 2>/dev/null; then
    echo "Error: NOPASSWD is NOT enabled for $(id -un)"
    echo "Aborting"
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
sudo rm -rf /tmp/perf.data $HOME/system_flamegraph.svg $HOME/${COMM}_flamegraph.svg $HOME/${COMM}_thread*_flamegraph.svg $HOME/${COMM}_flamegraph_tabs.html

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

        # If the process has multiple threads, also generate one SVG per thread.
        if [[ -d /proc/$PID/task ]] && (( $(ls /proc/$PID/task 2>/dev/null | wc -l) > 1 )); then
            echo "$COMM ($PID) has $(ls /proc/$PID/task 2>/dev/null | wc -l) threads"
            sudo rm -rf /tmp/perf_tid*
            # Split perf script output by TID. Process line-by-line so we don't rely on blank lines
            # between samples; each line is appended to the file for the TID from the last seen
            # header line (a line containing pid/tid).
            awk '
                BEGIN { cur_tid = "" }
                /[0-9]+\/[0-9]+/ {
                    n = split($0, w, /[ \t]+/)
                    tid = ""
                    for (i = 1; i <= n; i++) {
                        if (match(w[i], /^[0-9]+\/[0-9]+$/)) {
                            split(w[i], a, "/")
                            tid = a[2]
                            break
                        }
                    }
                    if (tid != "") cur_tid = tid
                }
                { file = "/tmp/perf_tid" (cur_tid == "" ? "unknown" : cur_tid) ".txt"; print >> file }
            ' /tmp/perf.txt

            # List TIDs that have data, sorted numerically (smallest = oldest thread = thread1).
            tid_list=$(ls /tmp/perf_tid*.txt 2>/dev/null | sed -n 's|.*/perf_tid\([0-9]\+\)\.txt$|\1|p' | sort -n -u)
            tid_count=$(echo "$tid_list" | grep -c . || true)
            if (( tid_count > 1 )); then
                # Tab labels and SVG files for the combined view HTML (tab 0 = All threads, then Thread 1, 2, ...).
                tab_labels=("All threads")
                tab_files=("${COMM}_flamegraph.svg")
                index=1
                for tid in $tid_list; do
                    file=/tmp/perf_tid${tid}.txt
                    [[ -f $file ]] || continue
                    thread_name=$(cat /proc/$PID/task/$tid/comm 2>/dev/null | tr -d '\n' | sed 's/[^a-zA-Z0-9._-]/_/g' | head -c 48)
                    [[ -z $thread_name ]] && thread_name="untitled"
                    out_name="${COMM}_thread${index}_${thread_name}_flamegraph.svg"
                    cat $file | stackcollapse-perf.pl 2>/dev/null | stackcollapse-recursive.pl 2>/dev/null | flamegraph.pl >"$HOME/$out_name"
                    echo "    - $HOME/$out_name"
                    tab_labels+=("Thread $index: $thread_name")
                    tab_files+=("$out_name")
                    (( index++ )) || true
                done
                # Generate one self-contained HTML with a tab per flamegraph (SVG content embedded
                # inline so the single file can be sent to others and opened anywhere).
                html_file="$HOME/${COMM}_flamegraph_tabs.html"
                {
                    echo '<!DOCTYPE html><html><head><meta charset="utf-8"><title>'"$COMM"' flame graphs</title>'
                    echo '<style>.tabbtn{border:1px solid #888;background:#eee;padding:8px 12px;cursor:pointer;margin:2px}.tabbtn.active{background:#ccc}.tabpanel{display:none}.tabpanel.active{display:block}.svgwrap{overflow:auto;max-height:85vh}.svgwrap svg{max-width:100%}</style></head><body>'
                    echo '<h1>'"$COMM"' flame graphs</h1><div class="tabbar">'
                    for i in "${!tab_labels[@]}"; do
                        echo -n '<button class="tabbtn'"$([[ $i -eq 0 ]] && echo ' active')"'" onclick="showTab('"$i"')">'"${tab_labels[$i]}"'</button>'
                    done
                    echo '</div>'
                    for i in "${!tab_files[@]}"; do
                        echo -n '<div id="panel'"$i"'" class="tabpanel'"$([[ $i -eq 0 ]] && echo ' active')"'"><div class="svgwrap">'
                        cat "$HOME/${tab_files[$i]}"
                        echo '</div></div>'
                    done
                    echo '<script>function showTab(i){document.querySelectorAll(".tabpanel").forEach(function(p){p.classList.remove("active")});document.querySelectorAll(".tabbtn").forEach(function(b){b.classList.remove("active")});document.getElementById("panel"+i).classList.add("active");document.querySelectorAll(".tabbtn")[i].classList.add("active")}</script></body></html>'
                } > "$html_file"
                echo "    - $html_file (tab view)"
            else
                echo "Found 0 per-thread stack, skipping per-thread flamegraph"
            fi
        else
            echo "$COMM ($PID) has 1 thread, skipping per-thread flamegraph"
        fi
    fi
fi
