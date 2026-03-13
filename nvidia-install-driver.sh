#!/usr/bin/env bash

set -o pipefail 
rm -rf /tmp/cmd 

shutdown_graphical_env() {
    # unload nvidia kernel modules 
    if [[ ! -z $(lsmod | awk '$1 ~ /^nvidia/ {print $1}') ]]; then 
        read -p "Press [Enter] to unload nvidia kernel modules: "
        sudo systemctl isolate multi-user && echo "sudo systemctl isolate graphical" >/tmp/cmd
        sudo systemctl stop nvidia-persistenced 2>/dev/null || sudo nvidia-smi -pm 0 2>/dev/null 
        sudo rmmod nvidia_drm nvidia_modeset nvidia_uvm nvidia 2>/dev/null && sleep 3
        if [[ ! -z $(lsmod | awk '$1 ~ /^nvidia/ {print $1}') ]]; then 
            sudo modprobe -r $(lsmod | awk '$1 ~ /^nvidia/ {print $1}') 2>/dev/null 
        fi 
        if [[ ! -z $(lsmod | awk '$1 ~ /^nvidia/ {print $1}') ]]; then 
            echo "Failed to unload these modules:"
            lsmod | awk '$1 ~ /^nvidia/ {print $1}'
            return 1
        fi 
    fi 

    # remove apt-based nvidia packaged 
    nvidia_packages=$(dpkg -l | awk '/^(ii|rc)[[:space:]]+(nvidia|libnvidia|linux-modules-nvidia|xserver-xorg-video-nvidia)/ { print $2 }')
    if [[ ! -z $nvidia_packages ]]; then
        echo "$nvidia_packages"
        read -p "Press [Enter] to uninstall nvidia packages:"
        sudo apt purge -y $nvidia_packages
        sudo apt autoremove -y
    fi
}

install_local_file() {
    local file=$1 
    [[ $XDG_SESSION_TYPE != tty ]] && return 1
    [[ -z $file || ! -e $file ]] && return 1
    [[ -z $(which expect) ]] && sudo apt install -y expect 

    sudo chmod +x $file 2>/dev/null 
    sudo $file -ui=none --accept-license --disable-nouveau --no-cc-version-check --install-libglvnd && {
        sudo nvidia-smi -pm 1 
        sudo systemctl isolate graphical
    }
}

if [[ -z $1 || -f $1 ]]; then 
    shutdown_graphical_env || exit 1
    install_local_file $(realpath $1)
else 
    if ! ping -c 1 -W 1 linuxqa >/dev/null 2>&1; then
        read -p "Reconnect to nvidia vpn? [Y/n]: " recon
        [[ -z $recon || $recon == y ]] && nvidia-vpn.sh
    fi
    if ping -c 1 -W 1 linuxqa >/dev/null 2>&1; then
        if [[ ! -d /mnt/linuxqa/wanliz ]]; then 
            sudo mkdir -p /mnt/linuxqa && sudo mount -t nfs linuxqa:/qa/people /mnt/linuxqa
        fi 
        if [[ -d /mnt/linuxqa/wanliz ]]; then 
            shutdown_graphical_env || exit 1
            sudo -iu root -- bash -lic "[[ ! -d /root/nvt ]] && /mnt/linuxqa/nvt.sh sync; /mnt/linuxqa/nvt.sh drivers $@" 
        fi 
    fi 
fi 

if [[ -f /tmp/cmd ]]; then 
    chmod +x /tmp/cmd
    source /tmp/cmd 
    rm -rf /tmp/cmd 
fi 
