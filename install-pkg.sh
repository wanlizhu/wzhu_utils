#!/usr/bin/env bash

set -o pipefail 

required_pkgs=()
failed_pkgs=()

if (( $# )); then
    required_pkgs=("$@")
else # read from stdin
    while IFS= read -r pkg; do
        [[ -z $pkg ]] && continue
        required_pkgs+=("$pkg")
    done
fi 

for pkg in "${required_pkgs[@]}"; do 
    dpkg -s $pkg &>/dev/null && continue 
    sudo apt install -y $pkg || failed_pkgs+=("$pkg")
done 

if (( ${#failed_pkgs[@]} )); then
    for pkg in "${failed_pkgs[@]}"; do 
        case $pkg in 
            libxcb-errors*) 
                pushd /tmp >/dev/null 
                baseurl=http://archive.ubuntu.com/ubuntu/pool/universe/x/xcb-util-errors
                wget -O libxcb-errors0.deb     $baseurl/libxcb-errors0_1.0.1-4build1_amd64.deb
                wget -O libxcb-errors-dev.deb  $baseurl/libxcb-errors-dev_1.0.1-4build1_amd64.deb
                sudo dpkg -i libxcb-errors0.deb libxcb-errors-dev.deb
                sudo apt -f install -y
                popd >/dev/null 
            ;;
            *) echo "Todo: fallback build of $pkg" ;;
        esac
    done 
fi 