#!/usr/bin/env bash
set -o pipefail

runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export XDG_RUNTIME_DIR=$runtime_dir
export DBUS_SESSION_BUS_ADDRESS=unix:path=$runtime_dir/bus

session_id=
leader_pid=
session_type=
unset DISPLAY
unset XAUTHORITY
unset WAYLAND_DISPLAY

while read -r sid; do
    [[ -z $sid ]] && continue
    active=$(loginctl show-session $sid -p Active --value 2>/dev/null)
    remote=$(loginctl show-session $sid -p Remote --value 2>/dev/null)
    class=$(loginctl show-session $sid -p Class --value 2>/dev/null)
    type=$(loginctl show-session $sid -p Type --value 2>/dev/null)
    [[ $active != yes ]] && continue
    [[ $remote != no ]] && continue
    [[ $class != user ]] && continue
    [[ $type != wayland && $type != x11 ]] && continue
    session_id=$sid
    session_type=$type
    break
done < <(loginctl show-user $(id -u) -p Sessions --value 2>/dev/null | tr ' ' '\n')

leader_pid=$(loginctl show-session $session_id -p Leader --value 2>/dev/null)
if [[ -r /proc/$leader_pid/environ ]]; then
    DISPLAY=$(tr '\0' '\n' </proc/$leader_pid/environ 2>/dev/null | awk -F= '/^DISPLAY=/{print $2; exit}')
    XAUTHORITY=$(tr '\0' '\n' </proc/$leader_pid/environ 2>/dev/null | awk -F= '/^XAUTHORITY=/{print $2; exit}')
    WAYLAND_DISPLAY=$(tr '\0' '\n' </proc/$leader_pid/environ 2>/dev/null | awk -F= '/^WAYLAND_DISPLAY=/{print $2; exit}')
fi

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

exec bash