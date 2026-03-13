#!/usr/bin/env bash

set -o pipefail
output=~/system_info.d
rm -rf "$output"
mkdir -p "$output"
sudo -v || exit 1

dump_stdout_of() {
    local type=$1
    local name=$2
    shift 2

    {
        if [[ $type == cmd ]]; then
            printf '>>'
            printf ' %q' "$@"
            printf '\n'
            "$@"
        elif [[ $type == shell ]]; then
            printf '>> %s\n' "$*"
            bash -lc "$*"
        else
            printf 'unknown type: %s\n' "$type"
            return 1
        fi
    } >"$output/$name.txt" 2>&1
}

collect_basic_system_info() {
    dump_stdout_of cmd env env
    dump_stdout_of cmd lscpu lscpu
    dump_stdout_of cmd lsblk lsblk -a -o NAME,PATH,MAJ:MIN,RM,SIZE,RO,TYPE,FSTYPE,FSVER,FSAVAIL,FSUSE%,MOUNTPOINTS,MODEL,SERIAL,UUID,PARTUUID
    dump_stdout_of cmd blkid blkid
    dump_stdout_of cmd df df -hT
    dump_stdout_of cmd free free -h
    dump_stdout_of cmd swapon swapon --show
    dump_stdout_of cmd mount mount
    dump_stdout_of cmd findmnt findmnt -A -R
    dump_stdout_of cmd timedatectl timedatectl
    dump_stdout_of cmd localectl localectl
    dump_stdout_of cmd systemd_analyze systemd-analyze
    dump_stdout_of cmd bootctl bootctl status
    dump_stdout_of cmd efibootmgr sudo efibootmgr -v

    dump_stdout_of shell os_release 'cat /etc/os-release'
    dump_stdout_of shell boot_config 'cat /boot/config-$(uname -r)'
    dump_stdout_of shell cmdline 'cat /proc/cmdline'
    dump_stdout_of shell cpuinfo 'cat /proc/cpuinfo'
    dump_stdout_of shell meminfo 'cat /proc/meminfo'
    dump_stdout_of shell interrupts 'cat /proc/interrupts'
    dump_stdout_of shell iomem 'cat /proc/iomem'
    dump_stdout_of shell modules 'cat /proc/modules'
    dump_stdout_of shell fstab 'cat /etc/fstab'
}

