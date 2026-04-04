#!/usr/bin/env bash
set -o pipefail 

# Extend ~/.bashrc
if [[ -z $(cat ~/.bashrc | grep ".bashrc_extended") ]]; then
    echo "if [[ -f ~/.bashrc_extended ]]; then" >>~/.bashrc 
    echo "    source ~/.bashrc_extended" >>~/.bashrc 
    echo "fi" >>~/.bashrc 
fi 
echo '#!/bin/bash' >~/.bashrc_extended
echo 'export PATH="/mnt/linuxqa/wanliz/$(uname -m)/bin:/mnt/linuxqa/wanliz/$(uname -m):$PATH"' >>~/.bashrc_extended
echo 'export PATH="$HOME:$HOME/bin:$HOME/.local/bin:$PATH"' >>~/.bashrc_extended 
echo 'export PATH="$HOME/wzhu_utils:$PATH"' >>~/.bashrc_extended 
echo 'export PATH="$HOME/wzhu_utils/offscreen:$PATH"' >>~/.bashrc_extended 
echo 'export PATH="$HOME/wzhu_utils/testcases:$PATH"' >>~/.bashrc_extended 
echo 'export PATH="$HOME/wzhu_utils/profiling:$PATH"' >>~/.bashrc_extended 
echo 'export PATH="$HOME/wzhu_utils/profiling/utils:$PATH"' >>~/.bashrc_extended 
echo 'export PATH="$HOME/wzhu_utils/profiling/oncpu:$PATH"' >>~/.bashrc_extended 
echo 'export PATH="$HOME/wzhu_utils/profiling/offcpu:$PATH"' >>~/.bashrc_extended 
echo 'export PATH="$HOME/wzhu_utils/profiling/gpu:$PATH"' >>~/.bashrc_extended 
echo 'export PATH="$HOME/nsight_systems/bin:$PATH"' >>~/.bashrc_extended 
echo 'export PATH="$HOME/nvidia-nomad-internal-Linux.linux/host/linux-desktop-nomad-x64:$PATH"' >>~/.bashrc_extended 
echo 'export PATH="$HOME/phoronix-test-suite:$PATH"' >>~/.bashrc_extended 
echo "export P4PORT=p4proxy-sc.nvidia.com:2006" >>~/.bashrc_extended
echo "export P4USER=wanliz" >>~/.bashrc_extended
echo "export P4CLIENT=wanliz_sw_windows_wsl2" >>~/.bashrc_extended
echo "export P4ROOT=$HOME/wzhu_p4sw" >>~/.bashrc_extended
echo "export P4IGNORE=$P4ROOT/.p4ignore" >>~/.bashrc_extended
echo "export __GL_SYNC_TO_VBLANK=0" >>~/.bashrc_extended 
echo "export vblank_mode=0" >>~/.bashrc_extended 
echo "alias ll='ls -alFh'" >>~/.bashrc_extended 
cat >> ~/.bashrc_extended <<'EOF'
if [[ -f $HOME/VulkanSDK/current/setup-env.sh ]]; then 
    source $HOME/VulkanSDK/current/setup-env.sh
