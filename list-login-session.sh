#!/usr/bin/env bash
set -o pipefail 

if [[ $1 == 'seat0.type' ]]; then 
    if [[ ! -z $(which loginctl) ]]; then 
        seat0_sid=$(
            while read -r session; do
                seat=$(loginctl show-session $session -p Seat --value)
                if [[ $seat == seat0 ]]; then
                    echo $session
                fi
            done < <(loginctl list-sessions --no-legend | awk '{print $1}')
        )
        if [[ ! -z $seat0_sid ]]; then 
            loginctl show-session $seat0_sid -p Type --value
        else
            echo "Error: can't find the session id of seat0"
        fi 
    fi 
else 
    printf "%-6s %-5s %-8s %-6s %-6s %-7s %-4s %s\n" "SESSION" "UID" "USER" "SEAT" "TTY" "STATE" "IDLE" "TYPE"
    loginctl list-sessions --no-legend | 
    while read -r sid uid user seat tty state idle _; do
        type=$(loginctl show-session $sid -p Type --value)
        printf "%-6s %-5s %-8s %-6s %-6s %-7s %-4s %s\n" "$sid" "$uid" "$user" "$seat" "$tty" "$state" "$idle" "$type"
    done
fi 
