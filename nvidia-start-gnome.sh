#!/usr/bin/env bash
set -o pipefail 

if [[ ! -z $(pidof Xorg) ]]; then 
    echo "Found Xorg: $(pidof Xorg)"
elif [[ ! -z $(pidof Xwayland) ]]; then 
    echo "Found Xwayland: $(pidof Xwayland)"
else
    if [[ $(systemctl get-default) != "graphical.target" ]]; then 
        sudo systemctl isolate graphical 
    fi 
    sudo systemctl restart gdm3
fi 