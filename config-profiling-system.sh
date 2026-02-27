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
if [[ -f ~/nvidia-profiling.sh ]]; then 
    sudo mv -f ~/nvidia-profiling.sh /tmp/nvidia-profiling.sh.old 
fi 
echo '#!/bin/bash' >~/nvidia-profiling.sh
echo "export __GL_SYNC_TO_VBLANK=0" >>~/nvidia-profiling.sh 
echo "export vblank_mode=0" >>~/nvidia-profiling.sh 
echo 'export PATH="$HOME/wzhu_utils:$HOME/wzhu_utils/profiling:$HOME/nsight_systems/bin:$PATH"' >>~/nvidia-profiling.sh 
echo "export P4PORT=p4proxy-sc.nvidia.com:2006" >>~/nvidia-profiling.sh
echo "export P4USER=wanliz" >>~/nvidia-profiling.sh
echo "export P4CLIENT=wanliz_sw_windows_wsl2" >>~/nvidia-profiling.sh
echo "export P4ROOT=$HOME/sw" >>~/nvidia-profiling.sh
echo "export P4IGNORE=$HOME/.p4ignore" >>~/nvidia-profiling.sh
echo "export NVM_GTLAPI_TOKEN='eyJhbGciOiJIUzI1NiJ9.eyJpZCI6IjNlMGZkYWU4LWM5YmUtNDgwOS1iMTQ3LTJiN2UxNDAwOTAwMyIsInNlY3JldCI6IndEUU1uMUdyT1RaY0Z0aHFXUThQT2RiS3lGZ0t5NUpaalU3QWFweUxGSmM9In0.Iad8z1fcSjA6P7SHIluppA_tYzOGxGv4koMyNawvERQ'" >>~/nvidia-profiling.sh 
cat >>~/nvidia-profiling.sh <<'EOF'
zhu_mount() {
    local remote_dir=$1
    local local_dir=$([[ -z $2 ]] && echo /mnt/$(basename $1) || echo $2)
    if ! findmnt -rn -T $local_dir >/dev/null; then
        sudo mkdir -p $local_dir
        sudo mount -t nfs $remote_dir $local_dir 
        findmnt -T $local_dir
    fi 
}
zhu_steam_pstree() {
    pstree -aspT $(pidof steam)
}
EOF
source ~/nvidia-profiling.sh

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
install-pkg.sh debian-goodies libc6-dbg libstdc++6-dbgsym linux-image-$(uname -r)-dbgsym build-essential cmake git ninja-build pkg-config meson clang vim mesa-utils vulkan-tools libvulkan-dev nfs-common btop htop sysprof 

# install amd gpu drivers 
if [[ $(lspci -nnk | grep -EA3 'VGA|3D|Display' | grep amdgpu) ]]; then 
    install-pkg.sh libdrm2-dbgsym libdrm-amdgpu1-dbgsym mesa-vulkan-drivers-dbgsym libgl1-mesa-dri-dbgsym libgbm1-dbgsym linux-image-$(uname -r)-dbgsym
    dpkg -l | awk '$1=="ii"{print $2}' | sed -E 's/:(amd64|i386)$//' | grep -Ei '(amdgpu|amdvlk|radeon|radv|radeonsi|mesa|libdrm|vulkan|rocm|hip|hsa|opencl|xserver-xorg-video-amdgpu|xserver-xorg-video-radeon)' | sed -E 's/-dbgsym$//' |  install-pkg.sh
fi 

# config wayland
if [[ $(list-login-session.sh -t0) == wayland ]]; then
    # wayland: enable gnome remote desktop
    if ! sudo ss -ltnp | grep -qE ':3389\b'; then
        install-pkg.sh gnome-remote-desktop openssl remmina remmina-plugin-rdp freerdp2-x11
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
if ! systemctl is-active ssh &>/dev/null || ! systemctl is-enabled ssh &>/dev/null; then 
    install-pkg.sh openssh-server 
    sudo systemctl enable ssh 
    sudo systemctl start ssh
fi 

# mount data dirs
zhu_mount linuxqa:/qa/people /mnt/linuxqa
