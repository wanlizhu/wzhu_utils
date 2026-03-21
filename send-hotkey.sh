#!/usr/bin/env bash
set -o pipefail 

[[ -z $(which xdotool)  ]] && sudo apt install -y xdotool 
[[ -z $(which ydotool)  ]] && sudo apt install -y ydotool 
[[ -z $(which ydotoold) ]] && sudo apt install -y ydotoold 

type=$(loginctl show-session $(loginctl | awk '/tty|pts/ { print $1; exit }') -p Type)

if [[ $type == "Type=wayland" ]]; then 
    sudo pkill ydotoold
    sudo ydotoold --socket-path=/tmp/ydotool.sock &
    sleep 0.2
    sudo YDOTOOL_SOCKET=/tmp/.ydotool_socket ydotool key 87:1
    sleep 0.2
    sudo YDOTOOL_SOCKET=/tmp/.ydotool_socket ydotool key 87:0
else
    if [[ -e /run/user/$(id -u)/gdm/Xauthority ]]; then 
        DISPLAY=:0 XAUTHORITY=/run/user/$(id -u)/gdm/Xauthority xdotool key F11 
    else 
        DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority xdotool key F11 
    fi 
fi 