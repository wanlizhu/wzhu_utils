#!/usr/bin/env bash
set -o pipefail

APP_ID=312670
STEAM_COMMAND=steam
GAME_PROCESS_NAME=StrangeBrigade_

STEAM_ROOT=$HOME/.steam/steam
PROTON_PREFIX=$STEAM_ROOT/steamapps/compatdata/$APP_ID/pfx

GAME_CONFIG_DIR=$PROTON_PREFIX/drive_c/users/steamuser/Local\ Settings/Application\ Data/Strange\ Brigade
GAME_CONFIG_FILE=$GAME_CONFIG_DIR/GraphicsOptions.ini

BENCHMARK_RESULT_DIR=$PROTON_PREFIX/drive_c/users/steamuser/My\ Documents/StrangeBrigade_Benchmark
RESULT_FILE_GLOB='SB__*.txt'

BENCHMARK_WIDTH=3840
BENCHMARK_HEIGHT=2160
BENCHMARK_QUALITY=3

POLL_INTERVAL_SECONDS=2
RESULT_SETTLE_SECONDS=3

BENCHMARK_RESULT_FILE=

write_graphics_options()
{
    mkdir -p "$GAME_CONFIG_DIR" || {
        printf 'error: failed to create game config directory\n' >&2
        exit 1
    }

    mkdir -p "$BENCHMARK_RESULT_DIR" || {
        printf 'error: failed to create benchmark result directory\n' >&2
        exit 1
    }

    printf 'writing benchmark config to %s\n' "$GAME_CONFIG_FILE"

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
        printf 'error: failed to write game config\n' >&2
        exit 1
    }
}

run_benchmark()
{
    printf 'removing old benchmark result files\n'
    find "$BENCHMARK_RESULT_DIR" -maxdepth 1 -type f -name "$RESULT_FILE_GLOB" -delete || {
        printf 'error: failed to remove old benchmark result files\n' >&2
        exit 1
    }

    printf 'launching steam benchmark\n'
    "$STEAM_COMMAND" -applaunch "$APP_ID" -benchmark &
    printf 'steam launch command submitted\n'

    printf 'waiting for game process to appear: %s\n' "$GAME_PROCESS_NAME"
    while ! pgrep -x "$GAME_PROCESS_NAME" > /dev/null; do
        sleep "$POLL_INTERVAL_SECONDS"
    done
    printf 'game process detected\n'

    printf 'waiting for benchmark process to exit\n'
    while pgrep -x "$GAME_PROCESS_NAME" > /dev/null; do
        sleep "$POLL_INTERVAL_SECONDS"
    done
    printf 'game process exited\n'

    printf 'waiting for benchmark result file\n'
    while true; do
        BENCHMARK_RESULT_FILE=$(
            find "$BENCHMARK_RESULT_DIR" -maxdepth 1 -type f -name "$RESULT_FILE_GLOB" | sort | tail -n 1
        )

        if [ -n "$BENCHMARK_RESULT_FILE" ] && [ -s "$BENCHMARK_RESULT_FILE" ]; then
            sleep "$RESULT_SETTLE_SECONDS"

            if [ -s "$BENCHMARK_RESULT_FILE" ]; then
                printf 'result file detected: %s\n' "$BENCHMARK_RESULT_FILE"
                break
            fi
        fi

        sleep "$POLL_INTERVAL_SECONDS"
    done

    [ -n "$BENCHMARK_RESULT_FILE" ] || {
        printf 'error: benchmark result file not found\n' >&2
        exit 1
    }

    [ -s "$BENCHMARK_RESULT_FILE" ] || {
        printf 'error: benchmark result file is empty\n' >&2
        exit 1
    }
}

print_results()
{
    printf 'benchmark raw result file:\n'
    cat "$BENCHMARK_RESULT_FILE"
    printf '\n'

    printf 'parsed summary:\n'
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

command -v "$STEAM_COMMAND" > /dev/null || {
    printf 'error: steam command not found\n' >&2
    exit 1
}

if [ "$EUID" -eq 0 ]; then
    printf 'error: do not run this script with sudo/root\n' >&2
    exit 1
fi

write_graphics_options
run_benchmark
print_results