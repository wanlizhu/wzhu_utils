#!/usr/bin/env bash

set -o pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $0 DIR_A DIR_B [REPORT_DIR]"
    exit 1
fi

system_info_a=$1
system_info_b=$2
output_dir=${3:-$PWD/system_info_diff.d}
summary=$output_dir/summary.txt

rm -rf "$output_dir"
mkdir -p "$output_dir"/diffs/fixed
mkdir -p "$output_dir"/diffs/unknown

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fixed_missing_in_a=$output_dir/fixed_missing_in_a.txt
fixed_missing_in_b=$output_dir/fixed_missing_in_b.txt
fixed_same=$output_dir/fixed_same.txt
fixed_diff=$output_dir/fixed_diff.txt

unknown_only_in_a=$output_dir/unknown_only_in_a.txt
unknown_only_in_b=$output_dir/unknown_only_in_b.txt
unknown_same=$output_dir/unknown_same.txt
unknown_diff=$output_dir/unknown_diff.txt

: >"$summary"
: >"$fixed_missing_in_a"
: >"$fixed_missing_in_b"
: >"$fixed_same"
: >"$fixed_diff"
: >"$unknown_only_in_a"
: >"$unknown_only_in_b"
: >"$unknown_same"
: >"$unknown_diff"

fixed_files=(
    quick_summary.txt
    session_env.txt
    env.txt
    os_release.txt
    boot_config.txt
    cmdline.txt
    cpuinfo.txt
    meminfo.txt
    interrupts.txt
    iomem.txt
    modules.txt
    fstab.txt

    lscpu.txt
    lsblk.txt
    blkid.txt
    df.txt
    free.txt
    swapon.txt
    mount.txt
    findmnt.txt
    timedatectl.txt
    localectl.txt
    systemd_analyze.txt
    bootctl.txt
    efibootmgr.txt

    dmidecode.txt
    bios_fw.txt
    cpu_microcode.txt
    cpu_freq_policy.txt
    power_state.txt

    lspci.txt
    lsusb.txt
    sensors.txt
    gpu_pci_detail.txt

    dmesg.txt
    journal_boot.txt
    failed_units.txt
    units.txt
    unit_files.txt

    apt_installed.txt
    apt_manual.txt
    apt_policy_nvidia.txt
    snap_list.txt
    flatpak_list.txt
    sysctl_all.txt
    modprobe_config.txt
    modules_load.txt
    systemd_dropins.txt
    grub_default.txt
    limits_conf.txt
    udev_rules.txt
    ldconfig.txt
    alternatives.txt
    bin_versions.txt

    xrandr.txt
    loginctl.txt
    glxinfo_brief.txt
    vulkaninfo_summary.txt
    vulkaninfo_full.txt
    eglinfo.txt
    drm_connectors.txt
    vulkan_icd_layers.txt
    Xorg_log.txt
    gpu_mgr_log.txt

    nvidia_smi.txt
    nvidia_smi_l.txt
    nvidia_smi_topo.txt
    nvidia_smi_clocks.txt
    nvidia_modinfo.txt
    nvidia_params.txt
    nvidia_proc.txt
    drm_state.txt
    nvidia_modules_and_params.txt
)

cd "$tmpdir" || exit 1

find "$system_info_a" -type f -printf '%P\n' | LC_ALL=C sort >a_files.txt
find "$system_info_b" -type f -printf '%P\n' | LC_ALL=C sort >b_files.txt

printf '%s\n' "${fixed_files[@]}" | LC_ALL=C sort -u >fixed_files.txt

comm -23 a_files.txt fixed_files.txt >unknown_a.txt
comm -23 b_files.txt fixed_files.txt >unknown_b.txt

compare_one_file() {
    local rel=$1
    local category=$2
    local out_list=$3

    local norm_a=$tmpdir/a.norm
    local norm_b=$tmpdir/b.norm
    local safe_name

    sed '1{/^>> /d;}' "$system_info_a/$rel" >"$norm_a" 2>/dev/null
    sed '1{/^>> /d;}' "$system_info_b/$rel" >"$norm_b" 2>/dev/null

    if cmp -s "$norm_a" "$norm_b"; then
        return 0
    fi

    echo "$rel" >>"$out_list"
    safe_name=$(printf '%s\n' "$rel" | sed 's#^./##; s#/#__#g')
    diff -u "$norm_a" "$norm_b" >"$output_dir/diffs/$category/$safe_name.diff" 2>/dev/null || true
    return 1
}

while IFS= read -r rel; do
    [[ -n $rel ]] || continue

    has_a=0
    has_b=0
    [[ -f $system_info_a/$rel ]] && has_a=1
    [[ -f $system_info_b/$rel ]] && has_b=1

    if [[ $has_a -eq 0 && $has_b -eq 1 ]]; then
        echo "$rel" >>"$fixed_missing_in_a"
        continue
    fi

    if [[ $has_a -eq 1 && $has_b -eq 0 ]]; then
        echo "$rel" >>"$fixed_missing_in_b"
        continue
    fi

    if compare_one_file "$rel" fixed "$fixed_diff"; then
        echo "$rel" >>"$fixed_same"
    fi
done <fixed_files.txt

cat unknown_a.txt unknown_b.txt | LC_ALL=C sort -u >unknown_union.txt

while IFS= read -r rel; do
    [[ -n $rel ]] || continue

    has_a=0
    has_b=0
    [[ -f $system_info_a/$rel ]] && has_a=1
    [[ -f $system_info_b/$rel ]] && has_b=1

    if [[ $has_a -eq 1 && $has_b -eq 0 ]]; then
        echo "$rel" >>"$unknown_only_in_a"
        continue
    fi

    if [[ $has_a -eq 0 && $has_b -eq 1 ]]; then
        echo "$rel" >>"$unknown_only_in_b"
        continue
    fi

    if compare_one_file "$rel" unknown "$unknown_diff"; then
        echo "$rel" >>"$unknown_same"
    fi
done <unknown_union.txt

{
    echo "A: $system_info_a"
    echo "B: $system_info_b"
    echo
    echo "=== fixed file list summary ==="
    echo "fixed files configured: $(wc -l < fixed_files.txt)"
    echo "fixed missing in A: $(wc -l < "$fixed_missing_in_a")"
    echo "fixed missing in B: $(wc -l < "$fixed_missing_in_b")"
    echo "fixed same: $(wc -l < "$fixed_same")"
    echo "fixed different: $(wc -l < "$fixed_diff")"
    echo
    echo "=== unknown file summary ==="
    echo "unknown only in A: $(wc -l < "$unknown_only_in_a")"
    echo "unknown only in B: $(wc -l < "$unknown_only_in_b")"
    echo "unknown same: $(wc -l < "$unknown_same")"
    echo "unknown different: $(wc -l < "$unknown_diff")"
    echo
    echo "=== fixed files missing in A ==="
    sed 's/^/    /' "$fixed_missing_in_a"
    echo
    echo "=== fixed files missing in B ==="
    sed 's/^/    /' "$fixed_missing_in_b"
    echo
    echo "=== fixed files with meaningful differences ==="
    sed 's/^/    /' "$fixed_diff"
    echo
    echo "=== unknown files only in A ==="
    sed 's/^/    /' "$unknown_only_in_a"
    echo
    echo "=== unknown files only in B ==="
    sed 's/^/    /' "$unknown_only_in_b"
    echo
    echo "=== unknown files with meaningful differences ==="
    sed 's/^/    /' "$unknown_diff"
} >"$summary"

echo "Full report written to $output_dir"
echo 
cat "$summary"