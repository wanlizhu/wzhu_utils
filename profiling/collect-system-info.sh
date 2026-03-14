#!/usr/bin/env bash

set -o pipefail

OUTPUT_FILE=~/system_info.txt
DM_SAMPLE_FREQ_MS=100
DM_SAMPLE_TIME_LIMIT_S=0

if [[ $1 == brief ]]; then 
    printf '%s (Kernel: %s)\n' "$(lsb_release -a | grep Description | awk '{print $2 $3}')" "$(uname -r)"
    printf '%s [RAM: %s, CLK: %.1f GHz]\n' "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')" "$(free -h | awk '/^Mem:/ {print $2}')" "$(awk '{print $1 / 1000000}' /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq)"
    printf '%s [VRAM: %s (Resizable BAR: %s), CLK: %s]\n' "$(lspci | grep -iE 'vga|3d|display' | cut -d: -f3- | sed 's/^ *//' | grep -vi Controller | grep -vi Thunderbolt )" "$(nvidia-smi --query-gpu=memory.total --format=csv,noheader)" "$(sudo lspci -vv -s $(lspci -Dnn | grep -iE 'VGA|3D|Display' | grep -i nvidia | awk 'NR==1 {print $1}') | grep -A1 'Physical Resizable BAR' | grep 'current size' | awk -F',' '{print $1}' | awk '{print $5}')" "$(nvidia-smi -q -d CLOCK | grep -A4 'Max Clocks' | grep 'Graphics' | awk -F': ' '{print $2}')"
    exit 
fi 

if [[ $1 == steam && ! -z $(pidof steam) ]]; then 
    pstree -aspT $(pidof steam)
    read -p "Input steam game PID: " dm_target_pid
elif [[ -d /proc/$1 ]]; then 
    dm_target_pid=$1
else
    dm_target_pid=
fi 
[[ ! -z $dm_target_pid ]] && dm_output_file=~/system_info_dm_pid${dm_target_pid}.csv

append_basic_header() {
    printf '%s\n' "$(hostname)" >$OUTPUT_FILE

    if command -v lsb_release >/dev/null 2>&1; then
        lsb_release -a 2>/dev/null | grep 'Description' | awk -F: '{ sub(/^[[:space:]]+/, "", $2); print $2 }' >>$OUTPUT_FILE
    else
        echo N/A >>$OUTPUT_FILE
    fi

    uname -srm >>$OUTPUT_FILE
    lscpu | grep 'Model name' | awk -F: '{ sub(/^[[:space:]]+/, "", $2); print $2 }' >>$OUTPUT_FILE

    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi -L >>$OUTPUT_FILE 2>/dev/null
    fi

    printf '\n' >>$OUTPUT_FILE
}

append_environment() {
    printf '[environment variables]\n' >>$OUTPUT_FILE
    env | grep -Ev 'PTYXIS_PROFILE|guid=|INVOCATION_ID=|LS_COLORS|MEMORY_PRESSURE_WRITE=|MEMORY_PRESSURE_WATCH=' >>$OUTPUT_FILE
    printf '[environment variables] FINISHED\n\n' >>$OUTPUT_FILE
}

append_cpu_static_info() {
    printf '[cpu static info]\n' >>$OUTPUT_FILE

    lscpu >>$OUTPUT_FILE
    printf '\n' >>$OUTPUT_FILE

    if [[ -r /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw ]]; then
        echo max_power_limit_uw: "$(cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw)" >>$OUTPUT_FILE
    else
        echo max_power_limit_uw: N/A >>$OUTPUT_FILE
    fi

    if [[ -r /sys/devices/system/cpu/intel_pstate/status ]]; then
        echo intel_pstate: "$(cat /sys/devices/system/cpu/intel_pstate/status)" >>$OUTPUT_FILE
    else
        echo intel_pstate: N/A >>$OUTPUT_FILE
    fi

    if command -v powerprofilesctl >/dev/null 2>&1; then
        echo power_profile: "$(powerprofilesctl get 2>/dev/null || echo N/A)" >>$OUTPUT_FILE
    else
        echo power_profile: N/A >>$OUTPUT_FILE
    fi

    {
        printf 'cpu\tmax_freq_khz\tcurrent_policy\tcpufreq_governor\tenergy_perf_bias\tenergy_perf_pref\n'
        for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                "${cpu##*/}" \
                "$( [[ -r $cpu/cpufreq/cpuinfo_max_freq ]] && cat $cpu/cpufreq/cpuinfo_max_freq || echo N/A )" \
                "$( [[ -r $cpu/cpufreq/scaling_driver ]] && cat $cpu/cpufreq/scaling_driver || echo N/A )" \
                "$( [[ -r $cpu/cpufreq/scaling_governor ]] && cat $cpu/cpufreq/scaling_governor || echo N/A )" \
                "$( [[ -r $cpu/power/energy_perf_bias ]] && cat $cpu/power/energy_perf_bias || echo N/A )" \
                "$( [[ -r $cpu/cpufreq/energy_performance_preference ]] && cat $cpu/cpufreq/energy_performance_preference || echo N/A )"
        done
    } | column -t -s $'\t' >>$OUTPUT_FILE

    printf '[cpu static info] FINISHED\n\n' >>$OUTPUT_FILE
}

