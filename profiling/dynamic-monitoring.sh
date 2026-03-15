#!/usr/bin/env bash

set -o pipefail

if [[ $1 == steam && ! -z $(pidof steam) ]]; then 
    pstree -aspT $(pidof steam)
    read -p "Input steam game PID: " dm_target_pid
else 
    dm_target_pid=$1
fi 
dm_sample_freq_ms=100
dm_sample_time_limit_s=0
gpu_query_fields=pstate:int,utilization.gpu:pct,utilization.memory:pct,clocks.current.graphics:mhz,clocks.current.sm:mhz,clocks.current.memory:mhz,power.draw.average:w,power.draw.instant:w,power.limit:w,temperature.gpu:c,temperature.memory:c,memory.used:mb,clocks_event_reasons.active:int

tmp_cpu_file=/tmp/cpu_data.csv
tmp_gpu_file=/tmp/gpu_data.csv
out_csv=./dynamic_monitoring.csv

cpu_sampler_pid=
gpu_sampler_pid=
stop_requested=0

normalize_gpu_field_name() {
    local field=$1
    local name
    local unit

    field=$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' <<< "$field")

    if [[ $field == *:* ]]; then
        name=${field%%:*}
        unit=${field##*:}
    else
        name=$field
        unit=int
    fi

    name=${name//./_}
    name=${name//:/_}
    unit=${unit//./_}
    unit=${unit//:/_}

    echo "${name}_${unit}"
}

build_gpu_csv_header() {
    local fields_csv=$1
    local field
    local out=ts_ms
    local old_ifs=$IFS

    IFS=,
    for field in $fields_csv; do
        out+=,$(normalize_gpu_field_name "$field")
    done
    IFS=$old_ifs

    echo "$out"
}

read_proc_cpu_total_idle() {
    awk '
        /^cpu / {
            total = 0
            for (i = 2; i <= NF; i++)
                total += $i
            idle = $5
            print total, idle
        }
    ' /proc/stat
}

read_meminfo_mb() {
    awk '
        /^MemTotal:/     { mem_total_kb = $2 }
        /^MemAvailable:/ { mem_avail_kb = $2 }
        /^SwapTotal:/    { swap_total_kb = $2 }
        /^SwapFree:/     { swap_free_kb = $2 }
        END {
            mem_used_mb = (mem_total_kb - mem_avail_kb) / 1024.0
            swap_used_mb = (swap_total_kb - swap_free_kb) / 1024.0
            printf "%.1f %.1f\n", mem_used_mb, swap_used_mb
        }
    ' /proc/meminfo
}

read_pid_stat() {
    local pid=$1

    if [[ ! -r /proc/$pid/stat ]]; then
        echo N/A N/A
        return
    fi

    awk '
        {
            utime = $14
            stime = $15
            rss = $24
            print utime + stime, rss
        }
    ' /proc/$pid/stat
}

stop_process_group() {
    local pid=$1

    [[ -n $pid ]] || return 0

    kill -- -$pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
}

cleanup() {
    stop_process_group $cpu_sampler_pid
    stop_process_group $gpu_sampler_pid
}

request_stop() {
    trap - INT TERM
    stop_requested=1

    stop_process_group $cpu_sampler_pid
    stop_process_group $gpu_sampler_pid

    cpu_sampler_pid=
    gpu_sampler_pid=

    echo
    echo dynamic monitoring finished
}

start_cpu_sampler() {
    local target_pid=$1
    local sleep_s=$2
    local out_file=$3
    local page_size=$4

    setsid bash -c '
        set -o pipefail

        target_pid=$1
        sleep_s=$2
        out_file=$3
        page_size=$4

        read_proc_cpu_total_idle() {
            awk "
                /^cpu / {
                    total = 0
                    for (i = 2; i <= NF; i++)
                        total += \$i
                    idle = \$5
                    print total, idle
                }
            " /proc/stat
        }

        read_meminfo_mb() {
            awk "
                /^MemTotal:/     { mem_total_kb = \$2 }
                /^MemAvailable:/ { mem_avail_kb = \$2 }
                /^SwapTotal:/    { swap_total_kb = \$2 }
                /^SwapFree:/     { swap_free_kb = \$2 }
                END {
                    mem_used_mb = (mem_total_kb - mem_avail_kb) / 1024.0
                    swap_used_mb = (swap_total_kb - swap_free_kb) / 1024.0
                    printf \"%.1f %.1f\n\", mem_used_mb, swap_used_mb
                }
            " /proc/meminfo
        }

        read_pid_stat() {
            local pid=$1

            if [[ ! -r /proc/$pid/stat ]]; then
                echo N/A N/A
                return
            fi

            awk "
                {
                    utime = \$14
                    stime = \$15
                    rss = \$24
                    print utime + stime, rss
                }
            " /proc/$pid/stat
        }

        echo ts_ms,cpu_util_pct,cpu_mem_used_mb,swap_used_mb,target_cpu_pct,target_rss_mb >$out_file

        read prev_total prev_idle < <(read_proc_cpu_total_idle)
        read prev_target_jiffies _ < <(read_pid_stat $target_pid)

        while [[ -d /proc/$target_pid ]]; do
            now_ms=$(date +%s%3N)

            read cur_total cur_idle < <(read_proc_cpu_total_idle)
            total_delta=$((cur_total - prev_total))
            idle_delta=$((cur_idle - prev_idle))

            if (( total_delta > 0 )); then
                cpu_util_pct=$(awk -v t=$total_delta -v i=$idle_delta "BEGIN { printf \"%.1f\", 100.0 * (t - i) / t }")
            else
                cpu_util_pct=N/A
            fi

            read cpu_mem_used_mb swap_used_mb < <(read_meminfo_mb)
            read cur_target_jiffies target_rss_pages < <(read_pid_stat $target_pid)

            if [[ $cur_target_jiffies != N/A && $prev_target_jiffies != N/A && $total_delta -gt 0 ]]; then
                target_cpu_pct=$(awk -v d=$((cur_target_jiffies - prev_target_jiffies)) -v t=$total_delta "BEGIN { printf \"%.1f\", 100.0 * d / t }")
            else
                target_cpu_pct=N/A
            fi

            if [[ $target_rss_pages != N/A ]]; then
                target_rss_mb=$(awk -v p=$target_rss_pages -v ps=$page_size "BEGIN { printf \"%.1f\", p * ps / 1024.0 / 1024.0 }")
            else
                target_rss_mb=N/A
            fi

            echo "$now_ms,$cpu_util_pct,$cpu_mem_used_mb,$swap_used_mb,$target_cpu_pct,$target_rss_mb" >>$out_file

            prev_total=$cur_total
            prev_idle=$cur_idle
            prev_target_jiffies=$cur_target_jiffies

            sleep $sleep_s || true
        done
    ' bash $target_pid $sleep_s $out_file $page_size </dev/null &
    echo $!
}

build_nvidia_smi_query_fields() {
    local fields_csv=$1
    local field
    local out=
    local old_ifs=$IFS

    IFS=,
    for field in $fields_csv; do
        field=$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' <<< "$field")
        field=${field%%:*}

        if [[ -z $out ]]; then
            out=$field
        else
            out+=,$field
        fi
    done
    IFS=$old_ifs

    echo "$out"
}

start_gpu_sampler() {
    local fields_csv=$1
    local sample_ms=$2
    local out_file=$3
    local header=$4
    local nvidia_smi_fields=$5

    setsid bash -c '
        set -o pipefail

        fields_csv=$1
        sample_ms=$2
        out_file=$3
        header=$4
        nvidia_smi_fields=$5

        trim() {
            sed "s/^[[:space:]]*//; s/[[:space:]]*$//"
        }

        convert_gpu_value() {
            local field=$1
            local value=$2
            local name
            local unit

            value=$(printf "%s\n" "$value" | trim)

            if [[ $field == *:* ]]; then
                name=${field%%:*}
                unit=${field##*:}
            else
                name=$field
                unit=
            fi

            if [[ $name == pstate && $unit == int ]]; then
                if [[ $value =~ ^P([0-9]+)$ ]]; then
                    echo "${BASH_REMATCH[1]}"
                else
                    echo "$value"
                fi
                return
            fi

            if [[ $name == clocks_event_reasons.active && $unit == int ]]; then
                if [[ $value =~ ^0[xX][0-9a-fA-F]+$ ]]; then
                    printf "%d\n" "$value"
                else
                    echo "$value"
                fi
                return
            fi

            echo "$value"
        }

        echo "$header" >$out_file

        nvidia-smi \
            --query-gpu="$nvidia_smi_fields" \
            --format=csv,noheader,nounits \
            --loop-ms="$sample_ms" 2>/dev/null |
        while IFS= read -r line; do
            [[ -n $line ]] || continue

            now_ms=$(date +%s%3N)
            out_line=$now_ms

            i=0
            old_ifs=$IFS
            IFS=,
            read -r -a fields <<< "$fields_csv"
            read -r -a values <<< "$line"
            IFS=$old_ifs

            for (( i = 0; i < ${#fields[@]}; i++ )); do
                value=$(convert_gpu_value "${fields[i]}" "${values[i]}")
                out_line+=,$value
            done

            echo "$out_line" >>$out_file
        done
    ' bash "$fields_csv" $sample_ms $out_file "$header" "$nvidia_smi_fields" </dev/null &
    echo $!
}

merge_cpu_gpu_csv() {
    local cpu_file=$1
    local gpu_file=$2
    local out_file=$3

    awk -F, '
        NR == FNR {
            if (FNR == 1) {
                cpu_header = $0
                next
            }
            cpu_n++
            cpu_ts[cpu_n] = $1
            cpu_rest[cpu_n] = substr($0, index($0, ",") + 1)
            next
        }

        FNR == 1 {
            gpu_header = $0
            next
        }

        {
            gpu_n++
            gpu_ts[gpu_n] = $1
            gpu_rest[gpu_n] = substr($0, index($0, ",") + 1)
        }

        END {
            if (cpu_n == 0 || gpu_n == 0)
                exit 1

            gpu_start_ts = gpu_ts[1]

            cpu_start_idx = 1
            best_diff = -1

            for (i = 1; i <= cpu_n; i++) {
                diff = cpu_ts[i] - gpu_start_ts
                if (diff < 0)
                    diff = -diff

                if (best_diff < 0 || diff < best_diff) {
                    best_diff = diff
                    cpu_start_idx = i
                }
            }

            sub(/^ts_ms,/, "", cpu_header)
            print gpu_header "," cpu_header

            count = cpu_n - cpu_start_idx + 1
            if (gpu_n < count)
                count = gpu_n

            for (i = 0; i < count; i++) {
                print gpu_ts[i + 1] "," gpu_rest[i + 1] "," cpu_rest[cpu_start_idx + i]
            }
        }
    ' $cpu_file $gpu_file >$out_file
}

if [[ -z $dm_target_pid ]]; then
    echo "usage: ${0##*/} <target_pid>"
    exit 1
fi

if [[ ! -d /proc/$dm_target_pid ]]; then
    echo "error: invalid pid: $dm_target_pid" >&2
    exit 1
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo 'error: nvidia-smi not found' >&2
    exit 1
fi

rm -f $tmp_cpu_file $tmp_gpu_file $out_csv ${out_csv%.*}.html

sleep_s=$(awk -v ms=$dm_sample_freq_ms 'BEGIN { printf "%.3f\n", ms / 1000.0 }')
page_size=$(getconf PAGESIZE)
gpu_header=$(build_gpu_csv_header "$gpu_query_fields")
nvidia_smi_query_fields=$(build_nvidia_smi_query_fields "$gpu_query_fields")

trap cleanup EXIT
trap request_stop INT TERM

if (( dm_sample_time_limit_s > 0 )); then
    echo "time limit in sec: $dm_sample_time_limit_s"
else
    echo 'time limit: until ctrl-c or target exits'
fi

cpu_sampler_pid=$(start_cpu_sampler $dm_target_pid $sleep_s $tmp_cpu_file $page_size)
gpu_sampler_pid=$(start_gpu_sampler "$gpu_query_fields" $dm_sample_freq_ms $tmp_gpu_file "$gpu_header" "$nvidia_smi_query_fields")
start_s=$(date +%s)

while [[ -d /proc/$dm_target_pid ]]; do
    if (( stop_requested )); then
        break
    fi

    if (( dm_sample_time_limit_s > 0 )) && (( $(date +%s) - start_s >= dm_sample_time_limit_s )); then
        break
    fi

    if ! kill -0 $cpu_sampler_pid 2>/dev/null; then
        echo 'cpu sampler exited unexpectedly' >&2
        break
    fi

    if ! kill -0 $gpu_sampler_pid 2>/dev/null; then
        echo 'gpu sampler exited unexpectedly' >&2
        break
    fi

    sleep 0.2 || true
done

stop_process_group $cpu_sampler_pid
stop_process_group $gpu_sampler_pid
cpu_sampler_pid=
gpu_sampler_pid=

if [[ ! -s $tmp_cpu_file ]]; then
    echo "error: empty cpu temp file: $tmp_cpu_file" >&2
    exit 1
fi

if [[ ! -s $tmp_gpu_file ]]; then
    echo "error: empty gpu temp file: $tmp_gpu_file" >&2
    exit 1
fi

merge_cpu_gpu_csv $tmp_cpu_file $tmp_gpu_file $out_csv || {
    echo 'error: failed to merge cpu and gpu csv' >&2
    exit 1
}

if command -v draw-polylines-in-html.py >/dev/null 2>&1; then
    python3 "$(command -v draw-polylines-in-html.py)" $out_csv 
fi