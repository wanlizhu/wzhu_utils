#!/usr/bin/env bash

set -o pipefail 

NV_SOURCE=$HOME/sw
NV_BRANCH=r595_00
NV_TARGET_OS=linux
NV_TARGET_ARCH=$(uname -m | sed 's/x86_64/amd64/g')
NV_BUILD_TYPE=develop
NV_BUILD_JOBS=-j$(nproc)
NV_VERBOSE=
NV_OTHERS=

while (( $# )); do 
    case $1 in 
        x86|amd64|aarch64) NV_TARGET_ARCH=$1 ;;
        debug|release|develop) NV_BUILD_TYPE=$1 ;;
        -j[0-9]*) NV_BUILD_JOBS=$1 ;; 
        ppp) 
            $0 $NV_BUILD_JOBS $NV_BUILD_TYPE amd64 drivers dist || exit 1
            $0 $NV_BUILD_JOBS $NV_BUILD_TYPE x86 drivers dist || exit 1
            NV_OTHERS=post-process-packages 
            NV_BUILD_JOBS=-j1
        ;;
        *) break ;;
    esac 
    shift 
done 

if [[ ! -f makefile.nvmk ]]; then 
    cd $NV_SOURCE/branch/$NV_BRANCH || exit 1
fi 

source /etc/os-release 
if [[ $ID == ubuntu && ${VERSION_ID%%.*} -ge 24 ]]; then 
    if [[ $(sysctl -n kernel.apparmor_restrict_unprivileged_userns) != 0 ]]; then 
        sudo sysctl -w kernel.apparmor_restrict_unprivileged_unconfined=0
        sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
    fi 
fi 

function unix_build_nvmake() {
    $NV_SOURCE/tools/linux/unix-build/unix-build \
        --unshare-namespaces \
        --tools  $NV_SOURCE/tools \
        --devrel $NV_SOURCE/devrel/SDK/inc/GL \
        nvmake \
        NV_COLOR_OUTPUT=1 \
        NV_WARNINGS_AS_ERRORS=0 \
        NV_COMPRESS_THREADS=$(nproc) \
        NV_FAST_PACKAGE_COMPRESSION=1 \
        NV_STRIP=0 \
        NV_UNIX_CHECK_DEBUG_INFO=0 \
        NV_GUARDWORD=0 \
        NV_MANGLE_SYMBOLS=0 \
        NV_SYMBOLS=1 \
        NV_FRAME_POINTER=$([[ $NV_BUILD_TYPE == release ]] && echo 0 || echo 1) \
        NV_TRACE_CODE=$([[ $NV_BUILD_TYPE == release ]] && echo 0 || echo 1) \
        $NV_TARGET_OS $NV_TARGET_ARCH $NV_BUILD_TYPE $NV_BUILD_JOBS $NV_VERBOSE $NV_OTHERS "$@" 
}

if ! unix_build_nvmake; then
    NV_BUILD_JOBS=-j1
    NV_VERBOSE=verbose
    unix_build_nvmake || exit $?
fi 