append_mem_static_info() {
    printf '[mem static info]\n' >>$OUTPUT_FILE

    if ! command -v dmidecode >/dev/null 2>&1; then
        echo dmidecode: N/A >>$OUTPUT_FILE
        printf '[mem static info] FINISHED\n\n' >>$OUTPUT_FILE
        return
    fi

    sudo dmidecode -t memory 2>/dev/null | awk '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }

        function flush_dev() {
            if (!in_dev || no_module)
                return

            if (size_mb > 0)
                total_mb += size_mb

            if (type != "" && type != "Unknown" && type != "RAM")
                types[type] = 1

            if (manufacturer != "" && manufacturer != "Unknown")
                manufacturers[manufacturer] = 1

            if (configured_speed_mt > 0)
                speeds[configured_speed_mt]++

            if (configured_speed_mt > 0 && data_width_bits > 0)
                total_bandwidth_gbs += configured_speed_mt * (data_width_bits / 8) / 1000.0
        }

        BEGIN {
            in_dev = 0
            total_mb = 0
            total_bandwidth_gbs = 0
        }

        /^Memory Device$/ {
            flush_dev()

            in_dev = 1
            no_module = 0
            size_mb = 0
            type = ""
            manufacturer = ""
            configured_speed_mt = 0
            data_width_bits = 0
            next
        }

        !in_dev {
            next
        }

        /^[[:space:]]+Size:/ {
            sub(/^[[:space:]]+Size:[[:space:]]+/, "", $0)
            val = trim($0)

            if (val == "No Module Installed") {
                no_module = 1
                next
            }

            if (match(val, /^[0-9]+[[:space:]]+MB$/)) {
                size_mb = val
                sub(/[[:space:]]+MB$/, "", size_mb)
                size_mb += 0
            } else if (match(val, /^[0-9]+[[:space:]]+GB$/)) {
                size_mb = val
                sub(/[[:space:]]+GB$/, "", size_mb)
                size_mb = size_mb * 1024
            }

            next
        }

        /^[[:space:]]+Type:[[:space:]]/ {
            sub(/^[[:space:]]+Type:[[:space:]]+/, "", $0)
            type = trim($0)
            next
        }

        /^[[:space:]]+Manufacturer:/ {
            sub(/^[[:space:]]+Manufacturer:[[:space:]]+/, "", $0)
            manufacturer = trim($0)
            next
        }

        /^[[:space:]]+Configured Memory Speed:/ || /^[[:space:]]+Configured Clock Speed:/ {
            sub(/^[[:space:]]+Configured Memory Speed:[[:space:]]+/, "", $0)
            sub(/^[[:space:]]+Configured Clock Speed:[[:space:]]+/, "", $0)
            val = trim($0)
            if (match(val, /^[0-9]+[[:space:]]+MT\/s$/)) {
                configured_speed_mt = val
                sub(/[[:space:]]+MT\/s$/, "", configured_speed_mt)
                configured_speed_mt += 0
            }
            next
        }

        /^[[:space:]]+Data Width:/ {
            sub(/^[[:space:]]+Data Width:[[:space:]]+/, "", $0)
            val = trim($0)
            if (match(val, /^[0-9]+[[:space:]]+bits$/)) {
                data_width_bits = val
                sub(/[[:space:]]+bits$/, "", data_width_bits)
                data_width_bits += 0
            }
            next
        }

        END {
            flush_dev()

            type_str = "N/A"
            n = 0
            for (t in types)
                type_list[++n] = t
            if (n > 0) {
                type_str = type_list[1]
                for (i = 2; i <= n; i++)
                    type_str = type_str ", " type_list[i]
            }

            manufacturer_str = "N/A"
            m = 0
            for (x in manufacturers)
                manufacturer_list[++m] = x
            if (m > 0) {
                manufacturer_str = manufacturer_list[1]
                for (i = 2; i <= m; i++)
                    manufacturer_str = manufacturer_str ", " manufacturer_list[i]
            }

            speed_str = "N/A"
            s = 0
            for (sp in speeds)
                speed_list[++s] = sp
            if (s > 0) {
                speed_str = speed_list[1] " MT/s"
                for (i = 2; i <= s; i++)
                    speed_str = speed_str ", " speed_list[i] " MT/s"
            }

            printf "total_size_in_gb: %.0f\n", total_mb / 1024.0
            print  "memory_type: " type_str
            print  "configured_speed: " speed_str
            printf "theoretical_bandwidth: %.1f GB/s\n", total_bandwidth_gbs
            print  "manufacturer: " manufacturer_str
        }
    ' >>$OUTPUT_FILE

    printf '\n' >>$OUTPUT_FILE

    sudo dmidecode -t memory 2>/dev/null | awk '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }

        function reset_fields() {
            locator = "N/A"
            size = "N/A"
            type = "N/A"
            speed = "N/A"
            configured_speed = "N/A"
            ranks = "N/A"
            width = "N/A"
            manufacturer = "N/A"
            part_number = "N/A"
            no_module = 0
        }

        function flush() {
            if (!in_dev || no_module)
                return

            print locator "\t" \
                  size "\t" \
                  type "\t" \
                  speed "\t" \
                  configured_speed "\t" \
                  ranks "\t" \
                  width "\t" \
                  manufacturer "\t" \
                  part_number
        }

        BEGIN {
            print "locator\tsize\ttype\tspeed\tconfigured_speed\tranks\twidth\tmanufacturer\tpart_number"
            in_dev = 0
            reset_fields()
        }

        /^Memory Device$/ {
            flush()
            in_dev = 1
            reset_fields()
            next
        }

        !in_dev {
            next
        }

        /^[[:space:]]+Size:/ {
            sub(/^[[:space:]]+Size:[[:space:]]+/, "", $0)
            size = trim($0)
            if (size == "No Module Installed")
                no_module = 1
            next
        }

        /^[[:space:]]+Locator:/ {
            sub(/^[[:space:]]+Locator:[[:space:]]+/, "", $0)
            locator = trim($0)
            next
        }

        /^[[:space:]]+Type:[[:space:]]/ {
            sub(/^[[:space:]]+Type:[[:space:]]+/, "", $0)
            type = trim($0)
            next
        }

        /^[[:space:]]+Speed:/ {
            sub(/^[[:space:]]+Speed:[[:space:]]+/, "", $0)
            speed = trim($0)
            next
        }

        /^[[:space:]]+Configured Memory Speed:/ || /^[[:space:]]+Configured Clock Speed:/ {
            sub(/^[[:space:]]+Configured Memory Speed:[[:space:]]+/, "", $0)
            sub(/^[[:space:]]+Configured Clock Speed:[[:space:]]+/, "", $0)
            configured_speed = trim($0)
            next
        }

        /^[[:space:]]+Rank:/ {
            sub(/^[[:space:]]+Rank:[[:space:]]+/, "", $0)
            ranks = trim($0)
            next
        }

        /^[[:space:]]+Total Width:/ {
            sub(/^[[:space:]]+Total Width:[[:space:]]+/, "", $0)
            width = trim($0)
            next
        }

        /^[[:space:]]+Manufacturer:/ {
            sub(/^[[:space:]]+Manufacturer:[[:space:]]+/, "", $0)
            manufacturer = trim($0)
            next
        }

        /^[[:space:]]+Part Number:/ {
            sub(/^[[:space:]]+Part Number:[[:space:]]+/, "", $0)
            part_number = trim($0)
            next
        }

        END {
            flush()
        }
    ' | column -ts $'\t' >>$OUTPUT_FILE

    printf '[mem static info] FINISHED\n\n' >>$OUTPUT_FILE
}

