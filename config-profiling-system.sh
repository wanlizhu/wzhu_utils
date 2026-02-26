#!/usr/bin/env bash

set -o pipefail 

# enable passwordless sudo 
if ! sudo -n true 2>/dev/null; then 
    echo "$(id -un) ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/99-$(id -un)-nopasswd >/dev/null
    sudo chmod 0440 /etc/sudoers.d/99-$(id -un)-nopasswd
    sudo visudo -cf /etc/sudoers.d/99-$(id -un)-nopasswd >/dev/null
fi

# disable firewall 
if systemctl is-active ufw >/dev/null 2>&1; then
    sudo ufw disable 
fi 

# patch ~/.bashrc
if [[ -z $(cat ~/.bashrc | grep "nvidia-profiling.sh") ]]; then 
    echo -e "\n[[ -f ~/nvidia-profiling.sh ]] && source ~/nvidia-profiling.sh" >>~/.bashrc 
fi 
if [[ ! -f ~/nvidia-profiling.sh ]]; then 
    echo '#!/bin/bash' >~/nvidia-profiling.sh
    echo "export __GL_SYNC_TO_VBLANK=0" >>~/nvidia-profiling.sh 
    echo "export vblank_mode=0" >>~/nvidia-profiling.sh 
    echo 'export PATH="$HOME/nsight_systems/bin:$PATH"' >>~/nvidia-profiling.sh 
    echo "export P4PORT=p4proxy-sc.nvidia.com:2006" >>~/nvidia-profiling.sh
    echo "export P4USER=wanliz" >>~/nvidia-profiling.sh
    echo "export P4CLIENT=wanliz_sw_windows_wsl2" >>~/nvidia-profiling.sh
    echo "export P4ROOT=$HOME/sw" >>~/nvidia-profiling.sh
    echo "export P4IGNORE=$HOME/.p4ignore" >>~/nvidia-profiling.sh
    echo "export NVM_GTLAPI_TOKEN='eyJhbGciOiJIUzI1NiJ9.eyJpZCI6IjNlMGZkYWU4LWM5YmUtNDgwOS1iMTQ3LTJiN2UxNDAwOTAwMyIsInNlY3JldCI6IndEUU1uMUdyT1RaY0Z0aHFXUThQT2RiS3lGZ0t5NUpaalU3QWFweUxGSmM9In0.Iad8z1fcSjA6P7SHIluppA_tYzOGxGv4koMyNawvERQ'" >>~/nvidia-profiling.sh 
    cat >>~/nvidia-profiling.sh <<'EOF'
