#!/usr/bin/env bash
#
# collect-system-info.sh - Collect system hardware and environment information.
#
# DESCRIPTION
#   This script gathers static system information (CPU, memory, GPU, kernel,
#   environment) and writes it to a file or prints a brief summary. It supports
#   two modes:
#
#   Full mode (default): Appends multiple sections to OUTPUT_FILE (default
#   ~/system_info.txt): basic header (hostname, OS, kernel, CPU model, GPUs),
#   environment variables, CPU static info (lscpu, power limits, per-CPU
#   cpufreq/governor), memory static info (dmidecode summary and per-DIMM
#   table), NVIDIA kernel module parameters, and full nvidia-smi/lspci output
#   per GPU. Used for detailed system profiling or debugging.
#
#   Brief mode (first positional argument "brief"): Writes a short summary to
#   /tmp/brief (hostname, OS, kernel, memory summary, CPU summary including
#   P-core/E-core on Intel, GPU list with key attributes) and displays it via
#   print-ascii-tree.sh if available, else cat. Exits after printing.
#
# KEY RELATIONSHIPS
#   - print_mem_brief() is used both in brief mode and by append_mem_static_info().
#   - print_cpu_* and count_cpu_core_list() are used in brief mode and by
#     append_cpu_static_info().
#   - print_gpu_info() is used in brief mode (fixed attribute list) and by
#     append_nvidia_smi_query() (full attribute list).
#   - All append_* functions write to the same OUTPUT_FILE in sequence to
#     build the full report.
#
# REQUIREMENTS
#   Bash; optional: dmidecode (sudo), nvidia-smi, powerprofilesctl, lsb_release,
#   print-ascii-tree.sh. Some sections output "N/A" when tools or sysfs paths
#   are missing (e.g. non-Intel, no NVIDIA GPU).
#
set -o pipefail

OUTPUT_FILE=~/system_info.txt

# Print usage and exit. Used for -h/--help.
print_usage() {
    cat <<'USAGE'
Usage: collect-system-info.sh [OPTIONS] [brief]

Collect system hardware and environment information.

OPTIONS
  -h, --help       Show this help and exit.
  -o, --output F   Write full report to F (default: ~/system_info.txt).

ARGUMENTS
  brief            Print a brief summary to stdout and exit (writes to /tmp/brief).

With no arguments, writes the full report to the output file.
USAGE
}

# Parse -h/--help and -o/--output. Leaves positional args (e.g. "brief") in $@.
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            print_usage
            exit 0
            ;;
        -o|--output)
            if [[ -z ${2:-} ]]; then
                echo "Error: -o/--output requires an argument." >&2
                print_usage >&2
                exit 1
            fi
            OUTPUT_FILE="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Memory: parse dmidecode -t memory and output a one-line summary (total size,
# type, configured speed, theoretical bandwidth, manufacturer). Uses awk to
# parse "Memory Device" blocks and aggregate; flush_dev() commits each slot;
# empty slots (No Module Installed) are skipped. Output is key: value lines.
# -----------------------------------------------------------------------------
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
        # State machine: in_dev = inside a "Memory Device" block; flush_dev() commits slot and resets for next block or END.

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

# Read Intel RAPL long-term power limit (microwatts) from sysfs. Outputs
# "max_power_limit_uw: <value>" or "N/A" if not available (e.g. non-Intel).
print_cpu_max_power_limit_uw() {
    if [[ -r /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw ]]; then
        echo max_power_limit_uw: "$(cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw)" 
    else
        echo max_power_limit_uw: N/A 
    fi
}

# Read Intel P-state driver status (active/passive/off) from sysfs. Outputs
# "intel_pstate: <value>" or "N/A" if not present.
print_cpu_intel_pstate() {
    if [[ -r /sys/devices/system/cpu/intel_pstate/status ]]; then
        echo intel_pstate: "$(cat /sys/devices/system/cpu/intel_pstate/status)" 
    else
        echo intel_pstate: N/A 
    fi
}

# For a given CPU index ($1), print max_freq_khz, scaling_driver,
# scaling_governor, energy_perf_bias, energy_performance_preference from
# sysfs. Used for one representative core in brief mode and referenced
# by append_cpu_static_info for per-CPU table.
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

# Print current power profile (e.g. power-saver/balanced/performance) via
# powerprofilesctl if available; otherwise "N/A". Linux power-profiles-daemon.
print_cpu_power_profile() {
    if command -v powerprofilesctl >/dev/null 2>&1; then
        echo power_profile: "$(powerprofilesctl get 2>/dev/null || echo N/A)" 
    else
        echo power_profile: N/A 
    fi
}

# Count logical cores from a CPU list on stdin (e.g. "0-3,8,10-11"). Expands
# ranges and single numbers; used for P-core/E-core counts on Intel.
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