append_nvidia_kernel_modules() {
    printf '[nvidia kernel modules]\n' >>$OUTPUT_FILE

    {
        for name in $(lsmod | awk 'NR > 1 { print $1 }' | grep '^nvidia'); do
            mod=/sys/module/$name
            [[ -d $mod ]] || continue

            echo module: $name

            if [[ ! -d $mod/parameters ]]; then
                echo '    no parameters'
                echo
                continue
            fi

            for p in $mod/parameters/*; do
                [[ -e $p ]] || continue
                echo "    ${p##*/}: $(cat $p 2>/dev/null || echo N/A)"
            done

            echo
        done
    } >>$OUTPUT_FILE

    printf '[nvidia kernel modules] FINISHED\n\n' >>$OUTPUT_FILE
}

append_nvidia_smi_query() {
    printf '[nvidia-smi gpu query]\n' >>$OUTPUT_FILE

    if ! command -v nvidia-smi >/dev/null 2>&1; then
        echo nvidia-smi: N/A >>$OUTPUT_FILE
        printf '[nvidia-smi gpu query] FINISHED\n\n' >>$OUTPUT_FILE
        return
    fi

    fields=index,name,serial,uuid,driver_version,kmd_version,pci.bus_id,pci.domain,pci.bus,pci.device,pci.baseClass,pci.subClass,pci.device_id,pci.sub_device_id,pcie.link.gen.max,pcie.link.gen.gpumax,pcie.link.gen.hostmax,pcie.link.width.max,display_attached,display_active,persistence_mode,addressing_mode,accounting.mode,accounting.buffer_size,driver_model.current,driver_model.pending,vbios_version,inforom.image,inforom.oem,inforom.ecc,inforom.power,inforom.checksum_validation,gpu_recovery_action,gpu_operation_mode.current,gpu_operation_mode.pending,memory.total,compute_mode,compute_cap,dramEncryption.mode.current,dramEncryption.mode.pending,ecc.mode.current,ecc.mode.pending,power.management,power.limit,enforced.power.limit,power.default_limit,power.min_limit,power.max_limit,clocks.applications.graphics,clocks.applications.memory,clocks.default_applications.graphics,clocks.default_applications.memory,clocks.max.graphics,clocks.max.sm,clocks.max.memory,mig.mode.current,mig.mode.pending,gsp.mode.current,gsp.mode.default,c2c.mode,protected_memory.total,platform.chassis_serial_number,platform.slot_number,platform.tray_index,platform.host_id,platform.peer_type,platform.module_id,platform.gpu_fabric_guid,hostname

    {
        for i in $(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null); do
            paste <(tr ',' '\n' <<< "$fields") \
                <(nvidia-smi --id=$i --query-gpu="$fields" --format=csv,noheader 2>/dev/null | sed 's/, /\n/g') |
                awk -F '\t' '{ print $1 "\t:\t" $2 }' |
                column -t -s $'\t' -L
            echo
        done
    } >>$OUTPUT_FILE

    printf '[nvidia-smi gpu query] FINISHED\n\n' >>$OUTPUT_FILE
}