collect_hardware_info() {
    dump_stdout_of cmd dmidecode sudo dmidecode
    dump_stdout_of cmd lspci lspci -vvnn
    dump_stdout_of cmd lsusb lsusb -tv
    dump_stdout_of cmd sensors sensors

    dump_stdout_of shell gpu_pci_detail '
for d in /sys/bus/pci/devices/*; do
    [[ -f $d/vendor && -f $d/device && -f $d/class ]] || continue

    v=$(cat $d/vendor)
    c=$(cat $d/class)

    if [[ $v == 0x10de || $c == 0x030000 || $c == 0x030200 ]]; then
        echo "## $d"
        for f in vendor device subsystem_vendor subsystem_device class numa_node current_link_speed current_link_width max_link_speed max_link_width resource; do
            [[ -f $d/$f ]] || continue
            printf "%s: %s\n" "$f" "$(cat $d/$f 2>/dev/null)"
        done
        echo
    fi
done
'
}

collect_boot_and_service_info() {
    dump_stdout_of shell dmesg 'dmesg -T'
    dump_stdout_of shell journal_boot 'journalctl -b --no-pager'
    dump_stdout_of shell failed_units 'systemctl --failed --no-pager'
    dump_stdout_of shell units 'systemctl list-units --type=service --all --no-pager'
    dump_stdout_of shell unit_files 'systemctl list-unit-files --no-pager'
}

collect_package_and_config_info() {
    dump_stdout_of shell apt_installed 'dpkg-query -W -f='\''${binary:Package}\t${Version}\t${Architecture}\n'\'' | LC_ALL=C sort'
    dump_stdout_of shell apt_manual 'apt-mark showmanual | LC_ALL=C sort'
    dump_stdout_of shell apt_policy_nvidia 'apt-cache policy '\''nvidia*'\'' '\''libnvidia*'\'' steam steam-installer mesa-vulkan-drivers libgl1 libegl1 libvulkan1 2>/dev/null'
    dump_stdout_of shell snap_list 'snap list'
    dump_stdout_of shell flatpak_list 'flatpak list --columns=application,version,origin,installation 2>/dev/null'

    dump_stdout_of shell sysctl_all 'sysctl -a 2>/dev/null | LC_ALL=C sort'
    dump_stdout_of shell modprobe_config 'grep -RIn '\''^[^#].*'\'' /etc/modprobe.d /usr/lib/modprobe.d 2>/dev/null | LC_ALL=C sort'
    dump_stdout_of shell modules_load 'grep -RIn '\''^[^#].*'\'' /etc/modules /etc/modules-load.d /usr/lib/modules-load.d 2>/dev/null | LC_ALL=C sort'
    dump_stdout_of shell systemd_dropins 'find /etc/systemd /usr/lib/systemd -type f | LC_ALL=C sort'
    dump_stdout_of shell grub_default 'grep -RIn '\''^[^#].*'\'' /etc/default/grub /etc/default/grub.d 2>/dev/null | LC_ALL=C sort'
    dump_stdout_of shell limits_conf 'grep -RIn '\''^[^#].*'\'' /etc/security/limits.conf /etc/security/limits.d 2>/dev/null | LC_ALL=C sort'
    dump_stdout_of shell udev_rules 'find /etc/udev/rules.d /usr/lib/udev/rules.d -type f 2>/dev/null | LC_ALL=C sort'

    dump_stdout_of shell ldconfig 'ldconfig -p 2>/dev/null | LC_ALL=C sort'
    dump_stdout_of shell alternatives 'update-alternatives --get-selections | LC_ALL=C sort'
    dump_stdout_of shell bin_versions '
for x in gcc g++ clang ld ld.gold ld.lld make cmake python3 bash steam glxinfo vulkaninfo nvidia-smi; do
    command -v $x >/dev/null 2>&1 || continue
    echo "## $x"
    command -v $x
    $x --version 2>/dev/null | head -n 5
    echo
done
'
}

collect_graphics_stack_info() {
    dump_stdout_of cmd xrandr xrandr --verbose
    dump_stdout_of cmd loginctl loginctl session-status

    {
        printf "XDG_SESSION_TYPE=%s\n" "${XDG_SESSION_TYPE-}"
        printf "WAYLAND_DISPLAY=%s\n" "${WAYLAND_DISPLAY-}"
        printf "DISPLAY=%s\n" "${DISPLAY-}"
    } >"$output/session_env.txt" 2>&1

    dump_stdout_of shell glxinfo_brief 'glxinfo -B 2>/dev/null'
    dump_stdout_of shell vulkaninfo_summary 'vulkaninfo --summary 2>/dev/null'
    dump_stdout_of shell vulkaninfo_full 'vulkaninfo 2>/dev/null'
    dump_stdout_of shell eglinfo 'eglinfo -B 2>/dev/null'

    dump_stdout_of shell Xorg_log 'cat /var/log/Xorg.0.log'
    dump_stdout_of shell gpu_mgr_log 'cat /var/log/gpu-manager.log'
}

collect_nvidia_info() {
    dump_stdout_of cmd nvidia_smi nvidia-smi -q
    dump_stdout_of cmd nvidia_smi_l nvidia-smi -L
    dump_stdout_of cmd nvidia_smi_topo nvidia-smi topo -m
    dump_stdout_of cmd nvidia_smi_clocks nvidia-smi --query-gpu=index,name,driver_version,vbios_version,pstate,power.draw,power.limit,clocks.current.graphics,clocks.current.memory,clocks.max.graphics,clocks.max.memory,temperature.gpu,utilization.gpu,utilization.memory,pcie.link.gen.current,pcie.link.gen.max,pcie.link.width.current,pcie.link.width.max,display_active,display_mode,gpu_bus_id --format=csv,noheader

    dump_stdout_of shell nvidia_modinfo 'modinfo nvidia nvidia_drm nvidia_modeset nvidia_uvm 2>/dev/null'

    dump_stdout_of shell nvidia_params '
for m in nvidia nvidia_drm nvidia_modeset nvidia_uvm; do
    [[ -d /sys/module/$m/parameters ]] || continue
    echo "## $m"
    grep -H . /sys/module/$m/parameters/* 2>/dev/null
    echo
done
'

    dump_stdout_of shell nvidia_proc '
find /proc/driver/nvidia -maxdepth 3 -type f 2>/dev/null | LC_ALL=C sort | while read -r f; do
    echo "## $f"
    cat "$f" 2>/dev/null
    echo
done
'

    dump_stdout_of shell drm_state '
for d in /sys/class/drm/card*; do
    echo "## $d"
    find "$d" -maxdepth 2 -type f 2>/dev/null | LC_ALL=C sort | while read -r f; do
        printf "%s: " "$f"
        cat "$f" 2>/dev/null
    done
    echo
done
'

    dump_stdout_of shell nvidia_modules_and_params '
for m in $(lsmod | awk "/^nvidia/ {print \$1}"); do
    echo "## $m"
    echo

    echo "### modinfo"
    modinfo "$m" 2>/dev/null

    echo
    echo "### parameters"
    if [[ -d /sys/module/$m/parameters ]]; then
        for f in /sys/module/$m/parameters/*; do
            [[ -e $f ]] || continue
            printf "%s = " "${f##*/}"
            cat "$f" 2>/dev/null
        done | sort
    else
        echo "no parameters"
    fi

    echo
done
'
}

# main function starts 
collect_basic_system_info
collect_hardware_info
collect_boot_and_service_info
collect_package_and_config_info
collect_graphics_stack_info
collect_nvidia_info