fi 
pp() { 
    pushd ~/wzhu_utils
    git add .
    git commit -m s && { 
        git pull
        git push
    } || git pull
    popd
}
echo_in_red() {
    printf '\e[91m%s\e[0m\n' "$*"
}
echo_in_green() {
    printf '\e[92m%s\e[0m\n' "$*"
}
echo_in_blue() {
    printf '\e[94m%s\e[0m\n' "$*"
}
echo_in_yellow() {
    printf '\e[93m%s\e[0m\n' "$*"
}
echo_in_cyan() {
    printf '\e[96m%s\e[0m\n' "$*"
}
echo_in_magenta() {
    printf '\e[95m%s\e[0m\n' "$*"
}
reset_gnome_theme() {
    gsettings reset-recursively org.gnome.desktop.interface
    gsettings reset-recursively org.gnome.desktop.sound 
    gsettings reset-recursively org.gnome.desktop.wm.preferences 
}
sync_linuxqa_wanliz() {
    if [[ -d /mnt/linuxqa/wanliz/$(uname -m)/bin ]]; then 
        mkdir -p $HOME/bin
        echo_in_cyan "/mnt/linuxqa/wanliz/$(uname -m)/bin -> $HOME/"
        rsync -ah --info=progress2 /mnt/linuxqa/wanliz/$(uname -m)/bin/ $HOME/bin/ 
    fi 
    if [[ -d /mnt/linuxqa/wanliz/$(uname -m)/lib ]]; then 
        mkdir -p $HOME/lib 
        echo_in_cyan "/mnt/linuxqa/wanliz/$(uname -m)/lib -> $HOME/"
        rsync -ah --info=progress2 /mnt/linuxqa/wanliz/$(uname -m)/lib/ $HOME/lib/
    fi 
}
nvidia_smi_max_clocks() {
    if [[ "$1" == reset ]]; then 
        sudo nvidia-smi --reset-gpu-clocks
        sudo nvidia-smi --reset-memory-clocks
    else 
        max_gfx_clock=$(nvidia-smi -q -d SUPPORTED_CLOCKS | grep -m1 "Graphics" | grep -oE '[0-9]+' | tail -1)
        max_mem_clock=$(nvidia-smi -q -d SUPPORTED_CLOCKS | grep -m1 "Memory" | grep -oE '[0-9]+' | tail -1)
        if (( max_gfx_clock > 1000 && max_mem_clock > 1000 )); then 
            sudo nvidia-smi -pm 1
            sudo nvidia-smi -lgc $max_gfx_clock
            sudo nvidia-smi -lmc $max_mem_clock
        fi 
    fi 
}
print_nvparams() {
    find /etc/modprobe.d -type f -name '*.conf' -print0 |
    xargs -0 awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*options[[:space:]]+nvidia([_-].*)?[[:space:]]+/ {
            print
        }
    '
}
mount_linuxqa() {
    if [[ -r /proc/sys/kernel/osrelease ]] && grep -qi microsoft /proc/sys/kernel/osrelease; then
        echo_in_red "WSL does not support NFS mounting"
    else 
        if ping -c 1 -W 1 linuxqa >/dev/null 2>&1; then
            [[ ! -d /mnt/linuxqa/wanliz  ]] && sudo mkdir -p /mnt/linuxqa && sudo mount -t nfs linuxqa:/qa/people /mnt/linuxqa && echo_in_green "Mounted /mnt/linuxqa"
            [[ ! -d /mnt/builds/release  ]] && sudo mkdir -p /mnt/builds  && sudo mount -t nfs linuxqa:/qa/builds /mnt/builds  && echo_in_green "Mounted /mnt/builds"
            [[ ! -d /mnt/data/pynv_files ]] && sudo mkdir -p /mnt/data    && sudo mount -t nfs linuxqa:/qa/data   /mnt/data    && echo_in_green "Mounted /mnt/data"
        else
            echo_in_yellow "NOT inside nvidia domain, skip linuxqa mounting"
        fi 
    fi 
}
mount_nfs() {
    sudo mkdir -p /mnt/$(basename $1)
    sudo mount -t nfs $1 /mnt/$(basename $1) && echo_in_green "Mounted /mnt/$(basename $1)"
}
mount_cifs() {
    if [[ "$1" == \\\\* ]]; then 
        uncpath="$1"
    else
        read -r -p "Windows UNC Path: " uncpath
    fi 
    unixpath="${uncpath//\\//}"
    share_root=//$(cut -d/ -f3-4 <<< "$unixpath")
    subpath=$(cut -d/ -f5- <<< "$unixpath")
    mnt_dir=${share_root/#\/\//\/mnt\/}
    sudo mkdir -p $mnt_dir
    sudo mount -t cifs $share_root $mnt_dir -o username=wanliz,vers=3.0 && {
        echo_in_green "Mounted $mnt_dir" 
        [[ -e $mnt_dir/$subpath ]] && echo "$mnt_dir/$subpath"
    }
}
system_backup() {
    UUID='0bb172fa-5d90-44ac-b135-52f6520115b1'
    if [[ -z $(sudo blkid -U $UUID) ]]; then 
        echo_in_red "UUID $UUID doesn't exist"
        return 1
    fi 
    sudo blkid -U $UUID
    sudo timeshift --create --snapshot-device $UUID --comments "Created by $USER at $(date)" 
}
connect_nvidia_vpn() {
    if [[ -z $(which globalprotect) ]]; then 
        pushd /tmp 
        wget https://d2hvyxt0t758wb.cloudfront.net/gp_install_files/gp_install.sh
        chmod +x ./gp_install.sh 
        ./gp_install.sh 
        popd 
    fi 
    echo "Note: Nvidia portal in GUI: nvidia.gpcloudservice.com"
    read -p "Press [Enter] to connect now: "
    globalprotect connect --portal nvidia.gpcloudservice.com || {
        sudo systemctl restart gpd 
        globalprotect connect --portal nvidia.gpcloudservice.com 
    }
}
find_or_install() {
    local required_pkgs=()
    if (( $# )); then
        required_pkgs=("$@")
    else # read from stdin
        while IFS= read -r pkg; do
            [[ -z $pkg ]] && continue
            required_pkgs+=("$pkg")
        done
    fi 

    local to_install=0
    for pkg in "${required_pkgs[@]}"; do
        dpkg -s "$pkg" &>/dev/null || ((to_install++))
    done

    local index=0
    local succeeded_pkgs=()
    local failed_pkgs=()
    for pkg in "${required_pkgs[@]}"; do
        dpkg -s "$pkg" &>/dev/null && continue
        ((index++))
        echo_in_cyan "[$index/$to_install] Installing $pkg ..."
        sudo apt install -y "$pkg" && succeeded_pkgs+=("$pkg") || failed_pkgs+=("$pkg")
    done

    for pkg in "${succeeded_pkgs[@]}"; do
        echo_in_green "Installed $pkg"
    done 

    for pkg in "${failed_pkgs[@]}"; do
        echo_in_red "Failed to install $pkg"
    done 
}
list_login_session() {
    printf "%-6s %-5s %-8s %-6s %-6s %-7s %-4s %s\n" "SESSION" "UID" "USER" "SEAT" "TTY" "STATE" "IDLE" "TYPE"
    loginctl list-sessions --no-legend | 
    while read -r sid uid user seat tty state idle _; do
        type=$(loginctl show-session $sid -p Type --value)
        printf "%-6s %-5s %-8s %-6s %-6s %-7s %-4s %s\n" "$sid" "$uid" "$user" "$seat" "$tty" "$state" "$idle" "$type"
    done
}
login_session_type_seat0() {
    list_login_session | grep seat0 | awk '{print $8}'
}
install_certificate() {
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    install -m 600 /dev/null ~/.ssh/id_ed25519
    install -m 644 /dev/null ~/.ssh/id_ed25519.pub
    printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACB8e4c/PmyYwYqGt0Zb5mom/KTEndF05kcF8Gsa094RSwAAAJhfAHP9XwBz
/QAAAAtzc2gtZWQyNTUxOQAAACB8e4c/PmyYwYqGt0Zb5mom/KTEndF05kcF8Gsa094RSw
AAAECa55qWiuh60rKkJLljELR5X1FhzceY/beegVBrDPv6yXx7hz8+bJjBioa3Rlvmaib8
pMSd0XTmRwXwaxrT3hFLAAAAE3dhbmxpekBFbnpvLU1hY0Jvb2sBAg==
-----END OPENSSH PRIVATE KEY-----' > ~/.ssh/id_ed25519
    printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHx7hz8+bJjBioa3Rlvmaib8pMSd0XTmRwXwaxrT3hFL' > ~/.ssh/id_ed25519.pub
}
EOF
source ~/.bashrc_extended

# Enable passwordless sudo 
if [[ ! -f /etc/sudoers.d/99-$(id -un)-nopasswd ]]; then 
    echo "$(id -un) ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/99-$(id -un)-nopasswd >/dev/null
    sudo chmod 0440 /etc/sudoers.d/99-$(id -un)-nopasswd
    sudo visudo -cf /etc/sudoers.d/99-$(id -un)-nopasswd >/dev/null
fi

# Write out ssh config 
if [[ ! -e ~/.ssh/config ]]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    printf '%s\n' \
        'Host *' \
        '    UserKnownHostsFile /dev/null' \
        '    GlobalKnownHostsFile /dev/null' \
        '    StrictHostKeyChecking no' \
        > ~/.ssh/config
    chmod 600 ~/.ssh/config
fi

# Update grub cmdline 
sudo cp /etc/default/grub /tmp/grub
sudo sed -i \
    -e "s/^\(GRUB_CMDLINE_LINUX_DEFAULT=\)'\(.*\)'$/\1\"\2\"/" \
    -e "s/^\(GRUB_CMDLINE_LINUX=\)'\(.*\)'$/\1\"\2\"/" \
    /etc/default/grub
sudo sed -i \
    -e '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/ nomodeset / /g' \
    -e '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/"nomodeset /"/' \
    -e '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/ nomodeset"/"/' \
    -e '/^GRUB_CMDLINE_LINUX_DEFAULT=/ { /nvidia_drm\.modeset=1/! s/"$/ nvidia_drm.modeset=1"/; }' \
    -e '/^GRUB_CMDLINE_LINUX=/ { /apparmor=0/! s/"$/ apparmor=0"/; }' \
    /etc/default/grub
if ! cmp -s /tmp/grub /etc/default/grub; then
    sudo update-grub
fi

# Disable firewall 
if [[ -z $(sudo ufw status | grep inactive) ]]; then
    sudo ufw disable 
fi 

# In case appamror is not disabled
if [[ ! -f /etc/sysctl.d/99-nvmake.conf ]]; then 
    echo "kernel.apparmor_restrict_unprivileged_unconfined = 0" | sudo tee /etc/sysctl.d/99-nvmake.conf >/dev/null 
    echo "kernel.apparmor_restrict_unprivileged_userns = 0" | sudo tee -a /etc/sysctl.d/99-nvmake.conf >/dev/null # it's expected to append to the file
    sudo sysctl -w kernel.apparmor_restrict_unprivileged_unconfined=0
    sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
fi

# For vscode file watcher
if [[ ! -f /etc/sysctl.d/99-vscode.conf ]]; then 
    echo "fs.inotify.max_user_watches=524288" | sudo tee /etc/sysctl.d/99-vscode.conf >/dev/null 
    sudo sysctl -w fs.inotify.max_user_watches=524288 >/dev/null 
fi

# For p4ignore file
if [[ -d $P4ROOT && ! -f $P4ROOT/.p4ignore ]]; then 
    echo "_out/" >  $P4ROOT/.p4ignore
    echo ".git/" >> $P4ROOT/.p4ignore
    echo ".vscode/" >> $P4ROOT/.p4ignore
    echo ".cursor/" >> $P4ROOT/.p4ignore
    echo ".cache/" >> $P4ROOT/.p4ignore
    echo "__pycache__/" >> $P4ROOT/.p4ignore
    echo "/.p4ignore" >> $P4ROOT/.p4ignore
    echo "/compile_commands.json" >> $P4ROOT/.p4ignore
    echo "/.clangd" >> $P4ROOT/.p4ignore
    echo_in_green "Generated $P4ROOT/.p4ignore"
fi 

# Set up kernel params for profiling 
if [[ ! -f /etc/modprobe.d/nvidia-profiling.conf ]]; then
    echo 'options nvidia NVreg_RegistryDwords="RmProfilerFeature=0x1" NVreg_RestrictProfilingToAdminUsers=0' | sudo tee /etc/modprobe.d/nvidia-profiling.conf >/dev/null
    echo 'options nvidia-drm modeset=1' | sudo tee -a /etc/modprobe.d/nvidia-profiling.conf >/dev/null
    sudo update-initramfs -u -k all 
    echo_in_green "Generated /etc/modprobe.d/nvidia-profiling.conf"
fi 
if [[ ! -f /etc/sysctl.d/99-profiling.conf ]]; then
    echo 'kernel.perf_event_paranoid = 0' | sudo tee /etc/sysctl.d/99-profiling.conf >/dev/null
    echo 'kernel.kptr_restrict = 0' | sudo tee -a /etc/sysctl.d/99-profiling.conf >/dev/null
    sudo sysctl -p /etc/sysctl.d/99-profiling.conf
    echo_in_green "Generated /etc/sysctl.d/99-profiling.conf"
fi 

# Install required packages
if ! dpkg --print-foreign-architectures | grep -qxF i386; then
    sudo dpkg --add-architecture i386
    echo_in_green "Added architecture i386"
fi 
if [[ ! -e /etc/apt/apt.conf.d/99-phased-updates ]]; then 
    echo 'APT::Get::Always-Include-Phased-Updates "true";' | sudo tee /etc/apt/apt.conf.d/99-phased-updates
    echo_in_green "Generated /etc/apt/apt.conf.d/99-phased-updates" 
fi 
if [[ ! -f /etc/apt/sources.list.d/ddebs.sources ]]; then
    (   echo "Types: deb" 
        echo "URIs: http://ddebs.ubuntu.com/"
        echo "Suites: $(lsb_release -cs) $(lsb_release -cs)-updates $(lsb_release -cs)-proposed"
        echo "Components: main restricted universe multiverse"
        echo "Signed-By: /usr/share/keyrings/ubuntu-dbgsym-keyring.gpg"
    ) | sudo tee /etc/apt/sources.list.d/ddebs.sources
    sudo apt install -y ubuntu-dbgsym-keyring apt-transport-https ca-certificates apt-file 
fi 
if [[ $1 == noupdate || $1 == nopkg ]]; then 
    echo_in_cyan "Forced to skip updating apt packages"
else 
    if [[ ! -z $(apt list '?upgradable !?phasing' 2>/dev/null) ]]; then 
        sudo apt update  
        sudo apt upgrade -y 
        sudo apt autoremove -y  
        echo_in_green "Finished updating apt packages"
    fi  
fi 
if [[ $1 == nopkg ]]; then 
    echo_in_cyan "Forced to skip installing apt packages"
else 
    find_or_install debian-goodies libc6-dbg libstdc++6-dbgsym \
        build-essential cmake git ninja-build pkg-config meson clang \
        vim net-tools mesa-utils vulkan-tools libvulkan-dev screen \
        btop htop nvtop sysprof pciutils nfs-common openssh-server \
        libxcb-icccm4 libxcb-cursor0 libxcb-image0 libxcb-keysyms1 \
        libxcb-render-util0 libxcb-xkb1 libxkbcommon-x11-0 bsdextrautils \
        python3-pip python3-pandas cpufrequtils stress-ng glmark2 cifs-utils \
        php-cli php-xml timeshift libx11-dev libgl-dev steam elfutils \
        linux-tools-$(uname -r) linux-cloud-tools-$(uname -r) \
        linux-tools-generic linux-cloud-tools-generic \
        drm-info 
fi

# Install flame graph tools
if [[ -z $(which flamegraph.pl) ]]; then 
    git clone https://github.com/brendangregg/FlameGraph.git /tmp/fg 
    sudo cp -f /tmp/fg/*.pl /usr/local/bin/
    echo_in_green "Installed flamegraph.pl into /usr/local/bin/"
fi 

# Config git env 
git config --global user.email >/dev/null 2>&1 || git config --global user.email zhu.wanli@icloud.com
git config --global user.name >/dev/null 2>&1 || git config --global user.name "Wanli Zhu"
git config --global pull.rebase >/dev/null 2>&1 || git config --global pull.rebase false

# Enable ssh server
if ! systemctl is-active ssh &>/dev/null || ! systemctl is-enabled ssh &>/dev/null; then 
    find_or_install openssh-server
    sudo systemctl enable ssh 
    sudo systemctl start ssh
    echo_in_green "Enabled ssh service"
fi 

mount_linuxqa
collect-system-info.sh 
exec /usr/bin/bash 