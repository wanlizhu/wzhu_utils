#!/usr/bin/env bash
# NVIDIA-Linux-x86_64-590.48.01.run --ui=none --no-questions --accept-license --disable-nouveau --no-cc-version-check --install-libglvnd
set -o pipefail 

NV_SOURCE=$HOME/sw
NV_BRANCH=r595_00
NV_TARGET_OS=linux
NV_TARGET_ARCH=$(uname -m | sed 's/x86_64/amd64/g')
NV_TARGET_NAME=
NV_BUILD_TYPE=develop
NV_BUILD_JOBS=-j$(nproc)
NV_VERBOSE=

while (( $# )); do 
    case $1 in 
        x86|amd64|aarch64) NV_TARGET_ARCH=$1 ;;
        debug|release|develop) NV_BUILD_TYPE=$1 ;;
        -j[0-9]*) NV_BUILD_JOBS=$1 ;;
        sweep) NV_TARGET_NAME=sweep ;;
        ppp) 
            $0 x86 || exit 1
            $0 amd64 || exit 1
            $0 post-process-packages || exit 1
            exit 0
        ;;
        *) break ;;
    esac 
    shift 
done 

source /etc/os-release 
if [[ $ID == ubuntu && ${VERSION_ID%%.*} -ge 24 ]]; then 
    if [[ $(sysctl -n kernel.apparmor_restrict_unprivileged_userns) != 0 ]]; then 
        sudo sysctl -w kernel.apparmor_restrict_unprivileged_unconfined=0
        sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
    fi 
fi 

[[ ! -f makefile.nvmk ]] && cd $NV_SOURCE/branch/$NV_BRANCH
[[ -d drivers && -z $NV_TARGET_NAME ]] && NV_TARGET_NAME="drivers dist"

function unix_build_nvmake() {
    $NV_SOURCE/tools/linux/unix-build/unix-build \
        --unshare-namespaces \
        --tools  $NV_SOURCE/tools \
        --devrel $NV_SOURCE/devrel/SDK/inc/GL \
        nvmake \
        NV_COLOR_OUTPUT=1 \
        NV_COMPRESS_THREADS=$(nproc) \
        NV_STRIP=0 \
        NV_UNIX_CHECK_DEBUG_INFO=0 \
        NV_GUARDWORD=0 \
        NV_MANGLE_SYMBOLS=0 \
        NV_SYMBOLS=1 \
        NV_FRAME_POINTER=1 \
        NV_TRACE_CODE=$([[ $NV_BUILD_TYPE == release ]] && echo 0 || echo 1) \
        $NV_TARGET_OS $NV_TARGET_ARCH $NV_TARGET_NAME $NV_BUILD_TYPE $NV_BUILD_JOBS $NV_VERBOSE "$@" 
}

if ! unix_build_nvmake; then
    echo "Rebuild with option -j1"
    NV_BUILD_JOBS=-j1
    NV_VERBOSE=verbose
    unix_build_nvmake || exit $?
fi 