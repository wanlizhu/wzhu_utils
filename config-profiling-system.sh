#!/usr/bin/env bash
set -o pipefail 

INIT_APT_PKG=

while (( $# )); do
    case $1 in
        apt) INIT_APT_PKG=true ;;
        *) break ;;
    esac
    shift
 done

# enable passwordless sudo 
if [[ ! -f /etc/sudoers.d/99-$(id -un)-nopasswd ]]; then 
    echo "$(id -un) ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/99-$(id -un)-nopasswd >/dev/null
    sudo chmod 0440 /etc/sudoers.d/99-$(id -un)-nopasswd
    sudo visudo -cf /etc/sudoers.d/99-$(id -un)-nopasswd >/dev/null
fi

# disable firewall 
if [[ -z $(sudo ufw status | grep inactive) ]]; then
    sudo ufw disable 
fi 

# disable apparmor
if [[ ! -f /etc/sysctl.d/99-nvmake.conf ]]; then 
    echo "kernel.apparmor_restrict_unprivileged_unconfined = 0" | sudo tee /etc/sysctl.d/99-nvmake.conf >/dev/null 
    echo "kernel.apparmor_restrict_unprivileged_userns = 0" | sudo tee /etc/sysctl.d/99-nvmake.conf >>/dev/null # it's expected to append to the file
    sudo sysctl -w kernel.apparmor_restrict_unprivileged_unconfined=0
    sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
fi

# vscode file watcher
if [[ ! -f /etc/sysctl.d/99-vscode.conf ]]; then 
    echo "fs.inotify.max_user_watches=524288" | sudo tee /etc/sysctl.d/99-vscode.conf >/dev/null 
    sudo sysctl -w fs.inotify.max_user_watches=524288 >/dev/null 
fi

# patch ~/.bashrc
if [[ -z $(cat ~/.bashrc | grep "nvidia-profiling.sh") ]]; then
    echo "if [[ -f ~/nvidia-profiling.sh ]]; then" >>~/.bashrc 
    echo "    source ~/nvidia-profiling.sh" >>~/.bashrc 
    echo "fi" >>~/.bashrc 
fi 
echo '#!/bin/bash' >~/nvidia-profiling.sh
echo 'export PATH="/mnt/linuxqa/wanliz/$(uname -m)/bin:/mnt/linuxqa/wanliz/$(uname -m):$PATH"' >>~/nvidia-profiling.sh
echo 'export PATH="$HOME:$HOME/bin:$HOME/.local/bin:$PATH"' >>~/nvidia-profiling.sh 
echo 'export PATH="$HOME/wzhu_utils:$PATH"' >>~/nvidia-profiling.sh 
echo 'export PATH="$HOME/wzhu_utils/offscreen:$PATH"' >>~/nvidia-profiling.sh 
echo 'export PATH="$HOME/wzhu_utils/testcase:$PATH"' >>~/nvidia-profiling.sh 
echo 'export PATH="$HOME/wzhu_utils/profiling:$PATH"' >>~/nvidia-profiling.sh 
echo 'export PATH="$HOME/wzhu_utils/profiling/oncpu:$PATH"' >>~/nvidia-profiling.sh 
echo 'export PATH="$HOME/wzhu_utils/profiling/offcpu:$PATH"' >>~/nvidia-profiling.sh 
echo 'export PATH="$HOME/nsight_systems/bin:$PATH"' >>~/nvidia-profiling.sh 
echo 'export PATH="$HOME/nvidia-nomad-internal-Linux.linux/host/linux-desktop-nomad-x64:$PATH"' >>~/nvidia-profiling.sh 
echo 'export PATH="$HOME/phoronix-test-suite:$PATH"' >>~/nvidia-profiling.sh 
echo "export P4PORT=p4proxy-sc.nvidia.com:2006" >>~/nvidia-profiling.sh
echo "export P4USER=wanliz" >>~/nvidia-profiling.sh
echo "export P4CLIENT=wanliz_sw_windows_wsl2" >>~/nvidia-profiling.sh
echo "export P4ROOT=$HOME/wzhu_p4sw" >>~/nvidia-profiling.sh
echo "export P4IGNORE=$P4ROOT/.p4ignore" >>~/nvidia-profiling.sh
echo "export __GL_SYNC_TO_VBLANK=0" >>~/nvidia-profiling.sh 
echo "export vblank_mode=0" >>~/nvidia-profiling.sh 
cat >> ~/nvidia-profiling.sh <<'EOF'
if [[ -f $HOME/vulkansdk/current/setup-env.sh ]]; then 
    source $HOME/vulkansdk/current/setup-env.sh