read_proc_cpu_total_idle() {
    awk '
        /^cpu / {
            total = 0
            for (i = 2; i <= NF; i++)
                total += $i
            print total, $5
            exit
        }
    ' /proc/stat
}

read_meminfo_mb() {
    awk '
        /^MemAvailable:/ { avail = $2 }
        /^MemTotal:/     { total = $2 }
        /^SwapTotal:/    { swap_total = $2 }
        /^SwapFree:/     { swap_free = $2 }
        END {
            printf "%.1f %.1f\n",
                (total - avail) / 1024.0,
                (swap_total - swap_free) / 1024.0
        }
    ' /proc/meminfo
}

read_pid_stat() {
    [[ -r /proc/$1/stat ]] || {
        echo N/A N/A
        return
    }

    python3 - "$1" <<'PY'
import sys

path = f"/proc/{sys.argv[1]}/stat"

try:
    s = open(path, encoding="utf-8").read().rstrip()
except OSError:
    print("N/A N/A")
    raise SystemExit

r = s.rfind(")")
if r < 0:
    print("N/A N/A")
    raise SystemExit

f = s[r + 2:].split()

try:
    utime = int(f[11])
    stime = int(f[12])
    rss = int(f[21])
    print(f"{utime + stime} {rss}")
except (IndexError, ValueError):
    print("N/A N/A")
PY
}

