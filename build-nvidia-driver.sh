#!/usr/bin/env bash

set -o pipefail 

function unix_build_nvmake() {
    local root=$1
    local arch=$2 
    local buildtype=$3
    local buildjobs=$4
    shift 4
    $root/tools/linux/unix-build/unix-build \
        --unshare-namespaces \
        --tools  $root/tools \
        --devrel $root/devrel/SDK/inc/GL \
        nvmake \
        NV_COLOR_OUTPUT=1 \
        NV_GUARDWORD= \
        NV_WARNINGS_AS_ERRORS= \
        NV_COMPRESS_THREADS=$(nproc) \
        NV_FAST_PACKAGE_COMPRESSION=zstd \
        NV_STRIP=0 \
        NV_UNIX_CHECK_DEBUG_INFO=0 \
        NV_MANGLE_SYMBOLS= \
        NV_SYMBOLS=1 \
        NV_SECURITY=0 \
        NV_LTCG=0 \
        NV_FRAME_POINTER=$([[ $buildtype == release ]] && echo 0 || echo 1) \
        NV_TRACE_CODE=$([[ $buildtype == release ]] && echo 0 || echo 1) \
        linux $arch $buildtype $buildjobs "$@" && return 0
    [[ $buildjobs == -j1 && $1 == verbose ]] && return 1
    unix_build_nvmake $root $arch $buildtype -j1 verbose
}

if [[ -f makefile.nvmk ]]; then
    if [[ -d drivers ]]; then 
        NV_SOURCE=$(realpath $(pwd)/../..)
    elif [[ -f opengl.nvmk ]]; then 
        NV_SOURCE=$(realpath $(pwd)/../../../..)
    fi 
elif [[ -d $HOME/wzhu_p4sw ]]; then 
    NV_SOURCE=$HOME/wzhu_p4sw
else
    echo "~/wzhu_p4sw/ doesn't exist"
    echo "Aborting"
    exit 1
fi 
NV_BRANCH=r595_00
NV_TARGET_ARCH=$(uname -m | sed 's/x86_64/amd64/g')
NV_BUILD_TYPE=develop
NV_BUILD_JOBS=-j$(nproc)

while (( $# )); do 
    case $1 in 
        x86|amd64|aarch64) NV_TARGET_ARCH=$1 ;;
        debug|release|develop) NV_BUILD_TYPE=$1 ;;
        -j[0-9]*) NV_BUILD_JOBS=$1 ;; 
        ppp) 
            unix_build_nvmake $NV_SOURCE amd64 $NV_BUILD_TYPE $NV_BUILD_JOBS &&
            unix_build_nvmake $NV_SOURCE x86   $NV_BUILD_TYPE $NV_BUILD_JOBS &&
            unix_build_nvmake $NV_SOURCE amd64 $NV_BUILD_TYPE -j1 post-process-packages 
            exit
        ;;
        restore)
            sudo find /lib/$(uname -m)-linux-gnu -type f -name '*.backup' -exec bash -c '
                for path; do 
                    mv -f $path ${path%.backup}
                    echo "Restored ${path%.backup}"
                done 
            ' bash {} +
            exit 
        ;;
        info)
            nvidia_module_version=$(modinfo nvidia | grep ^version | awk '{print $2}')
            echo "Nvidia module version: $nvidia_module_version"
            for branch in $NV_SOURCE/branch/*; do 
                nvidia_source_version=$(grep '^#define NV_VERSION_STRING' $branch/drivers/common/inc/nvUnixVersion.h 2>/dev/null | awk '{print $3}' | sed 's/"//g')
                pending_changes=$(p4 opened $branch/... 2>/dev/null | grep -q 'change [0-9]')
                pending_changes=$([[ -z $pending_changes ]] && echo || echo "(pending changes)")
                echo "    - branch/$(basename $branch): $nvidia_source_version $pending_changes"
            done 
            exit 
        ;;
        *) break ;;
    esac 
    shift 
done 

if [[ ! -f makefile.nvmk ]]; then 
    echo "The current dir has no makefile.nvmk"
    echo "Aborting"
    exit 1
fi 

source /etc/os-release 
if [[ $ID == ubuntu && ${VERSION_ID%%.*} -ge 24 ]]; then 
    if [[ $(sysctl -n kernel.apparmor_restrict_unprivileged_userns) != 0 ]]; then 
        sudo sysctl -w kernel.apparmor_restrict_unprivileged_unconfined=0
        sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
    fi 
fi 

unix_build_nvmake $NV_SOURCE $NV_TARGET_ARCH $NV_BUILD_TYPE $NV_BUILD_JOBS "$@" || exit 1
nvidia_module_version=$(modinfo nvidia | grep ^version | awk '{print $2}')
nvidia_source_version=$(grep '^#define NV_VERSION_STRING' $NV_SOURCE/branch/$NV_BRANCH/drivers/common/inc/nvUnixVersion.h  | awk '{print $3}' | sed 's/"//g')

if [[ $nvidia_module_version == $nvidia_source_version ]]; then 
    if [[ -f opengl.nvmk && -e /lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.$nvidia_source_version ]]; then 
        read -p "Replace libnvidia-glcore.so.$nvidia_source_version on local system? [Y/n]: " replace
        if [[ -z $replace || $replace == y ]]; then 
            if [[ ! -f /lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.${nvidia_source_version}.backup ]]; then 
                sudo cp /lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.$nvidia_source_version /lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.${nvidia_source_version}.backup
                echo "Generated /lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.${nvidia_source_version}.backup"
            fi 
            sudo cp -v --remove-destination _out/Linux_${NV_TARGET_ARCH}_${NV_BUILD_TYPE}/libnvidia-glcore.so /lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.$nvidia_source_version 
        fi 
    fi 
fi 