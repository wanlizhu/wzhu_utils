#!/usr/bin/env bash

set -o pipefail 

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

# patch ~/.bashrc
[[ -z $(cat ~/.bashrc | grep "nvidia-profiling.sh") ]] && echo -e "\n[[ -f ~/nvidia-profiling.sh ]] && source ~/nvidia-profiling.sh" >>~/.bashrc 
echo '#!/bin/bash' >~/nvidia-profiling.sh
echo 'export PATH="$HOME:$HOME/bin:$HOME/.local/bin:$PATH"' >>~/nvidia-profiling.sh 
echo 'export PATH="$HOME/wzhu_utils:$PATH"' >>~/nvidia-profiling.sh 
echo 'export PATH="$HOME/wzhu_utils/testcase:$PATH"' >>~/nvidia-profiling.sh 
echo 'export PATH="$HOME/wzhu_utils/profiling:$PATH"' >>~/nvidia-profiling.sh 
echo 'export PATH="$HOME/wzhu_utils/profiling/oncpu:$PATH"' >>~/nvidia-profiling.sh 
echo 'export PATH="$HOME/wzhu_utils/profiling/offcpu:$PATH"' >>~/nvidia-profiling.sh 
echo 'export PATH="$HOME/nsight_systems/bin:$PATH"' >>~/nvidia-profiling.sh 
echo 'export PATH="/mnt/linuxqa/wanliz/$(uname -m):/mnt/linuxqa/wanliz/$(uname -m)/p4v/bin:$PATH"' >>~/nvidia-profiling.sh 
echo "export P4PORT=p4proxy-sc.nvidia.com:2006" >>~/nvidia-profiling.sh
echo "export P4USER=wanliz" >>~/nvidia-profiling.sh
echo "export P4CLIENT=wanliz_sw_windows_wsl2" >>~/nvidia-profiling.sh
echo "export P4ROOT=$HOME/wzhu_p4sw" >>~/nvidia-profiling.sh
echo "export P4IGNORE=$HOME/.p4ignore" >>~/nvidia-profiling.sh
echo "export __GL_SYNC_TO_VBLANK=0" >>~/nvidia-profiling.sh 
echo "export vblank_mode=0" >>~/nvidia-profiling.sh 
echo "reload() { source ~/.bashrc; }" >>~/nvidia-profiling.sh
echo "pp() { pushd ~/wzhu_utils; git add .; git commit -m s && { git pull; git push; } || git pull; popd; }" >>~/nvidia-profiling.sh
cat >>~/nvidia-profiling.sh <<'EOF'
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
if [[ ! -z $(which install-pkg.sh) ]]; then 
    if [[ ! -f /etc/apt/sources.list.d/ddebs.sources ]]; then
        echo "Types: deb
URIs: http://ddebs.ubuntu.com/
Suites: $(lsb_release -cs) $(lsb_release -cs)-updates $(lsb_release -cs)-proposed 
Components: main restricted universe multiverse
Signed-by: /usr/share/keyrings/ubuntu-dbgsym-keyring.gpg" | sudo tee /etc/apt/sources.list.d/ddebs.sources 
        install-pkg.sh ubuntu-dbgsym-keyring apt-transport-https ca-certificates apt-file 
    fi 
    if [[ ! -z $(apt list '?upgradable !?phasing') ]]; then 
        sudo apt update  
        sudo apt upgrade -y 
        sudo apt autoremove -y  
    fi  
    install-pkg.sh debian-goodies libc6-dbg libstdc++6-dbgsym \
        build-essential cmake git ninja-build pkg-config meson clang \
        vim net-tools mesa-utils vulkan-tools libvulkan-dev screen \
        btop htop nvtop sysprof pciutils nfs-common openssh-server \
        libxcb-icccm4 libxcb-cursor0 libxcb-image0 libxcb-keysyms1 \
        libxcb-render-util0 libxcb-xkb1 libxkbcommon-x11-0 bsdextrautils \
        python3-pip python3-pandas cpufrequtils stress-ng glmark2

    find . -maxdepth 1 -type f -name '*_dbgsym_packages.txt' -print0 |
    while IFS= read -r -d '' file; do
        while IFS= read -r pkg; do
            if [[ ! -z $(which install-pkg.sh) ]]; then 
                install-pkg.sh $pkg 
            else 
                sudo apt install -y $pkg 
            fi 
        done < "$file"
    done

    if [[ ! -z $(apt list --installed 'libreoffice*' 2>/dev/null | grep libreoffice) ]]; then 
        read -p "Press [Enter] to uninstall libre office: "
        sudo apt purge -y libreoffice*
        sudo apt autoremove -y 
    fi 
