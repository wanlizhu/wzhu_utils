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

ASK_INTERVAL_SECONDS=60
RESULT_SETTLE_SECONDS=3
STATUS_PREFIX='[strange-brigade-bench]'

RESULT_MARKER_FILE=/tmp/strange-brigade-result-marker.$$
BENCHMARK_RESULT_FILE=
STEAM_LAUNCH_PID=

write_graphics_options()
{
    mkdir -p "$GAME_CONFIG_DIR" || {
        printf '%s error: failed to create game config directory\n' "$STATUS_PREFIX" >&2
        exit 1
    }

    mkdir -p "$BENCHMARK_RESULT_DIR" || {
        printf '%s error: failed to create benchmark result directory\n' "$STATUS_PREFIX" >&2
        exit 1
    }

    printf '%s writing benchmark config to %s\n' "$STATUS_PREFIX" "$GAME_CONFIG_FILE"

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
        printf '%s error: failed to write game config\n' "$STATUS_PREFIX" >&2
        exit 1
    }
}

run_benchmark()
{
    : > "$RESULT_MARKER_FILE" || {
        printf '%s error: failed to create temporary marker file\n' "$STATUS_PREFIX" >&2
        exit 1
    }

    trap '[ -f "$RESULT_MARKER_FILE" ] && rm -f "$RESULT_MARKER_FILE"' EXIT

    printf '%s launching steam benchmark\n' "$STATUS_PREFIX"
    "$STEAM_COMMAND" -applaunch "$APP_ID" -benchmark &
    STEAM_LAUNCH_PID=$!
    printf '%s steam launcher pid: %s\n' "$STATUS_PREFIX" "$STEAM_LAUNCH_PID"

    printf '%s waiting for game process to appear: %s\n' "$STATUS_PREFIX" "$GAME_PROCESS_NAME"

    while true; do
        if pgrep -x "$GAME_PROCESS_NAME" > /dev/null; then
            printf '%s game process detected\n' "$STATUS_PREFIX"
            break
        fi

        printf '%s still waiting for the game to start\n' "$STATUS_PREFIX"
        printf '%s terminate the game now? [y/N]: ' "$STATUS_PREFIX"

        reply=
        if read -r -t "$ASK_INTERVAL_SECONDS" reply; then
            case $reply in
                y|Y|yes|YES)
                    printf '%s terminating benchmark processes by user request\n' "$STATUS_PREFIX"
                    pkill -x "$GAME_PROCESS_NAME" 2>/dev/null
                    exit 1
                    ;;
                *)
                    printf '%s continue waiting\n' "$STATUS_PREFIX"
                    ;;
            esac
        else
            printf '\n'
        fi
    done

    printf '%s waiting for benchmark process to exit\n' "$STATUS_PREFIX"

    while true; do
        if ! pgrep -x "$GAME_PROCESS_NAME" > /dev/null; then
            printf '%s game process exited\n' "$STATUS_PREFIX"
            break
        fi

        printf '%s benchmark is still running\n' "$STATUS_PREFIX"
        printf '%s terminate the game now? [y/N]: ' "$STATUS_PREFIX"

        reply=
        if read -r -t "$ASK_INTERVAL_SECONDS" reply; then
            case $reply in
                y|Y|yes|YES)
                    printf '%s terminating benchmark processes by user request\n' "$STATUS_PREFIX"
                    pkill -x "$GAME_PROCESS_NAME" 2>/dev/null
                    exit 1
                    ;;
                *)
                    printf '%s continue waiting\n' "$STATUS_PREFIX"
                    ;;
            esac
        else
            printf '\n'
        fi
    done

    printf '%s waiting for benchmark result file\n' "$STATUS_PREFIX"

    while true; do
        BENCHMARK_RESULT_FILE=$(
            find "$BENCHMARK_RESULT_DIR" -maxdepth 1 -type f -name "$RESULT_FILE_GLOB" -newer "$RESULT_MARKER_FILE" -printf '%T@ %p\n' 2>/dev/null |
            sort -n |
            tail -n 1 |
            cut -d' ' -f2-
        )

        if [ -n "$BENCHMARK_RESULT_FILE" ] && [ -s "$BENCHMARK_RESULT_FILE" ]; then
            sleep "$RESULT_SETTLE_SECONDS"

            if [ -s "$BENCHMARK_RESULT_FILE" ]; then
                printf '%s result file detected: %s\n' "$STATUS_PREFIX" "$BENCHMARK_RESULT_FILE"
                break
            fi
        fi

        printf '%s result file is not ready yet\n' "$STATUS_PREFIX"
        printf '%s terminate the game now? [y/N]: ' "$STATUS_PREFIX"

        reply=
        if read -r -t "$ASK_INTERVAL_SECONDS" reply; then
            case $reply in
                y|Y|yes|YES)
                    printf '%s terminating benchmark processes by user request\n' "$STATUS_PREFIX"
                    pkill -x "$GAME_PROCESS_NAME" 2>/dev/null
                    exit 1
                    ;;
                *)
                    printf '%s continue waiting\n' "$STATUS_PREFIX"
                    ;;
            esac
        else
            printf '\n'
        fi
    done

    [ -n "$BENCHMARK_RESULT_FILE" ] || {
        printf '%s error: benchmark result file not found\n' "$STATUS_PREFIX" >&2
        exit 1
    }

    [ -s "$BENCHMARK_RESULT_FILE" ] || {
        printf '%s error: benchmark result file is empty\n' "$STATUS_PREFIX" >&2
        exit 1
    }
}

print_results()
{
    printf '%s benchmark raw result file:\n' "$STATUS_PREFIX"
    cat "$BENCHMARK_RESULT_FILE"
    printf '\n'

    printf '%s parsed summary:\n' "$STATUS_PREFIX"
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
    printf '%s error: steam command not found\n' "$STATUS_PREFIX" >&2
    exit 1
}

if [ "$EUID" -eq 0 ]; then
    printf '%s error: do not run this script with sudo/root\n' "$STATUS_PREFIX" >&2
    exit 1
fi

write_graphics_options
run_benchmark
print_results