#!/usr/bin/env bash

set -o pipefail

OUTPUT_FILE=~/system_info.txt

print_mem_brief() {
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
    '
}

print_cpu_max_power_limit_uw() {
    if [[ -r /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw ]]; then
        echo max_power_limit_uw: "$(cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw)" 
    else
        echo max_power_limit_uw: N/A 
    fi
}

print_cpu_intel_pstate() {
    if [[ -r /sys/devices/system/cpu/intel_pstate/status ]]; then
        echo intel_pstate: "$(cat /sys/devices/system/cpu/intel_pstate/status)" 
    else
        echo intel_pstate: N/A 
    fi
}

print_cpu_core_info() {
    if [[ -e /sys/devices/system/cpu/cpu$1 ]]; then 
        cpu=/sys/devices/system/cpu/cpu$1 
        printf 'max_freq_khz: %s\n' "$( [[ -r $cpu/cpufreq/cpuinfo_max_freq ]] && cat $cpu/cpufreq/cpuinfo_max_freq || echo N/A )"
        printf 'scaling_driver: %s\n' "$( [[ -r $cpu/cpufreq/scaling_driver ]] && cat $cpu/cpufreq/scaling_driver || echo N/A )"
        printf 'scaling_governor: %s\n' "$( [[ -r $cpu/cpufreq/scaling_governor ]] && cat $cpu/cpufreq/scaling_governor || echo N/A )"
        printf 'energy_perf_bias: %s\n' "$( [[ -r $cpu/power/energy_perf_bias ]] && cat $cpu/power/energy_perf_bias || echo N/A )"
        printf 'energy_performance_preference: %s\n' "$( [[ -r $cpu/cpufreq/energy_performance_preference ]] && cat $cpu/cpufreq/energy_performance_preference || echo N/A )"
    fi 
}

print_cpu_power_profile() {
    if command -v powerprofilesctl >/dev/null 2>&1; then
        echo power_profile: "$(powerprofilesctl get 2>/dev/null || echo N/A)" 
    else
        echo power_profile: N/A 
    fi
}

count_cpu_core_list() {
    awk -F, '
        {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /-/) {
                    split($i, a, "-")
                    n += a[2] - a[1] + 1
                } else if ($i ~ /^[0-9]+$/) {
                    n++
                }
            }
        }
        END {
            print n + 0
        }
    '
}

