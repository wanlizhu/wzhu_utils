#!/usr/bin/env bash
set -o pipefail

runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export XDG_RUNTIME_DIR=$runtime_dir
export DBUS_SESSION_BUS_ADDRESS=unix:path=$runtime_dir/bus

session_id=
leader_pid=
unset DISPLAY
unset XAUTHORITY
unset WAYLAND_DISPLAY

read_env_from_proc() {
    while read -r pid; do 
        [[ -z $pid || ! -r /proc/$pid/environ ]] && continue 
        DISPLAY=$(tr '\0' '\n' </proc/$pid/environ | awk -F= '/^DISPLAY=/{print $2; exit}')
        XAUTHORITY=$(tr '\0' '\n' </proc/$pid/environ | awk -F= '/^XAUTHORITY=/{print $2; exit}')
        WAYLAND_DISPLAY=$(tr '\0' '\n' </proc/$pid/environ | awk -F= '/^WAYLAND_DISPLAY=/{print $2; exit}')
    done < <([[ $1 =~ ^[0-9]+$ ]] && echo $1 || pgrep -u $UID -f $1)
    [[ -n $DISPLAY || -n $XAUTHORITY || -n $WAYLAND_DISPLAY ]]
}

session_id=$(loginctl list-sessions --no-legend | grep "seat0" | awk '{print $1}')
session_type=$(loginctl show-session $session_id -p Type --value)
leader_pid=$(loginctl show-session $session_id -p Leader --value 2>/dev/null)

read_env_from_proc $leader_pid ||
read_env_from_proc kwin_wayland ||
read_env_from_proc startplasma-wayland ||
read_env_from_proc plasmashell ||
read_env_from_proc gnomeshell 

[[ ! -z $DISPLAY ]] && export DISPLAY  
[[ ! -z $XAUTHORITY ]] && export XAUTHORITY  
[[ ! -z $WAYLAND_DISPLAY ]] && export WAYLAND_DISPLAY  

echo SESSION_ID=${session_id:-N/A}
echo SESSION_TYPE=${session_type:-N/A}
echo DISPLAY=${DISPLAY:-N/A}
echo XAUTHORITY=${XAUTHORITY:-N/A}
echo XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR
echo DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS
echo WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-N/A}

if [[ -z $1 || $1 != noshell ]]; then 
    exec bash
fi 