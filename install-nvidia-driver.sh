#!/usr/bin/env bash

set -o pipefail 

install_local_file() {
    [[ $XDG_SESSION_TYPE != tty ]] && return 1
    sudo systemctl isolate multi-user
    sudo systemctl stop nvidia-persistenced || sudo nvidia-smi -pm 0
    sudo modprobe -r $(lsmod | awk '$1 ~ /^nvidia/ {print $1}') || sudo rmmod nvidia_drm nvidia_modeset nvidia_uvm nvidia
    [[ ! -z $1 && -f $1 ]] && sudo chmod +x $1 && sudo $1 --ui=none --accept-license --disable-nouveau --no-cc-version-check --install-libglvnd && sudo nvidia-smi -pm 1 
    sudo systemctl isolate graphical
}

if [[ -z $1 || -f $1 ]]; then 
    install_local_file $(realpath $1)
else 
    echo TODO
fi 

