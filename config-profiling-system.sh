#!/usr/bin/env bash

set -o pipefail 

# enable passwordless sudo 
if ! sudo -n true 2>/dev/null; then 
    echo "$(id -un) ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers.d/99-$(id -un)-nopasswd >/dev/null
    sudo chmod 0440 /etc/sudoers.d/99-$(id -un)-nopasswd
fi

# patch ~/.bashrc
[[ -z $(cat ~/.bashrc | grep nsight_systems) ]] && echo 'export PATH="$HOME/nsight_systems/bin:$PATH"' >>~/.bashrc
[[ -z $(cat ~/.bashrc | grep P4PORT) ]] && echo "export P4PORT=p4proxy-sc.nvidia.com:2006" >>~/.bashrc
[[ -z $(cat ~/.bashrc | grep P4USER) ]] && echo "export P4USER=wanliz" >>~/.bashrc
[[ -z $(cat ~/.bashrc | grep P4CLIENT) ]] && echo "export P4CLIENT=wanliz_sw_windows_wsl2" >>~/.bashrc
[[ -z $(cat ~/.bashrc | grep P4ROOT) ]] && echo "export P4ROOT=$HOME/sw" >>~/.bashrc
[[ -z $(cat ~/.bashrc | grep P4IGNORE) ]] && echo "export P4IGNORE=$HOME/.p4ignore" >>~/.bashrc
[[ -z $(cat ~/.bashrc | grep __GL_SYNC_TO_VBLANK) ]] && echo "export __GL_SYNC_TO_VBLANK=0" >>~/.bashrc
[[ -z $(cat ~/.bashrc | grep vblank_mode) ]] && echo "export vblank_mode=0" >>~/.bashrc
[[ -z $(cat ~/.bashrc | grep NVM_GTLAPI_TOKEN) ]] && echo "export NVM_GTLAPI_TOKEN='eyJhbGciOiJIUzI1NiJ9.eyJpZCI6IjNlMGZkYWU4LWM5YmUtNDgwOS1iMTQ3LTJiN2UxNDAwOTAwMyIsInNlY3JldCI6IndEUU1uMUdyT1RaY0Z0aHFXUThQT2RiS3lGZ0t5NUpaalU3QWFweUxGSmM9In0.Iad8z1fcSjA6P7SHIluppA_tYzOGxGv4koMyNawvERQ'" >>~/.bashrc
[[ -z $(cat ~/.bashrc | grep 'nsys-ui()') ]] && echo '
if command -v nsys-ui >/dev/null 2>&1; then
    nsys-ui() {
        if [[ $XDG_SESSION_TYPE == wayland || -n $WAYLAND_DISPLAY ]]; then
            QT_QPA_PLATFORM=xcb QT_OPENGL=desktop command nsys-ui "$@"
        else
            command nsys-ui "$@"
        fi
    }
fi
' >>~/.bashrc
[[ -z $(cat ~/.bashrc | grep 'list-login-sessions()') ]] && echo '
list-login-sessions() {
    printf '%-6s %-5s %-8s %-6s %-6s %-7s %-4s %s\n' "SESSION" "UID" "USER" "SEAT" "TTY" "STATE" "IDLE" "TYPE"
    loginctl list-sessions --no-legend | while read -r sid uid user seat tty state idle _; do
    type=$(loginctl show-session "$sid" -p Type --value)
    printf '%-6s %-5s %-8s %-6s %-6s %-7s %-4s %s\n' "$sid" "$uid" "$user" "$seat" "$tty" "$state" "$idle" "$type"
    done
}
' >>~/.bashrc

# set kernel params
find_modprobe_param() {
    while IFS= read -r conf_file; do 
        [[ ! -f $conf_file ]] && continue 
        if grep -Fq -- "$1" $conf_file; then 
            echo $conf_file
        fi 
    done < <(find /etc/modprobe.d -type f)
}
modprobe_param_changed=false
[[ -z $(find_modprobe_param "NVreg_RestrictProfilingToAdminUsers=0") ]] && echo 'options nvidia NVreg_RegistryDwords="RmProfilerFeature=0x1" NVreg_RestrictProfilingToAdminUsers=0' | sudo tee /etc/modprobe.d/nvidia-profiling.conf && modprobe_param_changed=true
[[ -z $(find_modprobe_param "nvidia-drm modeset=1") ]] && echo 'options nvidia-drm modeset=1' | sudo tee /etc/modprobe.d/nvidia-drm.conf && modprobe_param_changed=true
if [[ $modprobe_param_changed == true ]]; then 
    sudo update-initramfs -u -k all 
fi 

# install missing packages
find_or_install() {
    if (( $# )); then
        while (( $# )); do 
            dpkg -s $1 &>/dev/null || sudo apt install -y $1 
            shift 
        done 
    else # read from stdin
        while IFS= read -r pkg; do
            [[ -z $pkg ]] && continue
            dpkg -s $pkg &>/dev/null || sudo apt install -y $pkg
        done
    fi 
}
find_or_install ubuntu-dbgsym-keyring apt-transport-https ca-certificates apt-file
[[ ! -f /etc/apt/sources.list.d/ddebs.sources ]] && echo "Types: deb
URIs: http://ddebs.ubuntu.com/
Suites: $(lsb_release -cs) $(lsb_release -cs)-updates $(lsb_release -cs)-proposed 
Components: main restricted universe multiverse
Signed-by: /usr/share/keyrings/ubuntu-dbgsym-keyring.gpg" | sudo tee /etc/apt/sources.list.d/ddebs.sources && sudo apt update && sudo apt upgrade 
find_or_install debian-goodies libc6-dbg libstdc++6-dbgsym linux-image-$(uname -r)-dbgsym build-essential cmake git ninja-build pkg-config meson clang

# install amd gpu drivers 
if [[ $(lspci -nnk | grep -EA3 'VGA|3D|Display' | grep amdgpu) ]]; then 
    find_or_install libdrm2-dbgsym libdrm-amdgpu1-dbgsym mesa-vulkan-drivers-dbgsym libgl1-mesa-dri-dbgsym libgbm1-dbgsym linux-image-$(uname -r)-dbgsym
    dpkg -l | awk '$1=="ii"{print $2}' | sed -E 's/:(amd64|i386)$//' | grep -Ei '(amdgpu|amdvlk|radeon|radv|radeonsi|mesa|libdrm|vulkan|rocm|hip|hsa|opencl|xserver-xorg-video-amdgpu|xserver-xorg-video-radeon)' | sed -E 's/-dbgsym$//' |  find_or_install
fi 

# enable gnome remote desktop 
if ! sudo ss -ltnp | grep -qE ':3389\b'; then 
    find_or_install gnome-remote-desktop openssl
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
find_or_install remmina remmina-plugin-rdp freerdp2-x11