#!/usr/bin/env bash

set -o pipefail 

if [[ $1 == -t0 ]]; then 
    active_sid=$(
        while read -r session; do
            seat=$(loginctl show-session $session -p Seat --value)
            state=$(loginctl show-session $session -p State --value)
            if [[ $seat == seat0 && $state == active ]]; then
                echo $session
            fi
        done < <(loginctl list-sessions --no-legend | awk '{print $1}')
  )
  [[ ! -z $active_sid ]] && loginctl show-session $active_sid -p Type --value
else 
    printf "%-6s %-5s %-8s %-6s %-6s %-7s %-4s %s\n" "SESSION" "UID" "USER" "SEAT" "TTY" "STATE" "IDLE" "TYPE"
    loginctl list-sessions --no-legend | 
    while read -r sid uid user seat tty state idle _; do
        type=$(loginctl show-session $sid -p Type --value)
        printf "%-6s %-5s %-8s %-6s %-6s %-7s %-4s %s\n" "$sid" "$uid" "$user" "$seat" "$tty" "$state" "$idle" "$type"
    done
fi 
