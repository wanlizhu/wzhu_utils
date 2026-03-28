#!/usr/bin/env bash
set -o pipefail 

unix_build_nvmake() {
    if [[ ! -f makefile.nvmk ]]; then 
        echo "The current dir has no makefile.nvmk"
        echo "Aborting"
        return 1
    fi 

    local os_id=$(source /etc/os-release && echo $ID)
    local os_version_id=$(source /etc/os-release && echo $VERSION_ID)
    if [[ $os_id == ubuntu && ${os_version_id%%.*} -ge 24 ]]; then 
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
        tileiraslib # cuda tile IR codegen
    )
    #exclude_build_modules=() # uncomment to disable it
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

    echo "$root/tools/linux/unix-build/unix-build ${unix_build_args[@]} nvmake ${nvmake_args[@]} linux $arch $buildtype $@"
    echo "Will run this command in 3 seconds ..." && sleep 3
    time ionice -c2 nice $root/tools/linux/unix-build/unix-build "${unix_build_args[@]}" nvmake "${nvmake_args[@]}" linux $arch $buildtype "$@"  2>/tmp/nvmake.error || {
        cat /tmp/nvmake.error | grep -iv 'warning:'
        exit 1
    }
}

post_build_install_dso() {
    local targethost=$1
    local root=$2
    local branch=$3
    local arch=$4
    local buildtype=$5
    local workdir=$6
    local name=$7
    shift 7 
    local system_arch=${arch/amd64/x86_64}
    local nvidia_source_version=$(grep '^#define NV_VERSION_STRING' $root/branch/$branch/drivers/common/inc/nvUnixVersion.h  | awk '{print $3}' | sed 's/"//g')

    if [[ $targethost == localhost ]]; then 
        local nvidia_module_version=$(modinfo nvidia | grep ^version | awk '{print $2}')    
        if [[ $nvidia_module_version == $nvidia_source_version ]]; then 
            if [[ -f $workdir/_out/Linux_${arch}_${buildtype}/$name && $(uname -m) == $system_arch ]]; then 
                if [[ ! -f /lib/${system_arch}-linux-gnu/$name.${nvidia_source_version}.backup ]]; then 
                    sudo cp /lib/${system_arch}-linux-gnu/$name.$nvidia_source_version /lib/${system_arch}-linux-gnu/$name.${nvidia_source_version}.backup
                fi 
                sudo cp -v --remove-destination $workdir/_out/Linux_${arch}_${buildtype}/$name /lib/${system_arch}-linux-gnu/$name.$nvidia_source_version && return 0
            fi 
        else
            echo "Nvidia module version ($nvidia_module_version) and source version ($nvidia_source_version) doesn't match, replacement skipped"
        fi 
    else
        local nvidia_module_version=$(ssh $targethost 'modinfo nvidia | grep ^version | awk "{print \$2}"')
        local remote_arch=$(ssh $targethost uname -m)
        if [[ $nvidia_module_version == $nvidia_source_version ]]; then 
            if [[ -f $workdir/_out/Linux_${arch}_${buildtype}/$name && $remote_arch == $system_arch ]]; then 
                if ! ssh $targethost "[[ -f /lib/${system_arch}-linux-gnu/$name.${nvidia_source_version}.backup ]]"; then 
                    ssh -t $targethost "sudo cp /lib/${system_arch}-linux-gnu/$name.$nvidia_source_version /lib/${system_arch}-linux-gnu/$name.${nvidia_source_version}.backup"
                fi 
                rsync -Pah $workdir/_out/Linux_${arch}_${buildtype}/$name $targethost:/tmp/$name && ssh -t $targethost "sudo cp -v --remove-destination /tmp/$name /lib/${system_arch}-linux-gnu/$name.$nvidia_source_version" && return 0 
            fi 
        else
            echo "Nvidia module version ($nvidia_module_version on $targethost) and source version ($nvidia_source_version) doesn't match, replacement skipped"
        fi 
    fi 
    return 1
}

detect_source_root() {
    if [[ -f makefile.nvmk ]]; then
        if [[ -d drivers ]]; then 
            P4SW_ROOT=$(realpath $(pwd)/../..)
        elif [[ -f opengl.nvmk ]]; then 
            P4SW_ROOT=$(realpath $(pwd)/../../../..)
        fi 
    fi 

    if [[ -z $P4SW_ROOT ]]; then 
        if [[ -d $HOME/wzhu_p4sw ]]; then 
            P4SW_ROOT=$HOME/wzhu_p4sw
        else 
            echo "~/wzhu_p4sw/ doesn't exist"
            echo "Aborting"
            exit 1
        fi 
    fi 

    if [[ ! -f makefile.nvmk ]]; then
        if [[ -z $NV_BRANCH ]]; then 
            cd $P4SW_ROOT
        else 
            cd $P4SW_ROOT/branch/$NV_BRANCH
        fi 
    fi 

    pwd 
} 