# For GPU id $1 and comma-separated nvidia-smi attribute list $2, query each
# attribute and print "key: value" lines. Used by brief mode and
# append_nvidia_smi_query() with different attribute sets.
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

# --- Brief mode: write summary to /tmp/brief and display (tree or cat), then exit. ---
if [[ $1 == brief ]]; then
    hostname >/tmp/brief
    printf '\tOS: %s\n' "$(lsb_release -a | grep Description | awk '{print $2 " " $3}')" >>/tmp/brief
    printf '\t\tKernel: %s\n' "$(uname -r)" >>/tmp/brief
    printf '\t\tMemory:\n' >>/tmp/brief
    print_mem_brief | sed 's/^/\t\t\t/' >>/tmp/brief

    printf '\tCPU: %s\n' "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')" >>/tmp/brief
    printf '\t\tMax clock: %s\n' "$(awk '{print $1 / 1000000}' /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq)" >>/tmp/brief
    printf '\t\t%s\n' "$(print_cpu_max_power_limit_uw)" >>/tmp/brief
    printf '\t\t%s\n' "$(print_cpu_intel_pstate)" >>/tmp/brief
    printf '\t\t%s\n' "$(print_cpu_power_profile)" >>/tmp/brief
    # Intel: report P-cores and E-cores separately from sysfs cpu_core/cpu_atom; else total cores and cpu0.
    if grep -qi '^vendor_id[[:space:]]*:[[:space:]]*GenuineIntel$' /proc/cpuinfo; then
        printf '\t\tNumber of P-cores: %s\n' $(count_cpu_core_list </sys/devices/cpu_core/cpus) >>/tmp/brief
        print_cpu_core_info $(cat /sys/devices/cpu_core/cpus | cut -d- -f1) | sed 's/^/\t\t\t/' >>/tmp/brief
        printf '\t\tNumber of E-cores: %s\n' $(count_cpu_core_list </sys/devices/cpu_atom/cpus) >>/tmp/brief
        print_cpu_core_info $(cat /sys/devices/cpu_atom/cpus | cut -d- -f1) | sed 's/^/\t\t\t/' >>/tmp/brief
    else
        printf '\t\tNumber of cores: %s\n' "$(grep -c '^processor' /proc/cpuinfo)" >>/tmp/brief
        print_cpu_core_info 0 | sed 's/^/\t\t\t/' >>/tmp/brief
    fi

    # One subsection per GPU: name and key attributes via print_gpu_info.
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

# Write hostname, OS description (lsb_release), uname -srm, CPU model (lscpu),
# and nvidia-smi -L to OUTPUT_FILE. Overwrites OUTPUT_FILE; later append_*
# functions append.
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

# Append a filtered dump of environment variables to OUTPUT_FILE. Excludes
# noisy or session-specific vars (e.g. PTYXIS_PROFILE, SSH_*, LS_COLORS).
append_environment() {
    printf '[environment variables]\n' >>$OUTPUT_FILE
    env | grep -Ev 'PTYXIS_PROFILE|guid=|INVOCATION_ID=|LS_COLORS|MEMORY_PRESSURE_WRITE=|MEMORY_PRESSURE_WATCH=|SSH_CONNECTION=|SSH_CLIENT=|OLDPWD=' >>$OUTPUT_FILE
    printf '[environment variables] FINISHED\n\n' >>$OUTPUT_FILE
}

# Append lscpu, RAPL power limit, intel_pstate, power profile, and a per-CPU
# table (max_freq, scaling_driver, governor, energy_perf_*) to OUTPUT_FILE.
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

# Append memory section: print_mem_brief summary, then a per-DIMM table from
# dmidecode (locator, size, type, speed, ranks, width, manufacturer, part_number).
# Uses awk to parse "Memory Device" blocks; flush() writes one row per installed DIMM.
append_mem_static_info() {
    printf '[mem static info]\n' >>$OUTPUT_FILE

    if ! command -v dmidecode >/dev/null 2>&1; then
        echo dmidecode: N/A >>$OUTPUT_FILE
        printf '[mem static info] FINISHED\n\n' >>$OUTPUT_FILE
        return
    fi

    print_mem_brief >>$OUTPUT_FILE
    printf '\n' >>$OUTPUT_FILE

    # Parse dmidecode -t memory into a table: one row per installed DIMM;
    # flush() emits a row when leaving a device block; empty slots are skipped.
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

# Append names and parameters of all loaded kernel modules matching "nvidia"
# (from lsmod). For each module, list /sys/module/<name>/parameters/*.
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

# Append full nvidia-smi query (all listed fields) per GPU and lspci -vv for
# each GPU's PCI bus. Uses print_gpu_info() with the full field list; then
# sudo lspci -vv -s <bus_id> for detailed PCI config.
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

# --- Full report: run all append_* functions in order to build OUTPUT_FILE. ---
append_basic_header
append_environment
append_cpu_static_info
append_mem_static_info
append_nvidia_kernel_modules
append_nvidia_smi_query