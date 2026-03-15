#!/usr/bin/env bash

set -o pipefail 

if [[ -z $(which globalprotect) ]]; then 
    pushd /tmp 
    wget https://d2hvyxt0t758wb.cloudfront.net/gp_install_files/gp_install.sh

    chmod +x ./gp_install.sh 
    ./gp_install.sh 
    popd 
fi 

echo "Add Nvidia portal in GUI: nvidia.gpcloudservice.com"
globalprotect connect --portal nvidia.gpcloudservice.com || {
    sudo systemctl restart gpd 
    globalprotect connect --portal nvidia.gpcloudservice.com 
}