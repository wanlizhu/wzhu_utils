#!/usr/bin/env bash
set -o pipefail 

output=screenshot$([[ -z $1 ]] || echo "_$1").png
if [[ ! -z $2 ]]; then   
    mkdir -p $2
    find $2 -mindepth 1 -delete 
    output=$2/screenshot$([[ -z $1 ]] || echo "_$1").png
fi 

fallback_nvidia_fbc=$([[ -f /tmp/ssfallback ]] && echo true || echo false) 
if [[ $fallback_nvidia_fbc == false ]]; then 
    if [[ $(list-login-session.sh seat0.type) == wayland ]]; then 
        if [[ $XDG_CURRENT_DESKTOP == *GNOME* ]]; then
            [[ -z $(which gnome-screenshot) ]] && sudo apt install -y gnome-screenshot &>/dev/null 
            timeout 1 gnome-screenshot -f $output || fallback_nvidia_fbc=true 
        else 
            [[ -z $(which grim) ]] && sudo apt install -y grim &>/dev/null 
            timeout 1 grim $output || fallback_nvidia_fbc=true 
        fi  
    else
        [[ -z $(which magick) && -z $(which import) ]] && sudo apt install -y imagemagick
        if command -v magick > /dev/null; then
            timeout 1 magick import -window root $output || fallback_nvidia_fbc=true 
        elif command -v import > /dev/null; then
            timeout 1 import -window root $output || fallback_nvidia_fbc=true  
        fi
    fi 
fi 

if [[ $fallback_nvidia_fbc == true ]]; then 
    echo 1 > /tmp/ssfallback
    backend=NvFBC
    if [[ $(list-login-session.sh seat0.type) == wayland ]]; then
        backend=NvFBCPipeWire
    fi
    
fi 