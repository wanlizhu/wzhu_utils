#!/usr/bin/env bash
set -o pipefail

run_strangebrigade_benchmark() {
    local BENCHMARK_RESULT_DIR="$HOME/.steam/steam/steamapps/compatdata/312670/pfx/drive_c/users/steamuser/Documents/StrangeBrigade_Benchmark"
    local GRAPHICS_CONFIG_FILE="$HOME/.steam/steam/steamapps/compatdata/312670/pfx/drive_c/users/steamuser/Local Settings/Application Data/Strange Brigade/GraphicsOptions.ini"
    local GRAPHICS_CONFIG_LIST=(
        '[Display Settings]'
        'D3D12 = 0'
        'Resolution_Width = 1920'
        'Resolution_Height = 1080'
        'RenderScale = 1.000000'
        'Windowed = 0'
        'MotionBlur = 1'
        'AmbientOcclusion = 1'
        'VSync = 0'
        'ReduceMouseLag = 0'
        'AsyncCompute = 1'
        'Tessellation = 1'
        'TextureDetail = 3'
        'ShadowDetail = 3'
        'AntiAliasing = 4'
        'DrawDistance = 3'
        'AnisotropicFiltering = 16'
        'SSReflectionsQuality = 3'
        'Brightness = 0.500000'
        'ObscuranceFields = 1'
        'ReverbQuality = 1'
        'HDR = 0'
    )

    [[ -f "$GRAPHICS_CONFIG_FILE" ]] && cp "$GRAPHICS_CONFIG_FILE" "$GRAPHICS_CONFIG_FILE.backup"
    printf '%s\n' "${GRAPHICS_CONFIG_LIST[@]}" > "$GRAPHICS_CONFIG_FILE"

    [[ -d "$BENCHMARK_RESULT_DIR" ]] && find "$BENCHMARK_RESULT_DIR" -mindepth 1 -delete 
    steam -applaunch 312670 -benchmark &>/dev/null &

    start="$(date +%H:%M:%S)"
    while ! pgrep -f StrangeBrigade_ > /dev/null; do
        printf "\r[%s -> %s] Wait for game process to appear ..." "$start" "$(date +%H:%M:%S)"
        sleep 1
    done
    echo 
    start="$(date +%H:%M:%S)"
    while pgrep -f StrangeBrigade_ > /dev/null; do
        printf "\r[%s -> %s] Wait for game process to finish ..." "$start" "$(date +%H:%M:%S)"
        sleep 1
    done
    echo 

    benchmark_result_file=$(find "$BENCHMARK_RESULT_DIR" -maxdepth 1 -type f -name "SB__*.txt" | sort | tail -n 1)
    if [[ ! -e "$benchmark_result_file" ]]; then 
        echo "Error: can't find benchmark result file: $benchmark_result_file"
        return 1
    fi 

    cat "$benchmark_result_file" | sed '/Frame times (ms):/,$d'
}

if [ "$EUID" -eq 0 ]; then
    printf 'Error: do not run this script with sudo/root\n' >&2
    exit 1
fi

if [[ $1 == ngfx ]]; then 
    if [[ $2 == ? ]]; then 
        ngfx --help-all >/tmp/ngfx
        cat /tmp/ngfx | sed -n '/--architecture arg/,/--metric-set-name arg/p' | sed '$d'
        cat /tmp/ngfx | sed -n '/--metric-set-name arg/,/--metric-set-id arg/p' | sed '$d'
        exit 
    fi 
    if [[ -z $(pidof steam) && ! -z $(which ngfx) ]]; then 
        GPU_ARCH="Blackwell GB20x"
        METRIC_SET="Top-Level Triage"
        rm -rf   $HOME/StrangeBrigade_Nsight_GPU_Trace_TEMP
        mkdir -p $HOME/StrangeBrigade_Nsight_GPU_Trace_TEMP
        ngfx \
            --exe="/usr/games/steam" \
            --dir="$HOME" \
            --env="DISPLAY=:0" \
            --activity="GPU Trace Profiler" \
            --real-time-shader-profiler \
            --no-timeout \
            --auto-export \
            --multi-pass-metrics \
            --set-gpu-clocks=boost \
            --output-dir=$HOME/StrangeBrigade_Nsight_GPU_Trace_TEMP \
            --start-after-hotkey \
            --limit-to-frames=3 \
            --architecture="$GPU_ARCH" \
            --metric-set-name="$METRIC_SET" \
            --launch-detached 
        echo "GPU Trace output folder: $HOME/StrangeBrigade_Nsight_GPU_Trace_TEMP"
        echo "GPU Architecture: $GPU_ARCH"
        echo "      Metric Set: $METRIC_SET"
        echo "Press hot-key [F11] to trigger a captire"
    fi 
else 
    run_strangebrigade_benchmark 
fi 