zhu_list_login_sessions() {
    printf "%-6s %-5s %-8s %-6s %-6s %-7s %-4s %s\n" "SESSION" "UID" "USER" "SEAT" "TTY" "STATE" "IDLE" "TYPE"
    loginctl list-sessions --no-legend | 
    while read -r sid uid user seat tty state idle _; do
        type=$(loginctl show-session $sid -p Type --value)
        printf "%-6s %-5s %-8s %-6s %-6s %-7s %-4s %s\n" "$sid" "$uid" "$user" "$seat" "$tty" "$state" "$idle" "$type"
    done
}
zhu_get_login_session_type() {
    local active_sid
    active_sid=$(
        while read -r session; do
            seat=$(loginctl show-session $session -p Seat --value)
            state=$(loginctl show-session $session -p State --value)
            if [[ $seat == seat0 && $state == active ]]; then
                echo $session
                return 0
            fi
        done < <(loginctl list-sessions --no-legend | awk '{print $1}')
        return 1
  ) || return 1
  loginctl show-session $active_sid -p Type --value
}
zhu_install() {
    local required_pkgs=()
    local failed_pkgs=()
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
        sudo apt install -y $pkg || failed_pkgs+=("$pkg")
    done 
    if (( ${#failed_pkgs[@]} )); then
        for pkg in "${failed_pkgs[@]}"; do 
            
        done 
    fi 
}
zhu_mount() {
    local remote_dir=$1
    local local_dir=$([[ -z $2 ]] && echo /mnt/$(basename $1) || echo $2)
    sudo mkdir -p $local_dir
    sudo mount -t nfs $remote_dir $local_dir 
    findmnt -T $local_dir
}
zhu_mount_permanent() {
    local remote_dir=$1
    local local_dir=$([[ -z $2 ]] && echo /mnt/$(basename $1) || echo $2)
    local fstab_line="$remote_dir $local_dir nfs soft,intr,nofail,x-systemd.automount,x-systemd.device-timeout=10s,_netdev 0 0"
    if ! findmnt -rn -o TARGET | grep -qxF $local_dir; then
        sudo awk -v mnt=$local_dir '{
    norm=$0
    sub(/^[[:space:]]*(#[[:space:]]*)*/, "", norm)
    n=split(norm, f, /[[:space:]]+/)
    if (n >= 2 && f[2] == mnt) next
    print
  }' /etc/fstab | sudo tee /etc/fstab >/dev/null
        sudo mkdir -p $local_dir
        echo "$fstab_line" | sudo tee -a /etc/fstab >/dev/null
    fi
    sudo mount -a
    findmnt -T $local_dir
}
EOF
fi 
source ~/.bashrc  

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
if [[ ! -f /etc/apt/sources.list.d/ddebs.sources ]]; then
    echo "Types: deb
URIs: http://ddebs.ubuntu.com/
Suites: $(lsb_release -cs) $(lsb_release -cs)-updates $(lsb_release -cs)-proposed 
Components: main restricted universe multiverse
Signed-by: /usr/share/keyrings/ubuntu-dbgsym-keyring.gpg" | sudo tee /etc/apt/sources.list.d/ddebs.sources 
    sudo apt install -y ubuntu-dbgsym-keyring apt-transport-https ca-certificates apt-file 
fi 
sudo apt update && sudo apt upgrade 
zhu_install debian-goodies libc6-dbg libstdc++6-dbgsym linux-image-$(uname -r)-dbgsym build-essential cmake git ninja-build pkg-config meson clang vim mesa-utils vulkan-tools libvulkan-dev nfs-common 

# install amd gpu drivers 
if [[ $(lspci -nnk | grep -EA3 'VGA|3D|Display' | grep amdgpu) ]]; then 
    zhu_install libdrm2-dbgsym libdrm-amdgpu1-dbgsym mesa-vulkan-drivers-dbgsym libgl1-mesa-dri-dbgsym libgbm1-dbgsym linux-image-$(uname -r)-dbgsym
    dpkg -l | awk '$1=="ii"{print $2}' | sed -E 's/:(amd64|i386)$//' | grep -Ei '(amdgpu|amdvlk|radeon|radv|radeonsi|mesa|libdrm|vulkan|rocm|hip|hsa|opencl|xserver-xorg-video-amdgpu|xserver-xorg-video-radeon)' | sed -E 's/-dbgsym$//' |  zhu_install
fi 

# config wayland
if [[ $(zhu_get_login_session_type) == wayland ]]; then
    # wayland: install gamescope
    if [[ -z $(which gamescope) ]]; then 
        zhu_install libwayland-dev wayland-protocols libpipewire-0.3-dev libx11-xcb-dev libxcb1-dev libx11-dev libxdamage-dev libxcomposite-dev libxcursor-dev libxxf86vm-dev libxtst-dev libxres-dev libxmu-dev libdrm-dev libeis-dev libsystemd-dev libxkbcommon-dev libcap-dev libepoll-shim-dev libsdl2-dev libavif-dev libpixman-1-dev libseat-dev libinput-dev libxcb-composite0-dev libxcb-ewmh-dev libglm-dev libxcb-icccm4-dev libxcb-res0-dev libdisplay-info-dev libxcb-errors-dev libstb-dev libepoll-shim-dev libstd-dev 
        pushd $HOME >/dev/null  
        git clone --recursive https://github.com/ValveSoftware/gamescope.git 
        cd gamescope
        if [[ $(lsb_release -rs) == 24.04 ]]; then 
            git checkout --recurse-submodules 3.14.24
        fi 
        git submodule update --init --recursive
        meson setup build 
        ninja -C build
        sudo meson install -C build 
        popd >/dev/null 
    fi 
    # wayland: enable gnome remote desktop
    if ! sudo ss -ltnp | grep -qE ':3389\b'; then
        zhu_install gnome-remote-desktop openssl remmina remmina-plugin-rdp freerdp2-x11
        cert_dir=/var/lib/gnome-remote-desktop/.local/share/gnome-remote-desktop
        cert_key=$cert_dir/rdp-tls.key
        cert_crt=$cert_dir/rdp-tls.crt
        sudo install -d -m 0700 $cert_dir
        sudo chown -R gnome-remote-desktop:gnome-remote-desktop /var/lib/gnome-remote-desktop/.local
        if [[ ! -s $cert_key || ! -s $cert_crt ]]; then 
            sudo openssl req -x509 -newkey rsa:2048 -nodes -keyout $cert_key -out $cert_crt -days 3650 -subj "/CN=$(hostname -f)"
            sudo chmod 0600 $cert_key
            sudo chmod 0644 $cert_crt
            sudo chown gnome-remote-desktop:gnome-remote-desktop $cert_key $cert_crt
        fi 
        sudo openssl x509 -in $cert_crt -noout >/dev/null || echo "Bad certificate"
        sudo openssl pkey -in $cert_key -noout >/dev/null || echo "Bad certificate key"
        sudo grdctl --system rdp set-tls-key $cert_key
        sudo grdctl --system rdp set-tls-cert $cert_crt
        sudo grdctl --system rdp set-credentials wanliz zhujie
        sudo grdctl --system rdp enable
        sudo ufw disable || sudo ufw allow 3389/tcp 
        sudo systemctl daemon-reload
        sudo systemctl restart gnome-remote-desktop.service
        sudo grdctl --system status
        sudo ss -ltnp | grep -E ':3389\b' || {
            echo "RDP server is not listening on TCP/3389"
            sudo systemctl status gnome-remote-desktop.service --no-pager
            sudo journalctl -u gnome-remote-desktop.service -b --no-pager | tail -n 120
        }
    fi 
fi

# enable ssh server
if ! systemctl is-active ssh || !systemctl is-enabled ssh; then 
    zhu_install openssh-server 
    sudo systemctl enable ssh 
    sudo systemctl start ssh
fi 

# mount data dirs
zhu_mount_permanent linuxqa:/qa/people /mnt/linuxqa
