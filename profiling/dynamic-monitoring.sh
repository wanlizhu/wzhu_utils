#!/usr/bin/env bash
set -o pipefail

DM_SAMPLE_FREQ_MS=100
DM_SAMPLE_TIME_LIMIT_S=0
GPU_QUERY_FIELDS=pstate:int,utilization.gpu:pct,utilization.memory:pct,clocks.current.graphics:mhz,clocks.current.sm:mhz,clocks.current.memory:mhz,power.draw.average:w,power.draw.instant:w,power.limit:w,temperature.gpu:c,temperature.memory:c,memory.used:mb,clocks_event_reasons.active:int

TMP_CPU_FILE=/tmp/cpu_data.csv
TMP_GPU_FILE=/tmp/gpu_data.csv
OUT_CSV=./dynamic_monitoring.csv

cpu_sampler_pid=
gpu_sampler_pid=
poll_wait_pid=
stop_requested=0
dm_target_pid=

print_usage() {
    echo "usage: ${0##*/} [options] <target_pid>"
    echo "       ${0##*/} [options] steam"
    echo
    echo "options:"
    echo "    -h, --help    show this help message and exit"
    echo
    echo "inputs:"
    echo "    <target_pid>  monitor an existing target process by PID"
    echo "    steam         show the Steam process tree, then ask for the game PID"
    echo
    echo "output:"
    echo "    writes merged samples to $OUT_CSV"
}

