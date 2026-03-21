#!/usr/bin/env bash
set -o pipefail

APP_ID=312670
GAME_PROCESS_NAME=StrangeBrigade_
STEAM_ROOT=$HOME/.steam/steam
PROTON_PREFIX=$STEAM_ROOT/steamapps/compatdata/$APP_ID/pfx

GAME_CONFIG_DIR=$PROTON_PREFIX/drive_c/users/steamuser/'Local Settings'/'Application Data'/'Strange Brigade'
GAME_CONFIG_FILE=$GAME_CONFIG_DIR/GraphicsOptions.ini
BENCHMARK_RESULT_DIR=$PROTON_PREFIX/drive_c/users/steamuser/'My Documents'/StrangeBrigade_Benchmark
RESULT_FILE_GLOB='SB__*.txt'
BENCHMARK_WIDTH=3840
BENCHMARK_HEIGHT=2160
BENCHMARK_QUALITY=3
BENCHMARK_RESULT_FILE=

write_graphics_options()
{
    mkdir -p "$GAME_CONFIG_DIR" || {
        printf 'Error: failed to create game config directory\n' >&2
        exit 1
    }

    mkdir -p "$BENCHMARK_RESULT_DIR" || {
        printf 'Error: failed to create benchmark result directory\n' >&2
        exit 1
    }

    printf 'Writing benchmark config to %s\n' "$GAME_CONFIG_FILE"

    printf '%s\n' \
        '[Display Settings]' \
        'D3D12 = 0' \
        "Resolution_Width = $BENCHMARK_WIDTH" \
        "Resolution_Height = $BENCHMARK_HEIGHT" \
        'RenderScale = 1.000000' \
        'Windowed = 0' \
        'MotionBlur = 1' \
        'AmbientOcclusion = 1' \
        'VSync = 0' \
        'ReduceMouseLag = 0' \
        'AsyncCompute = 1' \
        'Tessellation = 0' \
        "TextureDetail = $BENCHMARK_QUALITY" \
        "ShadowDetail = $BENCHMARK_QUALITY" \
        "AntiAliasing = $BENCHMARK_QUALITY" \
        "DrawDistance = $BENCHMARK_QUALITY" \
        'AnisotropicFiltering = 4' \
        'SSReflectionsQuality = 1' \
        'Brightness = 0.500000' \
        'ObscuranceFields = 0' \
        'ReverbQuality = 1' \
        'HDR = 0' \
        > "$GAME_CONFIG_FILE" || {
        printf 'Error: failed to write game config\n' >&2
        exit 1
    }
}

run_benchmark()
{
    printf 'Removing old benchmark result files\n'
    find "$BENCHMARK_RESULT_DIR" -maxdepth 1 -type f -name "$RESULT_FILE_GLOB" -delete || {
        printf 'Error: failed to remove old benchmark result files\n' >&2
        exit 1
    }

    printf 'Launching steam benchmark\n'
    if [[ ! -z $(which mangohud) ]]; then 
        MANGOHUD=1 MANGOHUD_CONFIG=position=top-right,output_folder=$HOME,log_duration=0 steam -applaunch $APP_ID -benchmark &
    else
        steam -applaunch $APP_ID -benchmark &
    fi 
    printf 'Steam launch command submitted\n'

    printf 'Waiting for game process to appear: %s*\n' "$GAME_PROCESS_NAME"
    while ! pgrep -f "$GAME_PROCESS_NAME" > /dev/null; do
        sleep 5
    done
    printf 'Game process detected\n'

    printf 'Waiting for benchmark process to exit\n'
    while pgrep -f "$GAME_PROCESS_NAME" > /dev/null; do
        sleep 5
    done
    printf 'Game process exited\n'

    printf 'Waiting for benchmark result file\n'
    sleep 3
    BENCHMARK_RESULT_FILE=$(find "$BENCHMARK_RESULT_DIR" -maxdepth 1 -type f -name "$RESULT_FILE_GLOB" | sort | tail -n 1)
    if [ -n "$BENCHMARK_RESULT_FILE" ] && [ -s "$BENCHMARK_RESULT_FILE" ]; then
        if [ -s "$BENCHMARK_RESULT_FILE" ]; then
            printf 'Result file detected: %s\n' "$BENCHMARK_RESULT_FILE"
            print_results
            return 
        fi
    fi

    echo "Result file doesn't exist: $BENCHMARK_RESULT_FILE"
    if [[ ! -z $(which mangohud) ]]; then 
        echo "Fallback to read mangohud loggings"

    fi 
}

print_results()
{
    printf 'Benchmark raw result file:\n'
    cat "$BENCHMARK_RESULT_FILE"
    printf '\n'

    printf 'Parsed summary:\n'
    awk -F':' '
        /Average FPS/ {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
            avg=$2
        }
        /Minimum FPS/ {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
            min=$2
        }
        /Maximum FPS/ {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
            max=$2
        }
        END {
            if(avg != "") print "Average FPS: " avg
            if(min != "") print "Minimum FPS: " min
            if(max != "") print "Maximum FPS: " max
        }
    ' "$BENCHMARK_RESULT_FILE"
}

command -v steam > /dev/null || {
    printf 'Error: steam command not found\n' >&2
    exit 1
}

command -v mangohud > /dev/null || {
    sudo apt install -y mangohud 
}

if [ "$EUID" -eq 0 ]; then
    printf 'Error: do not run this script with sudo/root\n' >&2
    exit 1
fi

write_graphics_options
run_benchmark