NV_BRANCH=bugfix_main
NV_TARGET_ARCH=$(uname -m | sed 's/x86_64/amd64/g')
NV_BUILD_TYPE=develop
POST_BUILD_INSTALL=

while (( $# )); do 
    case $1 in 
        install=*) POST_BUILD_INSTALL=${1#*=} ;;
        branch=*) NV_BRANCH=${1#*=} ;;
        x86|amd64|aarch64) NV_TARGET_ARCH=$1 ;;
        debug|release|develop) NV_BUILD_TYPE=$1 ;;
        ppp)
            shift  
            detect_source_root || exit 1
            unix_build_nvmake $P4SW_ROOT $NV_BRANCH amd64 $NV_BUILD_TYPE drivers dist -j$(nproc) "$@" &&
            unix_build_nvmake $P4SW_ROOT $NV_BRANCH x86   $NV_BUILD_TYPE drivers dist -j$(nproc) "$@" &&
            unix_build_nvmake $P4SW_ROOT $NV_BRANCH amd64 $NV_BUILD_TYPE post-process-packages "$@" && {
                run_installer=no
                if [[ $POST_BUILD_INSTALL == 1 ]]; then 
                    read -p "Run Nvidia drivers installer now? [Y/n]: " run_installer
                fi 
                if [[ -z $run_installer || $run_installer == [Yy] ]]; then 
                    nvidia_source_version=$(grep '^#define NV_VERSION_STRING' $P4SW_ROOT/branch/$NV_BRANCH/drivers/common/inc/nvUnixVersion.h  | awk '{print $3}' | sed 's/"//g')
                    nvidia-install-driver.sh $P4SW_ROOT/branch/$NV_BRANCH/_out/Linux_${NV_TARGET_ARCH}_${NV_BUILD_TYPE}/NVIDIA-Linux-$(uname -m)-$nvidia_source_version.run 
                fi 
            }
            exit
        ;;
        dist)
            shift  
            detect_source_root || exit 1
            unix_build_nvmake $P4SW_ROOT $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE drivers dist -j$(nproc) "$@" && {
                run_installer=no
                if [[ $POST_BUILD_INSTALL == 1 ]]; then 
                    read -p "Run Nvidia drivers installer now? [Y/n]: " run_installer
                fi 
                if [[ -z $run_installer || $run_installer == [Yy] ]]; then 
                    nvidia_source_version=$(grep '^#define NV_VERSION_STRING' $P4SW_ROOT/branch/$NV_BRANCH/drivers/common/inc/nvUnixVersion.h  | awk '{print $3}' | sed 's/"//g')
                    nvidia-install-driver.sh $P4SW_ROOT/branch/$NV_BRANCH/_out/Linux_${NV_TARGET_ARCH}_${NV_BUILD_TYPE}/NVIDIA-Linux-$(uname -m)-$nvidia_source_version-internal.run 
                fi 
            }
            exit
        ;;
        opengl)
            shift 
            detect_source_root || exit 1
            cd $P4SW_ROOT/branch/$NV_BRANCH/drivers/OpenGL && 
            unix_build_nvmake $P4SW_ROOT $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE "$@" &&
            cd $P4SW_ROOT/branch/$NV_BRANCH/drivers/OpenGL/win/glx &&
            unix_build_nvmake $P4SW_ROOT $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE "$@" &&
            cd $P4SW_ROOT/branch/$NV_BRANCH/drivers/OpenGL/win/egl/glsi &&
            unix_build_nvmake $P4SW_ROOT $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE "$@" &&
            cd $P4SW_ROOT/branch/$NV_BRANCH/drivers/OpenGL/win/egl/build &&
            unix_build_nvmake $P4SW_ROOT $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE "$@" &&
            cd $P4SW_ROOT/branch/$NV_BRANCH/drivers/unix/libglvnd/NVIDIA &&
            unix_build_nvmake $P4SW_ROOT $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE "$@" &&
            cd $P4SW_ROOT/branch/$NV_BRANCH/drivers && 
            unix_build_nvmake $P4SW_ROOT $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE "$@" NV_BUILD_MODULES=egl && {
                install_umds=no
                if [[ $POST_BUILD_INSTALL == 1 ]]; then 
                    read -p "Install Nvidia OpenGL UMD(s) now? [Y/n]: " install_umds
                fi 
                if [[ -z $install_umds || $install_umds == [Yy] ]]; then 
                    read -e -i $([[ -f /tmp/remote ]] && cat /tmp/remote || echo localhost) -p "Target host IP: " target_host 
                    target_host=${target_host:-localhost}
                    echo $target_host >/tmp/remote 
                    echo -e "\nNvidia OpenGL UMD(s) installed to $target_host:" >/tmp/nvidia-umds.log 
                    post_build_install_dso $target_host $P4SW_ROOT $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $P4SW_ROOT/branch/$NV_BRANCH/drivers/OpenGL libnvidia-glcore.so && echo "    - libnvidia-glcore.so" >>/tmp/nvidia-umds.log
                    post_build_install_dso $target_host $P4SW_ROOT $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $P4SW_ROOT/branch/$NV_BRANCH/drivers/OpenGL/win/unix/tls/Linux-elf libnvidia-tls.so && echo "    - libnvidia-tls.so" >>/tmp/nvidia-umds.log
                    post_build_install_dso $target_host $P4SW_ROOT $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $P4SW_ROOT/branch/$NV_BRANCH/drivers/OpenGL/win/egl/build libnvidia-eglcore.so && echo "    - libnvidia-eglcore.so" >>/tmp/nvidia-umds.log
                    post_build_install_dso $target_host $P4SW_ROOT $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $P4SW_ROOT/branch/$NV_BRANCH/drivers/OpenGL/win/egl/glsi libnvidia-glsi.so && echo "    - libnvidia-glsi.so" >>/tmp/nvidia-umds.log 
                    post_build_install_dso $target_host $P4SW_ROOT $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $P4SW_ROOT/branch/$NV_BRANCH/drivers/OpenGL/win/glx/lib libGLX_nvidia.so && echo "    - libGLX_nvidia.so" >>/tmp/nvidia-umds.log 
                    post_build_install_dso $target_host $P4SW_ROOT $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $P4SW_ROOT/branch/$NV_BRANCH/drivers/OpenGL/win/glx/lib libGLX.so && echo "    - libGLX.so" >>/tmp/nvidia-umds.log # optional
                    post_build_install_dso $target_host $P4SW_ROOT $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $P4SW_ROOT/branch/$NV_BRANCH/drivers/khronos/egl/egl libEGL_nvidia.so && echo "    - libEGL_nvidia.so" >>/tmp/nvidia-umds.log
                    post_build_install_dso $target_host $P4SW_ROOT $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $P4SW_ROOT/branch/$NV_BRANCH/drivers/khronos/egl/egl libEGL.so && echo "    - libEGL.so" >>/tmp/nvidia-umds.log # optional 
                    post_build_install_dso $target_host $P4SW_ROOT $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $P4SW_ROOT/branch/$NV_BRANCH/drivers/khronos/opengles/gles2 libGLESv2_nvidia.so && echo "    - libGLESv2_nvidia.so" >>/tmp/nvidia-umds.log
                    post_build_install_dso $target_host $P4SW_ROOT $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE $P4SW_ROOT/branch/$NV_BRANCH/drivers/khronos/opengles/gles2 libGLESv2.so && echo "    - libGLESv2.so" >>/tmp/nvidia-umds.log # optional 
                    cat /tmp/nvidia-umds.log 
                else
                    echo -e "\nNvidia OpenGL UMD(s) compiled:"
                    echo "    - libnvidia-glcore.so"
                    echo "    - libnvidia-tls.so"
                    echo "    - libnvidia-eglcore.so"
                    echo "    - libnvidia-glsi.so"
                    if [[ -f $P4SW_ROOT/branch/$NV_BRANCH/drivers/OpenGL/win/glx/lib/_out/Linux_${NV_TARGET_ARCH}_${NV_BUILD_TYPE}/libGLX_nvidia.so ]]; then 
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
            detect_source_root || exit 1
            sudo find /lib/$(uname -m)-linux-gnu -type f -name '*.backup' -exec bash -c '
                for path; do 
                    mv -f "$path" "${path%.backup}"
                    echo "Restored ${path%.backup}"
                done 
            ' bash {} +
            exit 
        ;;
        info)
            shift 
            detect_source_root || exit 1
            nvidia_module_version=$(modinfo nvidia | grep ^version | awk '{print $2}')
            echo "Nvidia module version: $nvidia_module_version"
            shopt -s nullglob
            for branch_path in $P4SW_ROOT/branch/*; do 
                nvidia_source_version=$(grep '^#define NV_VERSION_STRING' $branch_path/drivers/common/inc/nvUnixVersion.h 2>/dev/null | awk '{print $3}' | sed 's/"//g')
                pending_changes=$(p4 opened $branch_path/... 2>/dev/null | grep 'change [0-9]')
                pending_changes=$([[ -z $pending_changes ]] && echo || echo "(pending changes)")
                echo "    - branch/$(basename $branch_path): $nvidia_source_version $pending_changes"
            done 
            shopt -u nullglob
            exit 
        ;;
        sync)
            shift 
            detect_source_root || exit 1
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
            while IFS= read -r subdir; do
                [[ $(basename $subdir) == branch ]] && continue 
                p4 sync $subdir/... 
            done < <(find $P4SW_ROOT -mindepth 1 -maxdepth 1 -type d -print)
            exit 
        ;;
        *) break ;;
    esac 
    shift 
done 

detect_source_root || exit 1
unix_build_nvmake $P4SW_ROOT $NV_BRANCH $NV_TARGET_ARCH $NV_BUILD_TYPE "$@" 
