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
[[ -z $(find_modprobe_param "NVreg_RestrictProfilingToAdminUsers=0") ]] && echo 'options nvidia NVreg_RegistryDwords="RmProfilerFeature=0x1" NVreg_RestrictProfilingToAdminUsers=0' | sudo tee /etc/modprobe.d/nvidia-profiling.conf >/dev/null && modprobe_param_changed=true
[[ -z $(find_modprobe_param "nvidia-drm modeset=1") ]] && echo 'options nvidia-drm modeset=1' | sudo tee /etc/modprobe.d/nvidia-drm.conf >/dev/null && modprobe_param_changed=true
if [[ $modprobe_param_changed == true ]]; then 
    sudo update-initramfs -u -k all 
fi 