fi 
reload() {
    source ~/.bashrc
}
reload_graphics_env() {
    export DISPLAY=:0
    export XAUTHORITY=$(tr '\0' '\n' </proc/$(pgrep -n gnome-shell)/environ | grep '^XAUTHORITY=' | awk -F'=' '{print $2}')
    export XDG_RUNTIME_DIR=/run/user/$(id -u)
    export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
    echo "DISPLAY=$DISPLAY"
    echo "XAUTHORITY=$XAUTHORITY"
    echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
    echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"

    wayland_display=$(ls /run/user/$(id -u)/wayland-[0-9] 2>/dev/null)
    if [[ ! -z $wayland_display ]]; then 
        export WAYLAND_DISPLAY=$(basename $wayland_display)
        echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
    fi 
    
    exec /usr/bin/bash 
}
sync_linuxqa_wanliz() {
    if [[ -d /mnt/linuxqa/wanliz/$(uname -m)/bin ]]; then 
        mkdir -p $HOME/bin
        echo "/mnt/linuxqa/wanliz/$(uname -m)/bin -> $HOME/"
        rsync -ah --info=progress2 /mnt/linuxqa/wanliz/$(uname -m)/bin/ $HOME/bin/ 
    fi 
    if [[ -d /mnt/linuxqa/wanliz/$(uname -m)/lib ]]; then 
        mkdir -p $HOME/lib 
        echo "/mnt/linuxqa/wanliz/$(uname -m)/lib -> $HOME/"
        rsync -ah --info=progress2 /mnt/linuxqa/wanliz/$(uname -m)/lib/ $HOME/lib/
    fi 
}
pp() { 
    pushd ~/wzhu_utils
    git add .
    git commit -m s && { 
        git pull
        git push
    } || git pull
    popd
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
mount_nfs() {
    sudo mkdir -p /mnt/$(basename $1)
    sudo mount -t nfs $1 /mnt/$(basename $1) && echo "Mounted /mnt/$(basename $1)"
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
        echo "Mounted $mnt_dir" 
        [[ -e $mnt_dir/$subpath ]] && echo "$mnt_dir/$subpath"
    }
}
system_backup() {
    UUID='0bb172fa-5d90-44ac-b135-52f6520115b1'
    if [[ -z $(sudo blkid -U $UUID) ]]; then 
        echo "UUID $UUID doesn't exist"
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
    echo "Add Nvidia portal in GUI: nvidia.gpcloudservice.com"
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

    for pkg in "${required_pkgs[@]}"; do 
        dpkg -s $pkg &>/dev/null && continue 
        sudo apt install -y $pkg 2>/dev/null 
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
screenshot() {
    output=screenshot$([[ -z $1 ]] || echo "_$1").png
    if [[ ! -z $2 ]]; then   
        mkdir -p $2
        find $2 -mindepth 1 -delete 
        output=$2/screenshot$([[ -z $1 ]] || echo "_$1").png
    fi 
    if [[ $(login_session_type_seat0) == wayland ]]; then 
        if [[ $XDG_CURRENT_DESKTOP == *GNOME* ]]; then
            [[ -z $(which gnome-screenshot) ]] && sudo apt install -y gnome-screenshot &>/dev/null 
            timeout 5 gnome-screenshot -f $output || {
                echo "Press Alt+F2, enter lg, set unsafe-mode flag to use gnome-screenshot"
            }
        else 
            [[ -z $(which grim) ]] && sudo apt install -y grim &>/dev/null 
            timeout 5 grim $output 
        fi  
    else
        [[ -z $(which magick) && -z $(which import) ]] && sudo apt install -y imagemagick
        if command -v magick > /dev/null; then
            timeout 5 magick import -window root $output 
        elif command -v import > /dev/null; then
            timeout 5 import -window root $output 
        fi
    fi 
}
EOF
source ~/nvidia-profiling.sh

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
fi 

# set kernel params
if [[ ! -f /etc/modprobe.d/nvidia-profiling.conf ]]; then
    echo 'options nvidia NVreg_RegistryDwords="RmProfilerFeature=0x1" NVreg_RestrictProfilingToAdminUsers=0' | sudo tee /etc/modprobe.d/nvidia-profiling.conf >/dev/null
    echo 'options nvidia-drm modeset=1' | sudo tee -a /etc/modprobe.d/nvidia-profiling.conf >/dev/null
    sudo update-initramfs -u -k all 
fi 
if [[ ! -f /etc/sysctl.d/99-profiling.conf ]]; then
    echo 'kernel.perf_event_paranoid = 0' | sudo tee /etc/sysctl.d/99-profiling.conf >/dev/null
    echo 'kernel.kptr_restrict = 0' | sudo tee -a /etc/sysctl.d/99-profiling.conf >/dev/null
    sudo sysctl -p /etc/sysctl.d/99-profiling.conf
fi 

# install required packages
if [[ $INIT_APT_PKG == true && ! -z $(which find_or_install) ]]; then 
    sudo tee /etc/apt/apt.conf.d/99-phased-updates >/dev/null <<'EOF'
APT::Get::Always-Include-Phased-Updates "true";
EOF
    if [[ ! -f /etc/apt/sources.list.d/ddebs.sources ]]; then
        echo "Types: deb
URIs: http://ddebs.ubuntu.com/
Suites: $(lsb_release -cs) $(lsb_release -cs)-updates $(lsb_release -cs)-proposed 
Components: main restricted universe multiverse
Signed-by: /usr/share/keyrings/ubuntu-dbgsym-keyring.gpg" | sudo tee /etc/apt/sources.list.d/ddebs.sources 
        find_or_install ubuntu-dbgsym-keyring apt-transport-https ca-certificates apt-file 
    fi 
    if [[ ! -z $(apt list '?upgradable !?phasing' 2>/dev/null) ]]; then 
        sudo apt update  
        sudo apt upgrade -y 
        sudo apt autoremove -y  
    fi  
    find_or_install debian-goodies libc6-dbg libstdc++6-dbgsym \
        build-essential cmake git ninja-build pkg-config meson clang \
        vim net-tools mesa-utils vulkan-tools libvulkan-dev screen \
        btop htop nvtop sysprof pciutils nfs-common openssh-server \
        libxcb-icccm4 libxcb-cursor0 libxcb-image0 libxcb-keysyms1 \
        libxcb-render-util0 libxcb-xkb1 libxkbcommon-x11-0 bsdextrautils \
        python3-pip python3-pandas cpufrequtils stress-ng glmark2 cifs-utils \
        php-cli php-xml timeshift libx11-dev libgl-dev

    find . -maxdepth 1 -type f -name '*_dbgsym_packages.txt' -print0 |
    while IFS= read -r -d '' file; do
        while IFS= read -r pkg; do
            find_or_install $pkg 
        done < "$file"
    done

    if [[ ! -z $(apt list --installed 'libreoffice*' 2>/dev/null | grep libreoffice) ]]; then 
        read -p "Press [Enter] to uninstall libre office: "
        sudo apt purge -y libreoffice*
        sudo apt autoremove -y 
    fi 

    # install amd gpu drivers 
    if [[ $(lspci -nnk | grep -EA3 'VGA|3D|Display' | grep amdgpu) && ! -z $(which find_or_install) ]]; then 
        find_or_install libdrm2-dbgsym libdrm-amdgpu1-dbgsym mesa-vulkan-drivers-dbgsym libgl1-mesa-dri-dbgsym libgbm1-dbgsym linux-image-$(uname -r)-dbgsym
        dpkg -l | awk '$1=="ii"{print $2}' | sed -E 's/:(amd64|i386)$//' | grep -Ei '(amdgpu|amdvlk|radeon|radv|radeonsi|mesa|libdrm|vulkan|rocm|hip|hsa|opencl|xserver-xorg-video-amdgpu|xserver-xorg-video-radeon)' | sed -E 's/-dbgsym$//' |  find_or_install
    fi 
fi 

# config git env 
git config --global user.email >/dev/null 2>&1 || git config --global user.email zhu.wanli@icloud.com
git config --global user.name >/dev/null 2>&1 || git config --global user.name "Wanli Zhu"
git config --global pull.rebase >/dev/null 2>&1 || git config --global pull.rebase false

# enable ssh server
if ! systemctl is-active ssh &>/dev/null || ! systemctl is-enabled ssh &>/dev/null; then 
    find_or_install openssh-server
    sudo systemctl enable ssh 
    sudo systemctl start ssh
fi 

# mount data dirs
if [[ -r /proc/sys/kernel/osrelease ]] && grep -qi microsoft /proc/sys/kernel/osrelease; then
    echo "WSL doesn't support NFS mounting"
else 
    if ! ping -c 1 -W 1 linuxqa >/dev/null 2>&1; then
        read -p "Reconnect to nvidia vpn? [Y/n]: " recon
        [[ -z $recon || $recon == y ]] && nvidia-vpn.sh
    fi
    if ping -c 1 -W 1 linuxqa >/dev/null 2>&1; then
        [[ ! -d /mnt/linuxqa/wanliz  ]] && sudo mkdir -p /mnt/linuxqa && sudo mount -t nfs linuxqa:/qa/people /mnt/linuxqa && echo "Mounted /mnt/linuxqa"
        [[ ! -d /mnt/builds/release  ]] && sudo mkdir -p /mnt/builds  && sudo mount -t nfs linuxqa:/qa/builds /mnt/builds  && echo "Mounted /mnt/builds"
        [[ ! -d /mnt/data/pynv_files ]] && sudo mkdir -p /mnt/data    && sudo mount -t nfs linuxqa:/qa/data   /mnt/data    && echo "Mounted /mnt/data"
    else
        echo "NOT inside nvidia domain, skip NFS mounting"
    fi 
fi 

if [[ ! -z $(which collect-system-info.sh) ]]; then 
    collect-system-info.sh brief 
fi 

exec /usr/bin/bash 