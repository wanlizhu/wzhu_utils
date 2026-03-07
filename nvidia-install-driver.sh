#!/usr/bin/env bash

set -o pipefail 

install_local_file() {
    local file=$1 
    [[ $XDG_SESSION_TYPE != tty ]] && return 1
    sudo systemctl isolate multi-user
    sudo systemctl stop nvidia-persistenced 2>/dev/null || sudo nvidia-smi -pm 0 2>/dev/null 
    sudo modprobe -r $(lsmod | awk '$1 ~ /^nvidia/ {print $1}') || sudo rmmod nvidia_drm nvidia_modeset nvidia_uvm nvidia  
    [[ ! -z $file && -f $file ]] && sudo chmod +x $file && sudo $file --ui=none --accept-license --disable-nouveau --no-cc-version-check --install-libglvnd && sudo nvidia-smi -pm 1 
    sudo systemctl isolate graphical
}

install_version_build() {
    local version=$1
    local buildtype=$([[ -z $2 ]] && echo "" || echo "/$2") 
    if [[ -d /mnt/builds/release ]]; then 
        rsync -Pah /mnt/builds/release/display/$(uname -m)$buildtype/$version/NVIDIA-Linux-$(uname -m)-$version.run $HOME || return 1
    else
        cd $HOME && 
        wget http://linuxqa.nvidia.com/builds/release/display/$(uname -m)$buildtype/$version/NVIDIA-Linux-$(uname -m)-$version.run || return 1
    fi 
    if [[ -f $HOME/NVIDIA-Linux-$(uname -m)-$version.run ]]; then 
        install_local_file $HOME/NVIDIA-Linux-$(uname -m)-$version.run
    fi 
}

if [[ -z $1 || -f $1 ]]; then 
    install_local_file $(realpath $1)
elif [[ $1 =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
    install_version_build "$@"
fi 