parse_args() {
    while (( $# > 0 )); do
        case $1 in
            -h|--help)
                print_usage
                exit 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                echo "error: unknown option: $1" >&2
                print_usage >&2
                exit 1
                ;;
            *)
                if [[ -n $dm_target_pid ]]; then
                    echo 'error: too many positional arguments' >&2
                    print_usage >&2
                    exit 1
                fi
                dm_target_pid=$1
                shift
                ;;
        esac
    done

    if (( $# > 0 )); then
        if [[ -n $dm_target_pid ]]; then
            echo 'error: too many positional arguments' >&2
            print_usage >&2
            exit 1
        fi
        dm_target_pid=$1
        shift
    fi

    if (( $# > 0 )); then
        echo 'error: too many positional arguments' >&2
        print_usage >&2
        exit 1
    fi

    if [[ -z $dm_target_pid ]]; then
        print_usage >&2
        exit 1
    fi

    if [[ $dm_target_pid == steam ]]; then
        if [[ -z $(pidof steam) ]]; then
            echo 'error: steam is not running' >&2
            exit 1
        fi

        pstree -aspT "$(pidof steam)"
        read -r -p 'Input steam game PID: ' dm_target_pid
    fi
}

# Convert one GPU query field into a safe CSV column name.
#
# Input format supports either:
#   field_name
#   field_name:unit
#
# The implementation trims surrounding spaces, splits the optional unit suffix,
# and replaces characters such as '.' and ':' with '_' so the final header can
# be used safely by CSV readers and later visualization scripts.
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

# Build the GPU CSV header from GPU_QUERY_FIELDS.
#
# The output always starts with ts_ms, followed by one normalized column name
# per queried GPU metric. This keeps the header stable and aligned with the
# values later emitted by start_gpu_sampler().
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

# Read total and idle CPU jiffies from /proc/stat.
#
# The function returns two numbers:
#   1) total jiffies across all CPUs
#   2) idle jiffies
#
# Sampling these values twice and subtracting them allows the script to compute
# system-wide CPU utilization over each interval.
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

# Read host memory usage from /proc/meminfo and report it in MiB.
#
# The function calculates used system memory as:
#   MemTotal - MemAvailable
#
# It also calculates used swap as:
#   SwapTotal - SwapFree
#
# Both values are printed as floating-point MiB numbers so the caller can append
# them directly into the CSV output.
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

# Read per-process CPU time and RSS from /proc/<pid>/stat.
#
# The function returns two values:
#   1) utime + stime, in jiffies
#   2) rss, in pages
#
# Returning the raw kernel counters avoids rounding loss. The caller converts
# them into percentages and MiB using the elapsed system jiffies and page size.
# If the target process no longer exists, the function prints N/A placeholders.
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

# Terminate the whole process group created for one sampler.
#
# Both samplers are launched via setsid, so each sampler runs in its own process
# group. Killing the negative PID targets the whole group, which cleanly stops
# the shell wrapper and any child processes such as nvidia-smi. A SIGKILL pass
# is used only as a best-effort fallback.
stop_process_group() {
    local pid=$1

    [[ -n $pid ]] || return 0

    kill -- -$pid 2>/dev/null || true
    sleep 0.2 || true
    kill -KILL -- -$pid 2>/dev/null || true
}

# Cleanup handler for normal exit paths.
#
# This makes sure background samplers do not survive after the main script exits,
# regardless of whether the exit is due to success, Ctrl-C, timeout, or error.
cleanup() {
    [[ -n $cpu_sampler_pid ]] && stop_process_group $cpu_sampler_pid
    [[ -n $gpu_sampler_pid ]] && stop_process_group $gpu_sampler_pid
}

# Signal handler for Ctrl-C or external termination.
#
# The handler does not stop samplers directly. Instead it flips a flag that is
# polled by the main loop, so the shutdown path stays centralized and the merge
# step can still run if temp files are valid.
request_stop() {
    trap - INT TERM
    stop_requested=1
    echo
    echo dynamic monitoring finished
}

# Start the host/target CPU sampler in a dedicated process group.
#
# The sampler periodically records:
#   - wall-clock timestamp in ms
#   - overall CPU utilization
#   - host used memory
#   - used swap
#   - target process CPU utilization
#   - target process RSS in MiB
#
# Implementation details:
#   - It samples /proc/stat twice and computes delta-based CPU utilization.
#   - It samples /proc/<pid>/stat twice and computes target CPU share against
#     the same total system jiffy delta.
#   - It derives timestamps from one base time plus sample_idx * interval, which
#     avoids duplicate timestamps caused by date +%s%3N granularity.
start_cpu_sampler() {
    local target_pid=$1
    local sleep_s=$2
    local out_file=$3
    local page_size=$4

    setsid bash -c '
        set -o pipefail

        target_pid=$1
        sleep_s=$2
        sleep_ms=$(awk -v s=$sleep_s '"'"'BEGIN { printf "%d\n", s * 1000 }'"'"')
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
                    printf \"%.1f %.1f\\n\", mem_used_mb, swap_used_mb
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
        base_ts_ms=
        sample_idx=

        while [[ -d /proc/$target_pid ]]; do
            if [[ -z $base_ts_ms ]]; then
                base_ts_ms=$(date +%s%3N)
                sample_idx=0
            else
                sample_idx=$((sample_idx + 1))
            fi
            now_ms=$((base_ts_ms + sample_idx * sleep_ms))

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
    cpu_sampler_pid=$!
}

# Strip the optional :unit suffix from GPU_QUERY_FIELDS for nvidia-smi.
#
# The script keeps unit annotations in GPU_QUERY_FIELDS because they are useful
# for generated CSV headers. nvidia-smi does not accept those suffixes, so this
# helper removes them and rebuilds a plain comma-separated query string.
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

# Start the GPU sampler in a dedicated process group.
#
# The sampler runs nvidia-smi --loop-ms and writes one CSV row per sample.
# For each row it:
#   - generates a synthetic timestamp based on base time + sample index
#   - splits the returned CSV values
#   - normalizes selected fields into more analysis-friendly numeric forms
#
# Current value conversions:
#   - pstate P0/P1/... -> 0/1/...
#   - clocks_event_reasons.active hex bitmask -> decimal integer
#
# All other fields are passed through unchanged because nounits mode already
# returns plain numeric strings for the selected metrics.
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
        base_ts_ms=
        sample_idx=

        nvidia-smi \
            --query-gpu="$nvidia_smi_fields" \
            --format=csv,noheader,nounits \
            --loop-ms="$sample_ms" 2>/dev/null |
        while IFS= read -r line; do
            [[ -n $line ]] || continue

            if [[ -z $base_ts_ms ]]; then
                base_ts_ms=$(date +%s%3N)
                sample_idx=0
            else
                sample_idx=$((sample_idx + 1))
            fi

            now_ms=$((base_ts_ms + sample_idx * sample_ms))
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
    gpu_sampler_pid=$!
}

# Merge CPU and GPU CSV streams into one output CSV.
#
# The two samplers start independently, so their first timestamps may not match.
# This function aligns the CPU stream to the first GPU timestamp by selecting the
# CPU row with the smallest absolute timestamp difference to GPU sample 0.
#
# It then emits paired rows in GPU time order, using the shorter stream length.
# If duplicate or non-increasing GPU timestamps still appear, the function bumps
# later timestamps upward by 1 ms to keep the merged file strictly increasing.
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

            last_ts = -1
            for (i = 0; i < count; i++) {
                out_ts = gpu_ts[i + 1] + 0
                if (last_ts >= 0 && out_ts <= last_ts)
                    out_ts = last_ts + 1
                print out_ts "," gpu_rest[i + 1] "," cpu_rest[cpu_start_idx + i]
                last_ts = out_ts
            }
        }
    ' $cpu_file $gpu_file >$out_file
}

parse_args "$@"

if [[ ! $dm_target_pid =~ ^[0-9]+$ ]]; then
    echo "error: invalid pid: $dm_target_pid" >&2
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

rm -f $TMP_CPU_FILE $TMP_GPU_FILE $OUT_CSV ${OUT_CSV%.*}.html

sleep_s=$(awk -v ms=$DM_SAMPLE_FREQ_MS 'BEGIN { printf "%.3f\n", ms / 1000.0 }')
page_size=$(getconf PAGESIZE)
gpu_header=$(build_gpu_csv_header "$GPU_QUERY_FIELDS")
nvidia_smi_query_fields=$(build_nvidia_smi_query_fields "$GPU_QUERY_FIELDS")

trap cleanup EXIT
trap request_stop INT TERM

if (( DM_SAMPLE_TIME_LIMIT_S > 0 )); then
    echo "time limit in sec: $DM_SAMPLE_TIME_LIMIT_S"
else
    echo 'time limit: until ctrl-c or target exits'
fi

start_cpu_sampler $dm_target_pid $sleep_s $TMP_CPU_FILE $page_size
start_gpu_sampler "$GPU_QUERY_FIELDS" $DM_SAMPLE_FREQ_MS $TMP_GPU_FILE "$gpu_header" "$nvidia_smi_query_fields"
start_s=$(date +%s)

while [[ -d /proc/$dm_target_pid ]]; do
    if (( stop_requested )); then
        break
    fi

    if (( DM_SAMPLE_TIME_LIMIT_S > 0 )) && (( $(date +%s) - start_s >= DM_SAMPLE_TIME_LIMIT_S )); then
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

    sleep 0.2 &
    poll_wait_pid=$!
    wait $poll_wait_pid 2>/dev/null || true
    poll_wait_pid=
done

stop_process_group $cpu_sampler_pid
stop_process_group $gpu_sampler_pid
cpu_sampler_pid=
gpu_sampler_pid=

if [[ ! -s $TMP_CPU_FILE ]]; then
    echo "error: empty cpu temp file: $TMP_CPU_FILE" >&2
    exit 1
fi

if [[ ! -s $TMP_GPU_FILE ]]; then
    echo "error: empty gpu temp file: $TMP_GPU_FILE" >&2
    exit 1
fi

merge_cpu_gpu_csv $TMP_CPU_FILE $TMP_GPU_FILE $OUT_CSV || {
    echo 'error: failed to merge cpu and gpu csv' >&2
    exit 1
}

if command -v draw-polylines-in-html.py >/dev/null 2>&1; then
    python3 "$(command -v draw-polylines-in-html.py)" --y-axis-mode actual --default-attributes utilization_gpu_pct cpu_util_pct $OUT_CSV
fi
