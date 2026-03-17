#!/usr/bin/env bash

set -o pipefail 
rm -rf /tmp/cmd 

# Installing nvidia drivers on Linux requires to unload all nvidia kernel modules first
shutdown_graphical_env() {
    if [[ ! -z $(pidof Xorg) || ! -z $(pidof Xwayland) ]]; then 
        sudo systemctl isolate multi-user && echo "sudo systemctl isolate graphical" >/tmp/cmd
    fi 

    # Unload all active nvidia kernel modules 
    if [[ ! -z $(lsmod | awk '$1 ~ /^nvidia/ {print $1}') ]]; then 
        lsmod | awk '$1 ~ /^nvidia/ {print $1}'
        read -p "Press [Enter] to unload nvidia kernel modules: "
        sudo systemctl stop nvidia-persistenced 2>/dev/null || sudo nvidia-smi -pm 0 2>/dev/null 
        sudo rmmod nvidia_drm nvidia_modeset nvidia_uvm nvidia 2>/dev/null && sleep 3
        # Remove all remaining nvidia modules 
        if [[ ! -z $(lsmod | awk '$1 ~ /^nvidia/ {print $1}') ]]; then 
            sudo modprobe -r $(lsmod | awk '$1 ~ /^nvidia/ {print $1}') 2>/dev/null 
        fi 
        # Check if there is no nvidia module existing 
        if [[ ! -z $(lsmod | awk '$1 ~ /^nvidia/ {print $1}') ]]; then 
            echo "Failed to unload these modules:"
            lsmod | awk '$1 ~ /^nvidia/ {print $1}'
            return 1
        fi 
    else
        echo "Found 0 active nvidia kernel module"
    fi 

    # Remove apt-based nvidia packaged 
    nvidia_packages=$(dpkg -l | awk '/^(ii|rc)[[:space:]]+(nvidia|libnvidia|linux-modules-nvidia|xserver-xorg-video-nvidia)/ { print $2 }')
    if [[ ! -z $nvidia_packages ]]; then
        echo "$nvidia_packages"
        read -p "Press [Enter] to uninstall nvidia packages:"
        sudo apt purge -y $nvidia_packages
        sudo apt autoremove -y
    fi
}

# Launch a text-based ui for interactive installation 
install_local_file() {
    local file=$1 
    [[ $XDG_SESSION_TYPE != tty ]] && return 1
    [[ -z $file || ! -e $file ]] && return 1
    [[ ! -z $(lsmod | awk '$1 ~ /^nvidia/ {print $1}') ]] && return 1
    [[ -z $(which expect) ]] && sudo apt install -y expect 

    sudo chmod +x $file 2>/dev/null 
    sudo $file --accept-license --disable-nouveau --no-cc-version-check --install-libglvnd && {
        # On success, restore the windowing system 
        sudo nvidia-smi -pm 1 
        sudo systemctl isolate graphical
    }
}

# If $1 is an existing file path 
if [[ -z $1 || -f $1 ]]; then 
    shutdown_graphical_env || exit 1
    install_local_file $(realpath $1)
else 
    # Fallback to call nvtest script 
    # [required] Must be inside nvidia domain 
    if ! ping -c 1 -W 1 linuxqa >/dev/null 2>&1; then
        read -p "Reconnect to nvidia vpn? [Y/n]: " recon
        [[ -z $recon || $recon == y ]] && nvidia-vpn.sh
    fi
    if ping -c 1 -W 1 linuxqa >/dev/null 2>&1; then
        # [required] Must have /mnt/linuxqa mounted 
        if [[ ! -d /mnt/linuxqa/wanliz ]]; then 
            sudo mkdir -p /mnt/linuxqa && sudo mount -t nfs linuxqa:/qa/people /mnt/linuxqa
        fi 
        if [[ -d /mnt/linuxqa/wanliz ]]; then 
            shutdown_graphical_env || exit 1
            sudo -iu root -- bash -lc '[[ ! -d /root/nvt ]] && /mnt/linuxqa/nvt.sh sync; /mnt/linuxqa/nvt.sh drivers "$@"' /usr/bin/bash "$@"
        fi 
    fi 
fi 

if [[ -f /tmp/cmd ]]; then 
    chmod +x /tmp/cmd
    source /tmp/cmd 
fi 