print_gpu_info() {
    local gpu_id=$1
    local attributes=$2
    local attr
    shopt -s extglob
    while IFS= read -r attr; do
        attr=${attr##+([[:space:]])}
        attr=${attr%%+([[:space:]])}
        [[ -n $attr ]] || continue
        nvidia-smi --id=$gpu_id \
            --query-gpu="$attr" \
            --format=csv,noheader 2>/dev/null |
        awk -v key=$attr '{ print key ": " $0 }'
    done < <(tr ',' '\n' <<< "$attributes" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    shopt -u extglob
}

if [[ $1 == brief ]]; then 
    hostname >/tmp/brief
    printf '\tOS: %s\n' "$(lsb_release -a | grep Description | awk '{print $2 " " $3}')" >>/tmp/brief
    printf '\t\tKernel: %s\n' "$(uname -r)" >>/tmp/brief
    printf '\t\tMemory:\n' >>/tmp/brief
    print_mem_brief | sed 's/^/\t\t/' >>/tmp/brief

    printf '\tCPU: %s\n' "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')" >>/tmp/brief
    printf '\t\tMax clock: %s\n' "$(awk '{print $1 / 1000000}' /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq)" >>/tmp/brief
    printf '\t\t%s\n' "$(print_cpu_max_power_limit_uw)" >>/tmp/brief
    printf '\t\t%s\n' "$(print_cpu_intel_pstate)" >>/tmp/brief
    printf '\t\t%s\n' "$(print_cpu_power_profile)" >>/tmp/brief
    if grep -qi '^vendor_id[[:space:]]*:[[:space:]]*GenuineIntel$' /proc/cpuinfo; then
        printf '\t\tNumber of P-cores: %s\n' $(count_cpu_core_list </sys/devices/cpu_core/cpus) >>/tmp/brief
        print_cpu_core_info $(cat /sys/devices/cpu_core/cpus | cut -d- -f1) | sed 's/^/\t\t\t/' >>/tmp/brief
        printf '\t\tNumber of E-cores: %s\n' $(count_cpu_core_list </sys/devices/cpu_atom/cpus) >>/tmp/brief
        print_cpu_core_info $(cat /sys/devices/cpu_atom/cpus | cut -d- -f1) | sed 's/^/\t\t\t/' >>/tmp/brief
    else
        printf '\t\tNumber of cores: %s\n' "$(grep -c '^processor' /proc/cpuinfo)" >>/tmp/brief
        print_cpu_core_info 0 | sed 's/^/\t\t\t/' >>/tmp/brief
    fi 
    
    for gpu_id in $(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null); do
        printf '\tGPU %s: %s\n' "$gpu_id" "$(nvidia-smi --id=$gpu_id --query-gpu=name --format=noheader)" >>/tmp/brief
        print_gpu_info $gpu_id "driver_version,pcie.link.gen.max,pcie.link.gen.gpumax,pcie.link.gen.hostmax,pcie.link.width.max,display_attached,display_active,persistence_mode,vbios_version,memory.total,compute_cap,power.limit,enforced.power.limit,power.default_limit,power.min_limit,power.max_limit,clocks.max.graphics,clocks.max.sm,clocks.max.memory,gsp.mode.current,gsp.mode.default,c2c.mode,protected_memory.total" | sed 's/^/\t\t/' >>/tmp/brief
    done

    if [[ ! -z $(which print-ascii-tree.sh) ]]; then 
        print-ascii-tree.sh /tmp/brief 
    else
        cat /tmp/brief 
    fi 

    exit 
fi 

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
    env | grep -Ev 'PTYXIS_PROFILE|guid=|INVOCATION_ID=|LS_COLORS|MEMORY_PRESSURE_WRITE=|MEMORY_PRESSURE_WATCH=|SSH_CONNECTION=|SSH_CLIENT=|OLDPWD=' >>$OUTPUT_FILE
    printf '[environment variables] FINISHED\n\n' >>$OUTPUT_FILE
}

append_cpu_static_info() {
    printf '[cpu static info]\n' >>$OUTPUT_FILE

    lscpu >>$OUTPUT_FILE
    printf '\n' >>$OUTPUT_FILE
    print_cpu_max_power_limit_uw >>$OUTPUT_FILE
    print_cpu_intel_pstate >>$OUTPUT_FILE
    print_cpu_power_profile >>$OUTPUT_FILE

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

    print_mem_brief >>$OUTPUT_FILE
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

    fields=index,name,serial,uuid,driver_version,kmd_version,pci.bus_id,pci.domain,pci.bus,pci.device,pci.baseClass,pci.subClass,pci.device_id,pci.sub_device_id,pcie.link.gen.max,pcie.link.gen.gpumax,pcie.link.gen.hostmax,pcie.link.width.max,display_attached,display_active,persistence_mode,addressing_mode,accounting.mode,accounting.buffer_size,driver_model.current,driver_model.pending,vbios_version,inforom.image,inforom.oem,inforom.ecc,inforom.power,inforom.checksum_validation,gpu_recovery_action,gpu_operation_mode.current,gpu_operation_mode.pending,memory.total,compute_mode,compute_cap,dramEncryption.mode.current,dramEncryption.mode.pending,ecc.mode.current,ecc.mode.pending,power.management,power.limit,enforced.power.limit,power.default_limit,power.min_limit,power.max_limit,clocks.applications.graphics,clocks.applications.memory,clocks.default_applications.graphics,clocks.default_applications.memory,clocks.max.graphics,clocks.max.sm,clocks.max.memory,clocks_event_reasons.supported,mig.mode.current,mig.mode.pending,gsp.mode.current,gsp.mode.default,c2c.mode,protected_memory.total,platform.chassis_serial_number,platform.slot_number,platform.tray_index,platform.host_id,platform.peer_type,platform.module_id,platform.gpu_fabric_guid,hostname

    {
        for i in $(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null); do
            print_gpu_info $i "$fields" | sed 's/: /\t:\t/' | column -t -s $'\t' -L
            echo
        done
    } >>$OUTPUT_FILE

    {
        for i in $(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null); do
            sudo lspci -vv -s $(nvidia-smi --id=$i --query-gpu=pci.bus_id --format=csv,noheader | sed 's/^00000000://')
            echo
        done
    } >>$OUTPUT_FILE

    printf '[nvidia-smi gpu query] FINISHED\n\n' >>$OUTPUT_FILE
}


append_basic_header
append_environment
append_cpu_static_info
append_mem_static_info
append_nvidia_kernel_modules
append_nvidia_smi_query