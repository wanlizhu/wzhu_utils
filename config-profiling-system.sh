#!/usr/bin/env bash
set -o pipefail 

# https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2getting__started.html
# https://nvidia.atlassian.net/wiki/spaces/linux/pages/2424735115/Wayland+Remote+Development

source /etc/os-release 
if [[ -z $(which sunshine) ]]; then 
    if [[ $ID == ubuntu && ${VERSION_ID%%.*} == 24 ]]; then 
        cd $HOME/Downloads
        wget https://github.com/LizardByte/Sunshine/releases/download/v2025.924.154138/sunshine-ubuntu-24.04-amd64.deb 
        sudo apt install -y miniupnpc
        sudo dpkg -i sunshine-ubuntu-24.04-amd64.deb
        sudo apt --fix-broken install
        sudo setcap cap_sys_admin+p $(readlink -f $(which sunshine))
    else 
        sudo apt install -y pkg-config libudev-dev libsystemd-dev libboost-all-dev libcurl4-openssl-dev libminiupnpc-dev nvidia-cuda-toolkit libdrm-dev libcap-dev libva-dev libva-drm2 libglib2.0-dev libpipewire-0.3-dev libnotify-dev libayatana-appindicator3-dev npm nodejs libevdev-dev doxygen graphviz libopus-dev  libgbm-dev libxcb-xfixes0-dev libpulse-dev libnuma-dev nfs-common screen nvidia-cuda-toolkit nvidia-cuda-toolkit-doc nvidia-cuda-toolkit-gcc nvidia-cuda-dev nvidia-cuda-gdb nvidia-cuda-samples 

        if [[ $(node -p 'typeof crypto.hash') == undefined ]]; then 
            sudo apt remove -y nodejs
            sudo apt autoremove -y
            sudo apt install -y ca-certificates curl gnupg
            curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
            sudo apt install -y nodejs
        fi 

        if [[ ! -d $HOME/Sunshine ]]; then 
            git clone --recursive https://github.com/LizardByte/Sunshine.git $HOME/Sunshine
            cd $HOME/Sunshine 
            git reset --hard v2026.209.34151
        fi 

        mkdir -p $HOME/Sunshine/build
        cd $HOME/Sunshine/build
        cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_DOCS=OFF || exit 1
        cmake --build . --config Release -j$(nproc) || exit 1
        sudo cmake --install . --config Release || exit 1
        sudo setcap cap_sys_admin+p $(readlink -f $(which sunshine))
    fi 
fi 

# install debug symbols packages *-dbgsym
sudo apt install -y ubuntu-dbgsym-keyring apt-transport-https ca-certificates apt-file
echo "Types: deb
URIs: http://ddebs.ubuntu.com/
Suites: $(lsb_release -cs) $(lsb_release -cs)-updates $(lsb_release -cs)-proposed 
Components: main restricted universe multiverse
Signed-by: /usr/share/keyrings/ubuntu-dbgsym-keyring.gpg" | sudo tee /etc/apt/sources.list.d/ddebs.sources
sudo apt update && sudo apt upgrade 
sudo apt install -y debian-goodies libc6-dbgsym libstdc++6-dbgsym linux-image-$(uname -r)-dbgsym

# install debug symbols for amd gpu drivers
sudo apt install -y libdrm2-dbgsym libdrm-amdgpu1-dbgsym mesa-vulkan-drivers-dbgsym libgl1-mesa-dri-dbgsym libgbm1-dbgsym linux-image-$(uname -r)-dbgsym 
dpkg -l | awk '$1=="ii"{print $2}' | sed -E 's/:(amd64|i386)$//' | grep -Ei '(amdgpu|amdvlk|radeon|radv|radeonsi|mesa|libdrm|vulkan|rocm|hip|hsa|opencl|xserver-xorg-video-amdgpu|xserver-xorg-video-radeon)' | sed -E 's/-dbgsym$//' | while read -r pkg; do
  sudo apt install -y "${pkg}-dbgsym"  
done

read -p "Install *-dbgsym for mapped shared objects of PID: " pid
if [[ ! -z $pid && -e /proc/$pid ]]; then 
    sudo awk '{print $6}' /proc/$pid/maps | grep -E '\.so(\.|$)' | sort -u |
    xargs -r -n1 dpkg -S 2>/dev/null | cut -d: -f1 | sort -u |
    sed 's/$/-dbgsym/' | while read -r pkg; do 
        sudo apt install -y $pkg 
    done 
fi 

# list gpu 
lspci -nnk | grep -EA3 'VGA|3D|Display'

# find blocking call
PID=$(pgrep -f "StrangeBrigade_Vulkan.exe" | head -n1)
ps -T -p $PID -o tid,comm,pcpu | sort -k3 -nr | head -n 20
read -p "Attach to render thread TID: " TID
sudo timeout 10s strace -ttT -p $TID -e trace=epoll_wait,epoll_pwait,poll,ppoll,futex,clock_nanosleep,nanosleep,recvmsg,sendmsg,read,write,ioctl -o /tmp/strace_render_thread.txt
grep -oE '<[0-9]+\.[0-9]+>' /tmp/strace_render_thread.txt | tr -d '<>' | sort -n | tail -n 20

# steam launch options
MANGOHUD=1 MANGOHUD_CONFIG="position=top-right" PROTON_LOG=1 DXVK_HUD=devinfo,fps VKD3D_DEBUG=info VKD3D_LOG_FILE=/home/wanliz/strange-brigade-vkd3d-logs.txt VK_INSTANCE_LAYERS=VK_LAYER_LUNARG_api_dump VK_API_DUMP_FILE=/home/wanliz/strange-brigade-vk-apidump.txt VK_API_DUMP_OUTPUT_FORMAT=text  %command%

# steam launch options -- wrapper script [failed to launch game]
gnome-terminal -- bash -lc '$HOME/wanliz_tools/profiling/generate-flamegraph.sh %command%'

# flamegraph by pmp
sudo mkdir -p /mnt/linuxqa 
sudo mount -t nfs linuxqa.nvidia.com:/storage/people /mnt/linuxqa
/mnt/linuxqa/mkorenchan/tools/profiling/pmp %command% > /home/wanliz/strange_brigade_pmp.data 
cat /home/wanliz/strange_brigade_pmp.data  | /mnt/linuxqa/mkorenchan/tools/profiling/pmp2folded | /mnt/linuxqa/mkorenchan/tools/profiling/genflamegraph > strange_brigade_pmp.svg 

cd $HOME 
loginctl list-sessions
export XDG_SESSION_TYPE=wayland
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY="$(basename "$(ls -1 "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | head -n1)")"
while IFS= read -r kv; do 
    export "$kv"
    echo "export $kv"
done < <(systemctl --user show-environment)
sudo setcap cap_sys_admin+p $(readlink -f $(which sunshine))
screen -S sunshine -dm bash -lic "sunshine" 
sleep 1
pgrep -a sunshine
echo "1) Redirect local port 47990 to remote:"
echo "   >> ssh -L 47990:127.0.0.1:47990 local-wanliz@10.176.207.76"
echo "2) Configure in Web UI: https://localhost:47990"

# show steam game proc
pgrep -aP 1234
pstree -aspT 1234

# passwordless sudo 
if ! sudo -n true 2>/dev/null; then 
    echo "$(id -un) ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers.d/99-$(id -un)-nopasswd >/dev/null
    sudo chmod 0440 /etc/sudoers.d/99-$(id -un)-nopasswd
fi 