append_dynamic_monitoring() {
    echo '[dynamic monitoring]' >>$OUTPUT_FILE

    if [[ -z $dm_target_pid || ! -d /proc/$dm_target_pid ]]; then
        echo 'dynamic monitoring skipped: invalid or missing pid' >>$OUTPUT_FILE
        echo '[dynamic monitoring] FINISHED' >>$OUTPUT_FILE
        return
    fi

    if ! command -v nvidia-smi >/dev/null 2>&1; then
        echo 'dynamic monitoring skipped: nvidia-smi not found' >>$OUTPUT_FILE
        echo '[dynamic monitoring] FINISHED' >>$OUTPUT_FILE
        return
    fi

    if (( DM_SAMPLE_TIME_LIMIT_S > 0 )); then
        echo "Dynamic monitoring PID $dm_target_pid for $DM_SAMPLE_TIME_LIMIT_S seconds ..."
    else
        echo "Dynamic monitoring PID $dm_target_pid until [ctrl-c] ..."
    fi

    tmp_gpu_latest=$(mktemp /tmp/tmp_gpu_latest.XXXXXX.csv)
    tmp_gpu_raw=$(mktemp /tmp/tmp_gpu_raw.XXXXXX.csv)
    tmp_gpu_swap=$(mktemp /tmp/tmp_gpu_swap.XXXXXX.csv)
    sleep_s=$(awk -v ms=$DM_SAMPLE_FREQ_MS 'BEGIN { printf "%.3f\n", ms / 1000.0 }')
    page_size=$(getconf PAGESIZE)
    gpu_sampler_pid=

    if nvidia-smi --help-query-gpu 2>/dev/null | grep -q 'bar1_memory.used'; then
        gpu_query_fields=utilization.gpu,utilization.memory,clocks.sm,clocks.mem,power.draw,temperature.gpu,memory.used,bar1_memory.used
        gpu_has_bar1=1
    else
        gpu_query_fields=utilization.gpu,utilization.memory,clocks.sm,clocks.mem,power.draw,temperature.gpu,memory.used
        gpu_has_bar1=0
    fi

    cleanup_dynamic_monitoring() {
        [[ -n $gpu_sampler_pid ]] && kill -- -$gpu_sampler_pid 2>/dev/null
        rm -f $tmp_gpu_latest $tmp_gpu_raw $tmp_gpu_swap
    }

    request_stop_dynamic_monitoring() {
        stop_requested=1
        echo 
        echo 'Dynamic monitoring finished'
    }

    trap cleanup_dynamic_monitoring EXIT
    trap request_stop_dynamic_monitoring INT TERM

    echo 'ts_ms,gpu_util,gpu_mem_util,gpu_sm_mhz,gpu_mem_mhz,gpu_power_w,gpu_temp_c,gpu_local_mem_used_mb,gpu_bar1_used_mb,cpu_util_pct,cpu_mem_used_mb,swap_used_mb,target_cpu_of_system_pct,target_rss_mb' >$dm_output_file

    setsid bash -c '
        set -o pipefail

        nvidia-smi \
            --query-gpu='"$gpu_query_fields"' \
            --format=csv,noheader,nounits \
            --loop-ms='"$DM_SAMPLE_FREQ_MS"' 2>/dev/null |
        tee -a '"$tmp_gpu_raw"' |
        while IFS= read -r line; do
            [[ -n $line ]] || continue
            printf "%s\n" "$line" >'"$tmp_gpu_swap"'
            mv '"$tmp_gpu_swap"' '"$tmp_gpu_latest"'
        done
    ' &
    gpu_sampler_pid=$!

    read prev_total prev_idle < <(read_proc_cpu_total_idle)
    read prev_target_jiffies _ < <(read_pid_stat $dm_target_pid)

    start_s=$(date +%s)

    while [[ -d /proc/$dm_target_pid ]]; do
        if (( stop_requested )); then
            break
        fi

        if (( DM_SAMPLE_TIME_LIMIT_S > 0 )) && (( $(date +%s) - start_s >= DM_SAMPLE_TIME_LIMIT_S )); then
            break
        fi

        now_ms=$(date +%s%3N)

        gpu_util=N/A
        gpu_mem_util=N/A
        gpu_sm_mhz=N/A
        gpu_mem_mhz=N/A
        gpu_power_w=N/A
        gpu_temp_c=N/A
        gpu_local_mem_used_mb=N/A
        gpu_bar1_used_mb=N/A

        if [[ -r $tmp_gpu_latest ]]; then
            if (( gpu_has_bar1 )); then
                IFS=, read -r \
                    gpu_util gpu_mem_util gpu_sm_mhz gpu_mem_mhz gpu_power_w gpu_temp_c gpu_local_mem_used_mb gpu_bar1_used_mb \
                    < $tmp_gpu_latest
            else
                IFS=, read -r \
                    gpu_util gpu_mem_util gpu_sm_mhz gpu_mem_mhz gpu_power_w gpu_temp_c gpu_local_mem_used_mb \
                    < $tmp_gpu_latest
                gpu_bar1_used_mb=N/A
            fi

            gpu_util=${gpu_util# }
            gpu_mem_util=${gpu_mem_util# }
            gpu_sm_mhz=${gpu_sm_mhz# }
            gpu_mem_mhz=${gpu_mem_mhz# }
            gpu_power_w=${gpu_power_w# }
            gpu_temp_c=${gpu_temp_c# }
            gpu_local_mem_used_mb=${gpu_local_mem_used_mb# }
            gpu_bar1_used_mb=${gpu_bar1_used_mb# }
        fi

        read cur_total cur_idle < <(read_proc_cpu_total_idle)
        total_delta=$((cur_total - prev_total))
        idle_delta=$((cur_idle - prev_idle))

        if (( total_delta > 0 )); then
            cpu_util_pct=$(awk -v t=$total_delta -v i=$idle_delta 'BEGIN { printf "%.1f", 100.0 * (t - i) / t }')
        else
            cpu_util_pct=N/A
        fi

        prev_total=$cur_total
        prev_idle=$cur_idle

        read cpu_mem_used_mb swap_used_mb < <(read_meminfo_mb)
        read cur_target_jiffies target_rss_pages < <(read_pid_stat $dm_target_pid)

        if [[ $cur_target_jiffies != N/A && $prev_target_jiffies != N/A && $total_delta -gt 0 ]]; then
            target_cpu_pct=$(awk -v d=$((cur_target_jiffies - prev_target_jiffies)) -v t=$total_delta 'BEGIN { printf "%.1f", 100.0 * d / t }')
        else
            target_cpu_pct=N/A
        fi

        prev_target_jiffies=$cur_target_jiffies

        if [[ $target_rss_pages != N/A ]]; then
            target_rss_mb=$(awk -v p=$target_rss_pages -v ps=$page_size 'BEGIN { printf "%.1f", p * ps / 1024.0 / 1024.0 }')
        else
            target_rss_mb=N/A
        fi

        echo "$now_ms,$gpu_util,$gpu_mem_util,$gpu_sm_mhz,$gpu_mem_mhz,$gpu_power_w,$gpu_temp_c,$gpu_local_mem_used_mb,$gpu_bar1_used_mb,$cpu_util_pct,$cpu_mem_used_mb,$swap_used_mb,$target_cpu_pct,$target_rss_mb" >>$dm_output_file

        sleep $sleep_s || true
    done

    echo "dm output csv file: $dm_output_file" >>$OUTPUT_FILE
    if [[ ! -z $(which draw-polylines-in-html.py) ]]; then 
        python3 $(which draw-polylines-in-html.py | head -1) $dm_output_file && 
        echo "dm output graph file: ${dm_output_file%.*}.html" >>$OUTPUT_FILE ||
        echo "failed to generate html graph from $dm_output_file" >>$OUTPUT_FILE
    fi 
    echo '[dynamic monitoring] FINISHED' >>$OUTPUT_FILE
}

append_basic_header
append_environment
append_cpu_static_info
append_mem_static_info
append_nvidia_kernel_modules
append_nvidia_smi_query
append_dynamic_monitoring