#!/usr/bin/env bash

set -o pipefail 

install_local_file() {
    local file=$1 
    [[ $XDG_SESSION_TYPE != tty ]] && return 1
    [[ -z $file || ! -e $file ]] && return 1
    [[ -z $(which expect) ]] && sudo apt install -y expect 
    sudo chmod +x $file 2>/dev/null 

    # unload nvidia kernel modules 
    sudo systemctl isolate multi-user
    if [[ ! -z $(lsmod | grep '^nvidia') ]]; then 
        sudo systemctl stop nvidia-persistenced 2>/dev/null || sudo nvidia-smi -pm 0 2>/dev/null 
        sudo rmmod nvidia_drm nvidia_modeset nvidia_uvm nvidia && sleep 3
        if [[ ! -z $(lsmod | awk '$1 ~ /^nvidia/ {print $1}') ]]; then 
            sudo modprobe -r $(lsmod | awk '$1 ~ /^nvidia/ {print $1}') 
        fi 
    fi 

    # remove apt-based nvidia packaged 
    nvidia_packages=$(dpkg -l | awk '/^(ii|rc)[[:space:]]+(nvidia|libnvidia|linux-modules-nvidia|xserver-xorg-video-nvidia)/ { print $2 }')
    if [[ ! -z $nvidia_packages ]]; then
        echo "$nvidia_packages"
        read -p "Uninstall these apt-based nvidia packages? [Y/n]: " uninstall
        if [[ -z $uninstall || $uninstall == [Yy] ]]; then 
            sudo apt purge -y $nvidia_packages
            sudo apt autoremove -y
        fi 
    fi

    sudo $file -ui=none --accept-license --disable-nouveau --no-cc-version-check --install-libglvnd && {
        sudo nvidia-smi -pm 1 
        sudo systemctl isolate graphical
    }
}

if [[ -z $1 || -f $1 ]]; then 
    install_local_file $(realpath $1)
else 
    sudo -iu root -- bash -lic "/mnt/linuxqa/nvt.sh drivers $@" 
fi 
