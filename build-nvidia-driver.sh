#!/usr/bin/env bash

set -o pipefail 

function unix_build_nvmake() {
    if [[ ! -f makefile.nvmk ]]; then 
        echo "The current dir has no makefile.nvmk"
        echo "Aborting"
        return 1
    fi 

    source /etc/os-release 
    if [[ $ID == ubuntu && ${VERSION_ID%%.*} -ge 24 ]]; then 
        if [[ $(sysctl -n kernel.apparmor_restrict_unprivileged_userns) != 0 ]]; then 
            sudo sysctl -w kernel.apparmor_restrict_unprivileged_unconfined=0
            sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
        fi 
    fi 

    local root=$1
    local branch=$2 
    local arch=$3
    local buildtype=$4
    shift 4
    local unix_build_args=(
        --unshare-namespaces 
        --tools  $root/tools 
        --devrel $root/devrel/SDK/inc/GL
    )
    # Exclude raytracing (rtcore) to avoid linker "Memory exhausted" when building libnvvm/cicc.
    # Build module name is "raytracing"; "rtcore" is the SUBDIR name and is not a valid exclude.
    local exclude_build_modules=(
        raytracing optix # for raytracing 
        compiler         # for openCL
        gpgpu gpgpucomp gpgpudbg # for cuda
    )
    local nvmake_args=(
        NV_COLOR_OUTPUT=1
        NV_COMPRESS_THREADS=$(nproc)
        NV_FAST_PACKAGE_COMPRESSION=1
        NV_GUARDWORD=0
        NV_WARNINGS_AS_ERRORS=
        NV_STRIP=0
        NV_SYMBOLS=1 
        NV_MANGLE_SYMBOLS=0
        NV_KEEP_UNSTRIPPED_BINARIES=1 
        NV_LTCG=0  
        NV_UNIX_CHECK_DEBUG_INFO=0
    )
    if (( ${#exclude_build_modules[@]} != 0 )); then
        nvmake_args+=("NV_EXCLUDE_BUILD_MODULES=${exclude_build_modules[*]}")
    fi 
    if [[ $buildtype == release ]]; then 
        nvmake_args+=( 
            NV_SEPARATE_DEBUG_INFO=1 
        )
    else
        nvmake_args+=(
            NV_FRAME_POINTER=1
            NV_TRACE_CODE=1
        )
    fi 

    ionice -c2 nice $root/tools/linux/unix-build/unix-build "${unix_build_args[@]}" nvmake "${nvmake_args[@]}" linux $arch $buildtype "$@" || {
        # retry with -j1 (to stop at the first error) and verbose options
        ionice -c2 nice $root/tools/linux/unix-build/unix-build "${unix_build_args[@]}" nvmake "${nvmake_args[@]}" linux $arch $buildtype "$@" verbose -j1 || return 1
    }
}

function post_build_install_dso() {
    local root=$1
    local branch=$2
    local arch=$3
    local buildtype=$4
    local workdir=$5
    local name=$6 
    shift 6
    local nvidia_module_version=$(modinfo nvidia | grep ^version | awk '{print $2}')
    local nvidia_source_version=$(grep '^#define NV_VERSION_STRING' $root/branch/$branch/drivers/common/inc/nvUnixVersion.h  | awk '{print $3}' | sed 's/"//g')

    if [[ $nvidia_module_version == $nvidia_source_version ]]; then 
        if [[ -f $workdir/_out/Linux_${arch}_${buildtype}/$name ]]; then 
            if [[ ! -f /lib/$(uname -m)-linux-gnu/$name.${nvidia_source_version}.backup ]]; then 
                sudo cp /lib/$(uname -m)-linux-gnu/$name.$nvidia_source_version /lib/$(uname -m)-linux-gnu/$name.${nvidia_source_version}.backup
            fi 
            sudo cp -v --remove-destination $workdir/_out/Linux_${arch}_${buildtype}/$name /lib/$(uname -m)-linux-gnu/$name.$nvidia_source_version && echo "Replaced /lib/$(uname -m)-linux-gnu/$name.$nvidia_source_version"
            return 0
        else
            return 1
        fi 
    else
        echo "Nvidia module version ($nvidia_module_version) and source version ($nvidia_source_version) doesn't match, replacement skipped"
        return 1
    fi 
}

if [[ -f makefile.nvmk ]]; then
    if [[ -d drivers ]]; then 
        NV_SOURCE=$(realpath $(pwd)/../..)
    elif [[ -f opengl.nvmk ]]; then 
        NV_SOURCE=$(realpath $(pwd)/../../../..)
    else
        echo "cd to branch root first"
        echo "Aborting"
        exit 1
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

while (( $# )); do 
    case $1 in 
        x86|amd64|aarch64) NV_TARGET_ARCH=$1 ;;
        debug|release|develop) NV_BUILD_TYPE=$1 ;;
        ppp)
            shift  
            unix_build_nvmake $NV_SOURCE $NV_BRANCH amd64 $NV_BUILD_TYPE drivers dist -j$(nproc) &&
            unix_build_nvmake $NV_SOURCE $NV_BRANCH x86   $NV_BUILD_TYPE drivers dist -j$(nproc) &&
            unix_build_nvmake $NV_SOURCE $NV_BRANCH amd64 $NV_BUILD_TYPE post-process-packages 
            exit
        ;;
        opengl)
            shift 
            cd $NV_SOURCE/branch/$NV_BRANCH/drivers/OpenGL && 
            unix_build_nvmake $NV_SOURCE $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE "$@" &&
            cd $NV_SOURCE/branch/$NV_BRANCH/drivers/OpenGL/win/glx &&
            unix_build_nvmake $NV_SOURCE $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE "$@" &&
            cd $NV_SOURCE/branch/$NV_BRANCH/drivers/OpenGL/win/egl/glsi &&
            unix_build_nvmake $NV_SOURCE $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE "$@" &&
            cd $NV_SOURCE/branch/$NV_BRANCH/drivers/OpenGL/win/egl/build &&
            unix_build_nvmake $NV_SOURCE $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE "$@" &&
            cd $NV_SOURCE/branch/$NV_BRANCH/drivers/unix/libglvnd/NVIDIA &&
            unix_build_nvmake $NV_SOURCE $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE "$@" &&
            cd $NV_SOURCE/branch/$NV_BRANCH/drivers && 
            unix_build_nvmake $NV_SOURCE $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE "$@" NV_BUILD_MODULES=egl && {
                read -p "Install Nvidia OpenGL UMD(s) to local system? [Y/n]: " install_umds
                if [[ -z $install_umds || $install_umds == y ]]; then 
                    echo -e "\nNvidia OpenGL UMD(s) installed:" >/tmp/nvidia-umds.log 
                    post_build_install_dso $NV_SOURCE $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $NV_SOURCE/branch/$NV_BRANCH/drivers/OpenGL libnvidia-glcore.so && echo "    - libnvidia-glcore.so" >>/tmp/nvidia-umds.log
                    post_build_install_dso $NV_SOURCE $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $NV_SOURCE/branch/$NV_BRANCH/drivers/OpenGL/win/unix/tls/Linux-elf libnvidia-tls.so && echo "    - libnvidia-tls.so" >>/tmp/nvidia-umds.log
                    post_build_install_dso $NV_SOURCE $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $NV_SOURCE/branch/$NV_BRANCH/drivers/OpenGL/win/egl/build libnvidia-eglcore.so && echo "    - libnvidia-eglcore.so" >>/tmp/nvidia-umds.log
                    post_build_install_dso $NV_SOURCE $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $NV_SOURCE/branch/$NV_BRANCH/drivers/OpenGL/win/egl/glsi libnvidia-glsi.so && echo "    - libnvidia-glsi.so" >>/tmp/nvidia-umds.log 
                    post_build_install_dso $NV_SOURCE $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $NV_SOURCE/branch/$NV_BRANCH/drivers/OpenGL/win/glx/lib libGLX_nvidia.so && echo "    - libGLX_nvidia.so" >>/tmp/nvidia-umds.log 
                    post_build_install_dso $NV_SOURCE $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $NV_SOURCE/branch/$NV_BRANCH/drivers/OpenGL/win/glx/lib libGLX.so && echo "    - libGLX.so" >>/tmp/nvidia-umds.log # optional
                    post_build_install_dso $NV_SOURCE $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $NV_SOURCE/branch/$NV_BRANCH/drivers/khronos/egl/egl libEGL_nvidia.so && echo "    - libEGL_nvidia.so" >>/tmp/nvidia-umds.log
                    post_build_install_dso $NV_SOURCE $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $NV_SOURCE/branch/$NV_BRANCH/drivers/khronos/egl/egl libEGL.so && echo "    - libEGL.so" >>/tmp/nvidia-umds.log # optional 
                    post_build_install_dso $NV_SOURCE $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $NV_SOURCE/branch/$NV_BRANCH/drivers/khronos/opengles/gles2 libGLESv2_nvidia.so && echo "    - libGLESv2_nvidia.so" >>/tmp/nvidia-umds.log
                    post_build_install_dso $NV_SOURCE $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $NV_SOURCE/branch/$NV_BRANCH/drivers/khronos/opengles/gles2 libGLESv2.so && echo "    - libGLESv2.so" >>/tmp/nvidia-umds.log # optional 
                    cat /tmp/nvidia-umds.log 
                else
                    echo -e "\nNvidia OpenGL UMD(s) compiled:"
                    echo "    - libnvidia-glcore.so"
                    echo "    - libnvidia-tls.so"
                    echo "    - libnvidia-eglcore.so"
                    echo "    - libnvidia-glsi.so"
                    if [[ -f $NV_SOURCE/branch/$NV_BRANCH/drivers/OpenGL/win/glx/lib/_out/Linux_${NV_TARGET_ARCH}_${NV_BUILD_TYPE}/libGLX_nvidia.so ]]; then 
                        echo "    - libGLX_nvidia.so"
                        echo "    - libEGL_nvidia.so"
                        echo "    - libGLESv2_nvidia.so"
                    else
                        echo "    - libGLX.so"
                        echo "    - libEGL.so"
                        echo "    - libGLESv2.so"
                    fi 
                fi 
            }
            exit 
        ;;
        restore)
            shift 
            sudo find /lib/$(uname -m)-linux-gnu -type f -name '*.backup' -exec bash -c '
                for path; do 
                    mv -f $path ${path%.backup}
                    echo "Restored ${path%.backup}"
                done 
            ' bash {} +
            exit 
        ;;
        info)
            shift 
            nvidia_module_version=$(modinfo nvidia | grep ^version | awk '{print $2}')
            echo "Nvidia module version: $nvidia_module_version"
            for branch in $NV_SOURCE/branch/*; do 
                nvidia_source_version=$(grep '^#define NV_VERSION_STRING' $branch/drivers/common/inc/nvUnixVersion.h 2>/dev/null | awk '{print $3}' | sed 's/"//g')
                pending_changes=$(p4 opened $branch/... 2>/dev/null | grep 'change [0-9]')
                pending_changes=$([[ -z $pending_changes ]] && echo || echo "(pending changes)")
                echo "    - branch/$(basename $branch): $nvidia_source_version $pending_changes"
            done 
            exit 
        ;;
        sync)
            shift 
            for cl in $(p4 changes -s pending -c $(p4 client -o | awk '/^Client:/ { print $2 }') | awk '{ print $2 }'); do
                p4 opened -c $cl 2>/dev/null | grep -q . && p4 shelve -f -c $cl && p4 revert -c $cl //... && echo "Shelved pending change $cl"
            done
            cl=$(p4 change -o | sed 's/<enter description here>/restore workspace/' | p4 change -i | awk '/Change/ { print $2 }')
            echo "Reconciling local edits/deletes into CL $cl"
            p4 reconcile -c $cl -e -m $(pwd)/...
            p4 reconcile -c $cl -d $(pwd)/...
            if  p4 opened -c $cl 2>/dev/null | grep -q .; then
                p4 shelve -f -c $cl  
                p4 revert -c $cl //...
            else
                echo "CL $cl is empty, removing it"
                p4 change -d $cl  
            fi 
            p4 clean -a -I $(pwd)/... 
            p4 sync $(pwd)/... 
            for subdir in $(find $NV_SOURCE -mindepth 1 -maxdepth 1 -type d -print); do 
                [[ $(basename $subdir) == branch ]] && continue 
                p4 sync $subdir/... 
            done 
            exit 
        ;;
        *) break ;;
    esac 
    shift 
done 

unix_build_nvmake $NV_SOURCE $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE "$@" 
