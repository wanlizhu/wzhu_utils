#!/usr/bin/env bash
set -o pipefail

OUTPUT_FILE=$HOME/system_info.txt

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
        raw_info=$(nvidia-smi --id=$gpu_id --query-gpu="$attr" --format=csv,noheader 2>/dev/null | awk -v key=$attr '{ print key ": " $0 }')
        if [[ $raw_info == *driver_version* ]]; then 
            raw_info+=" ($(nvidia_driver_build_type))"
        fi 
        echo "$raw_info"
    done < <(tr ',' '\n' <<< "$attributes" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    shopt -u extglob
}
nvidia_driver_build_type() {
    [[ ! -z $(cat /proc/driver/nvidia/version | head -1 | grep 'Release Build') ]] && echo "release build"
    [[ ! -z $(cat /proc/driver/nvidia/version | head -1 | grep 'Debug Build') ]] && echo "debug build"
    [[ ! -z $(cat /proc/driver/nvidia/version | head -1 | grep 'Develop Build') ]] && echo "develop build"
}

# For display related info which requires valid env var DISPLAY 
print_display_info() {
    local wayland_display=$(ls /run/user/$(id -u)/wayland-[0-9] 2>/dev/null)
    local xrandr_out connector line
    local found=0

    if [[ $XDG_SESSION_TYPE == tty ]]; then 
        export DISPLAY=:0
        export XAUTHORITY=$(tr '\0' '\n' </proc/$(pgrep -n gnome-shell)/environ | grep '^XAUTHORITY=' | awk -F'=' '{print $2}')
        export XDG_RUNTIME_DIR=/run/user/$(id -u)
        export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
        echo "DISPLAY=$DISPLAY"
        echo "XAUTHORITY=$XAUTHORITY"
        echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
        echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
        if [[ ! -z $wayland_display ]]; then 
            export WAYLAND_DISPLAY=$(basename $wayland_display)
            echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
        fi 
    fi 

    xrandr --current >/dev/null 2>&1 || {
        echo "[Failed to connect to X11]"
        return 
    }

    for path in /sys/class/drm/card*-*; do
        [[ -f $path/status ]] || continue
        [[ $(<"$path/status") == connected ]] || continue

        found=1
        connector=${path##*/}
        connector=${connector#card*-}
        local display_name="Unknown Display"
        local current_resolution="N/A"
        local refresh_rate="N/A"
        local color_depth_bpc="N/A"
        local colorspace="N/A"
        local connection_type=${connector%-*}
        local vrr_capable="N/A"
        local link_status="N/A"
        local physical_size="N/A"

        if [[ -f $path/edid ]]; then
            local edid_out
            edid_out=$(edid-decode "$path/edid" 2>/dev/null)

            if [[ -n $edid_out ]]; then
                while IFS= read -r line; do
                    if [[ $line =~ Display[[:space:]]+Product[[:space:]]+Name:[[:space:]]*(.+) ]]; then
                        [[ ${BASH_REMATCH[1]} != invalid && -n ${BASH_REMATCH[1]} ]] && display_name=${BASH_REMATCH[1]}
                    elif [[ $line =~ Maximum[[:space:]]+image[[:space:]]+size:[[:space:]]*(.+) ]]; then
                        physical_size=${BASH_REMATCH[1]}
                    elif [[ $line =~ Display[[:space:]]+size:[[:space:]]*([0-9]+)[[:space:]]*x[[:space:]]*([0-9]+)[[:space:]]*mm ]]; then
                        [[ $physical_size == N/A ]] && physical_size="${BASH_REMATCH[1]} x ${BASH_REMATCH[2]} mm"
                    elif [[ $line =~ Bits[[:space:]]+per[[:space:]]+primary[[:space:]]+color[[:space:]]+channel:[[:space:]]*(.+) ]]; then
                        color_depth_bpc=${BASH_REMATCH[1]}
                    fi
                done <<< "$edid_out"
            fi
        fi

        local in_block=0
        while IFS= read -r line; do
            if [[ $line != [[:space:]]* && $line == "$connector connected"* ]]; then
                in_block=1
                continue
            fi

            if (( in_block )) && [[ $line != [[:space:]]* && $line == *" connected"* ]]; then
                break
            fi

            (( in_block )) || continue

            if [[ $line =~ ^[[:space:]]+([0-9]+x[0-9]+)[[:space:]]+([0-9.]+)([*+[:space:]]*) ]] && [[ ${BASH_REMATCH[3]} == *"*"* ]]; then
                current_resolution=${BASH_REMATCH[1]}
                refresh_rate=${BASH_REMATCH[2]}
            elif [[ $line =~ ^[[:space:]]*max[[:space:]]+bpc:[[:space:]]*(.+) ]]; then
                color_depth_bpc=${BASH_REMATCH[1]}
            elif [[ $line =~ ^[[:space:]]*Colorspace:[[:space:]]*(.+) ]]; then
                colorspace=${BASH_REMATCH[1]}
            elif [[ $line =~ ^[[:space:]]*vrr_capable:[[:space:]]*(.+) ]]; then
                vrr_capable=${BASH_REMATCH[1]}
                [[ $vrr_capable == 1 ]] && vrr_capable=yes
                [[ $vrr_capable == 0 ]] && vrr_capable=no
            elif [[ $line =~ ^[[:space:]]*link-status:[[:space:]]*(.+) ]]; then
                link_status=${BASH_REMATCH[1]}
            fi
        done <<< "$xrandr_out"

        if [[ ! -z $wayland_display ]]; then 
            echo "$connector $display_name (Xwayland)"
        else 
            echo "$connector $display_name (X11)"
        fi 
        echo -e "\tcurrent_resolution: $current_resolution"
        echo -e "\trefresh_rate: $refresh_rate"
        echo -e "\tcolor_depth_bpc: $color_depth_bpc"
        echo -e "\tcolorspace: $colorspace"
        echo -e "\tconnection_type: $connection_type"
        echo -e "\tvrr_capable: $vrr_capable"
        echo -e "\tlink_status: $link_status"
        echo -e "\tphysical_size: $physical_size"
    done

    (( found )) || echo "[No display connected]"
}

hostname >$OUTPUT_FILE
printf '\tOS: %s\n' "$(lsb_release -a | grep Description | awk '{print $2 " " $3}')" >>$OUTPUT_FILE
printf '\t\tKernel: %s\n' "$(uname -r)" >>$OUTPUT_FILE
printf '\t\tMemory:\n' >>$OUTPUT_FILE
print_mem_brief | sed 's/^/\t\t\t/' >>$OUTPUT_FILE

printf '\tCPU: %s\n' "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')" >>$OUTPUT_FILE
printf '\t\tMax clock: %s\n' "$(awk '{print $1 / 1000000}' /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq)" >>$OUTPUT_FILE
printf '\t\t%s\n' "$(print_cpu_max_power_limit_uw)" >>$OUTPUT_FILE
printf '\t\t%s\n' "$(print_cpu_intel_pstate)" >>$OUTPUT_FILE
printf '\t\t%s\n' "$(print_cpu_power_profile)" >>$OUTPUT_FILE
# Intel: report P-cores and E-cores separately from sysfs cpu_core/cpu_atom; else total cores and cpu0.
if grep -qi '^vendor_id[[:space:]]*:[[:space:]]*GenuineIntel$' /proc/cpuinfo; then
    if [[ -e /sys/devices/cpu_core/cpus && -e /sys/devices/cpu_atom/cpus ]]; then 
        printf '\t\tNumber of P-cores: %s\n' $(count_cpu_core_list </sys/devices/cpu_core/cpus) >>$OUTPUT_FILE
        print_cpu_core_info $(cat /sys/devices/cpu_core/cpus | cut -d- -f1) | sed 's/^/\t\t\t/' >>$OUTPUT_FILE
        printf '\t\tNumber of E-cores: %s\n' $(count_cpu_core_list </sys/devices/cpu_atom/cpus) >>$OUTPUT_FILE
        print_cpu_core_info $(cat /sys/devices/cpu_atom/cpus | cut -d- -f1) | sed 's/^/\t\t\t/' >>$OUTPUT_FILE
    else
        printf '\t\tNumber of P-cores: N/A\n' >>$OUTPUT_FILE
        printf '\t\tNumber of E-cores: N/A\n' >>$OUTPUT_FILE
    fi 
else
    printf '\t\tNumber of cores: %s\n' "$(grep -c '^processor' /proc/cpuinfo)" >>$OUTPUT_FILE
    print_cpu_core_info 0 | sed 's/^/\t\t\t/' >>$OUTPUT_FILE
fi

# One subsection per GPU: name and key attributes via print_gpu_info.
for gpu_id in $(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null); do
    printf '\tGPU %s: %s\n' "$gpu_id" "$(nvidia-smi --id=$gpu_id --query-gpu=name --format=noheader)" >>$OUTPUT_FILE
    print_gpu_info $gpu_id "driver_version,pcie.link.gen.max,pcie.link.gen.gpumax,pcie.link.gen.hostmax,pcie.link.width.max,display_attached,display_active,persistence_mode,vbios_version,memory.total,compute_cap,power.limit,enforced.power.limit,power.default_limit,power.min_limit,power.max_limit,clocks.max.graphics,clocks.max.sm,clocks.max.memory,gsp.mode.current,gsp.mode.default,c2c.mode,protected_memory.total" | sed 's/^/\t\t/' >>$OUTPUT_FILE
done

print_display_info | sed 's/^/\t\t/' >>$OUTPUT_FILE

if [[ ! -z $(which print-ascii-tree.sh) ]]; then 
    print-ascii-tree.sh $OUTPUT_FILE >/tmp/tree
    mv -f /tmp/tree $OUTPUT_FILE
fi 

cat $OUTPUT_FILE 