fi 

# config git env 
git config --global user.email >/dev/null 2>&1 || git config --global user.email zhu.wanli@icloud.com
git config --global user.name >/dev/null 2>&1 || git config --global user.name "Wanli Zhu"
git config --global pull.rebase >/dev/null 2>&1 || git config --global pull.rebase false

# install amd gpu drivers 
if [[ $(lspci -nnk | grep -EA3 'VGA|3D|Display' | grep amdgpu) && ! -z $(which install-pkg.sh) ]]; then 
    install-pkg.sh libdrm2-dbgsym libdrm-amdgpu1-dbgsym mesa-vulkan-drivers-dbgsym libgl1-mesa-dri-dbgsym libgbm1-dbgsym linux-image-$(uname -r)-dbgsym
    dpkg -l | awk '$1=="ii"{print $2}' | sed -E 's/:(amd64|i386)$//' | grep -Ei '(amdgpu|amdvlk|radeon|radv|radeonsi|mesa|libdrm|vulkan|rocm|hip|hsa|opencl|xserver-xorg-video-amdgpu|xserver-xorg-video-radeon)' | sed -E 's/-dbgsym$//' |  install-pkg.sh
fi 

# enable ssh server
if ! systemctl is-active ssh &>/dev/null || ! systemctl is-enabled ssh &>/dev/null; then 
    if [[ ! -z $(which install-pkg.sh) ]]; then 
        install-pkg.sh openssh-server 
    else
        sudo apt install -y openssh-server 
    fi 
    sudo systemctl enable ssh 
    sudo systemctl start ssh
fi 

# enable remote login 
if [[ ! -z $(which list-login-session.sh) ]]; then 
    login_session_type=$(list-login-session.sh -t0)
else
    login_session_type=
fi 
if [[ $login_session_type == x11 ]]; then
    # x11: enable x11vnc 
    if ! ss -ltnp | grep -E "LISTEN.+:5900\b" >/dev/null; then
        [[ -z $(which screen) ]] && sudo apt install -y screen 
        [[ -z $(which x11vnc) ]] && sudo apt install -y x11vnc 
        screen -dmS 'x11vnc-server' bash -c 'x11vnc -display :0 -auth guess -forever -loop -shared -noxdamage -repeat >/tmp/x11vnc.log 2>&1' 
        sleep 3
        screen -ls | grep -F x11vnc-server 
        ss -ltnp | grep -E "LISTEN.+:5900\b"
    fi 
elif [[ $login_session_type == wayland ]]; then
    # wayland: enable gnome remote desktop
    if ! sudo ss -ltnp | grep -qE ':3389\b'; then
        if [[ ! -z $(which install-pkg.sh) ]]; then 
            install-pkg.sh gnome-remote-desktop openssl remmina remmina-plugin-rdp freerdp2-x11
        else
            sudo apt install -y gnome-remote-desktop openssl remmina remmina-plugin-rdp freerdp2-x11
        fi 
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
        sudo grdctl --system rdp set-credentials wzhu zhujie
        sudo grdctl --system rdp enable
        sudo ufw disable || sudo ufw allow 3389/tcp 
        sudo systemctl daemon-reload
        sudo systemctl restart gnome-remote-desktop.service
        echo "Wait for 3 seconds" && sleep 3
        sudo grdctl --system status
        sudo ss -ltnp | grep -E ':3389\b' || {
            echo "RDP server is not listening on TCP/3389"
            sudo systemctl status gnome-remote-desktop.service --no-pager
            sudo journalctl -u gnome-remote-desktop.service -b --no-pager | tail -n 120
        }
    fi 
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

if [[ -d /data ]]; then 
    pushd $HOME >/dev/null 
    [[ ! -e wzhu_utils ]] && ln -vsf /data/wzhu_utils wzhu_utils 
    [[ ! -e wzhu_p4sw  ]] && ln -vsf /data/wzhu_p4sw  wzhu_p4sw 
    [[ ! -e .ssh       ]] && ln -vsf /data/_ssh .ssh 
    [[ ! -e .bashrc    ]] && ln -vsf /data/_bashrc .bashrc 
    [[ ! -e Documents  ]] && ln -vsf /data/Documents Documents 
    [[ ! -e Downloads  ]] && ln -vsf /data/Downloads Downloads
    [[ ! -e Pictures   ]] && ln -vsf /data/Pictures Pictures 
    popd >/dev/null 
fi 

if [[ ! -z $(which collect-system-info.sh) ]]; then 
    collect-system-info.sh brief 
fi 

exec /usr/bin/bash 