#!/usr/bin/env bash

set -o pipefail 

install_local_file() {
    local file=$1 
    [[ $XDG_SESSION_TYPE != tty ]] && return 1
    [[ -z $file || ! -e $file ]] && return 1
    [[ -z $(which expect) ]] && sudo apt install -y expect 
    sudo systemctl isolate multi-user
    sudo systemctl stop nvidia-persistenced 2>/dev/null || sudo nvidia-smi -pm 0 2>/dev/null 
    sudo rmmod nvidia_drm nvidia_modeset nvidia_uvm nvidia  
    sleep 2
    if [[ ! -z $(lsmod | awk '$1 ~ /^nvidia/ {print $1}') ]]; then 
        sudo modprobe -r $(lsmod | awk '$1 ~ /^nvidia/ {print $1}') 
    fi 
    sudo chmod +x $file 2>/dev/null 
    
expect - "$file" --ui=none --accept-license --disable-nouveau --no-cc-version-check --install-libglvnd <<'EOF'
    set timeout -1
    spawn sudo {*}$argv 
    expect_before {
        -re {Multiple kernel module types are available} {
            expect -re {Please select your response by number or name:}
            send "MIT/GPL\r"
            exp_continue
        }
        -re {There appears to already be a driver installed on your system} {
            expect -re {Please select your response by number or name:}
            send "Continue installation\r"
            exp_continue
        }
        -re {Please review the message provided by the maintainer of this alternate installation method} {
            expect -re {Please select your response by number or name:}
            send "Continue installation\r"
            exp_continue
        }
        -re {Install NVIDIA's 32-bit compatibility libraries\?} {
            send "y\r"
            exp_continue
        }
        -re {Would you like to register the kernel module sources with DKMS\?} {
            send "y\r"
            exp_continue
        }
        -re {Would you like to run the nvidia-xconfig utility to automatically update your X configuration file} {
            send "y\r"
            exp_continue
        }
    }
    expect eof
    catch wait result
    set status [lindex $result 3]
    exit $status
EOF

    status=$?
    sudo nvidia-smi -pm 1 
    sudo systemctl isolate graphical
    return $status
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
