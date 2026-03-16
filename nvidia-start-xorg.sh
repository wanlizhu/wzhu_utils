#!/usr/bin/env bash

set -o pipefail 

if [[ ! -z $(pidof Xorg) ]]; then 
    echo "Found Xorg: $(pidof Xorg)"
elif [[ ! -z $(pidof Xwayland) ]]; then 
    echo "Found Xwayland: $(pidof Xwayland)"
else
    if [[ -d /mnt/linuxqa/wanliz ]]; then 
        screen -dm sudo -i /mnt/linuxqa/nvt.sh 3840x2160__runcmd --cmd "sleep 100000000"
        for ((i = 10; i > 0; i--)); do 
            if [[ ! -z $(pidof Xorg) || ! -z $(pidof Xwayland) ]] then 
                printf '\n'
                break 
            fi 
            printf '\rWait for Xorg/Xwayland to start ... (%2d sec left)' $i
            sleep 1
        done 
    fi 
    if [[ ! -z $(pidof Xorg) ]] then 
        echo "Xorg $(pidof Xorg) is running ..."
    elif [[ ! -z $(pidof Xwayland) ]]; then 
        echo "Xwayland $(pidof Xwayland) is running ..."
    else
        echo "Failed to start Xorg/Xwayland"
        exit 1
    fi 
fi 