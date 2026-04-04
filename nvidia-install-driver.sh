#!/usr/bin/env bash
set -o pipefail 
rm -rf /tmp/cmd 
source ~/.bashrc_extended

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
            echo_in_red "Failed to unload these modules:"
            lsmod | awk '$1 ~ /^nvidia/ {print $1}'
            return 1
        fi 
    else
        echo_in_cyan "Found 0 active nvidia kernel module"
    fi 

    # Remove existing nvidia modules from initramfs 
    for initrd in /boot/initrd.img-*; do
        kernel_version=${initrd##*/initrd.img-}
        [[ ! -e $initrd ]] && continue
        if ! lsinitramfs $initrd 2>/dev/null | grep -Eq '(^|/)nvidia[^/]*\.ko([.-].*)?$'; then
            echo_in_cyan "No NVIDIA modules found in initramfs for kernel $kernel_version"
            continue
        fi

        echo_in_cyan "Removing NVIDIA modules from /lib/modules/$kernel_version ..."
        find /lib/modules/$kernel_version -type f | grep -E '/nvidia[^/]*\.ko([.-].*)?$' | while read -r nv_ko_file; do
            echo "rm -f $nv_ko_file" 
            rm -f $nv_ko_file 
        done

        depmod $kernel_version
        update-initramfs -u -k $kernel_version
    done
}

# Launch a text-based ui for interactive installation 
run_nvidia_driver_installer() {
    local file=$1 
    local test_pkg=$2
    echo_in_yellow "Must run over SSH connection!"
    read -p "Press [Enter] to continue: "
    [[ ! -e $file ]] && { echo_in_red "File doesn't exist: $file"; exit 1; }
    [[ ! -z $(lsmod | awk '$1 ~ /^nvidia/ {print $1}') ]] && { lsmod | awk '$1 ~ /^nvidia/ {print $1}'; echo_in_red "Failed to unload nvidia modules"; exit 1; }
    [[ -z $(which expect) ]] && sudo apt install -y expect 
    [[ ! -z $(which nvidia-uninstall) ]] && sudo nvidia-uninstall 

    sudo chmod +x $file 2>/dev/null 
    sudo $file --accept-license --disable-nouveau --no-cc-version-check --install-libglvnd && {
        echo_in_green "Installed $file"
        if [[ -e $test_pkg ]]; then 
            sudo rm -rf $HOME/NVIDIA-Linux-$(uname -m)-tests/
            mkdir -p $HOME/NVIDIA-Linux-$(uname -m)-tests
            mkdir -p $HOME/.local/bin
            cd $HOME/NVIDIA-Linux-$(uname -m)-tests
            tar -xf $test_pkg || echo_in_red "Failed to unzip $test_pkg"
            cd tests-Linux-$(uname -m) && {
                cp LockToRatedTdp/LockToRatedTdp $HOME/.local/bin/ && echo_in_green "Installed LockToRatedTdp"
                cp sanbag-tool/sandbag-tool $HOME/.local/bin/ && echo_in_green "Installed sandbag-tool"
            }
        fi 
        sudo nvidia-smi -pm 1 
        sudo systemctl isolate graphical
    } || {
        echo_in_red "Failed to install $file"
        cat <<'EOF'
=================================================
# Fix 1: remove old nvidia kernels from initramfs 
sudo systemctl isolate multi-user 
sudo systemctl stop nvidia-persistenced 
sudo modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia  
find /lib/modules/$(uname -r) -type f | 
    grep -E '/nvidia([^/]*|/.+)\.ko(\.zst)?$' | 
    sudo xargs -r rm -f
sudo depmod -a
sudo update-initramfs -u
sudo systemctl isolate graphical
=================================================
EOF
    }
}

download_nvidia_driver_installer() {
    local filename=$(basename $1)
    local filedir=$(dirname $1)
    pushd $HOME >/dev/null 
    sudo rm -rf $filename tests-Linux-$(uname -m).tar
    wget "$1" && echo "Downloaded installer: $HOME/$filename" || echo "Downloaded installer: N/A"
    wget "$filedir/tests-Linux-$(uname -m).tar" && echo "Downloaded test pkg: $HOME/tests-Linux-$(uname -m).tar" || echo "Downloaded test pkg: N/A"
    popd >/dev/null 
}

# If $1 is an existing file path 
if [[ ! -z $1 ]]; then 
    installer=$1
    test_pkg=$2
    if [[ $installer == "http"* ]]; then 
        download_nvidia_driver_installer $1 | tee /tmp/log 
        installer=$(cat /tmp/log | grep "Downloaded installer:" | awk '{print $3}')
        test_pkg=$(cat /tmp/log | grep "Downloaded test pkg:" | awk '{print $4}')
    fi 

    shutdown_graphical_env || exit 1
    run_nvidia_driver_installer $installer $test_pkg
fi 

if [[ -f /tmp/cmd ]]; then 
    chmod +x /tmp/cmd
    source /tmp/cmd 
fi 

if [[ $(nvidia-smi) == *"No devices were found"* ]]; then 
    echo_in_cyan "Reset nvidia gpu device ... [OK]"
    sudo nvidia-smi -r 
    sudo systemctl restart display-manager  
fi 
