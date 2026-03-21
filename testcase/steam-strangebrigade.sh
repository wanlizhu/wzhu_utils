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

    steam -applaunch $APP_ID -benchmark &
    printf 'Waiting for game process to appear ...\n'
    while ! pgrep -f "$GAME_PROCESS_NAME" > /dev/null; do
        sleep 5
    done

    printf 'Waiting for game process to finish ...\n'
    while pgrep -f "$GAME_PROCESS_NAME" > /dev/null; do
        sleep 5
    done

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

    echo "Result file $RESULT_FILE_GLOB doesn't exist"
    if [[ ! -z $(which mangohud) ]]; then 
        echo "Fallback to read mangohud loggings"
        latest_mangohud_log=$(find "$HOME" -maxdepth 1 -type f -name 'StrangeBrigade_*.csv' | sort | tail -n 1)
        if [ -s "$latest_mangohud_log" ]; then
            avg_fps=$(awk -F, 'NR >= 4 { sum += $1; n++ } END { if (n) print sum / n }' "$latest_mangohud_log")
            echo "Average FPS: $avg_fps"

            rm -rf /tmp/desc.txt /tmp/data.csv 
            python3 - "$latest_mangohud_log" <<'PY'
import csv
import sys

src = sys.argv[1]
data_out = '/tmp/data.csv'
desc_out = '/tmp/desc.txt'

drop = {'frametime', 'swap_used', 'process_rss', 'elapsed'}
rename = {
    'fps': 'fps_dec',
    'cpu_load': 'cpu_load_pct',
    'gpu_load': 'gpu_load_pct',
    'cpu_temp': 'cpu_temp_c',
    'gpu_temp': 'gpu_temp_c',
    'gpu_vram_used': 'gpu_vram_used_mb',
    'gpu_power': 'gpu_power_w',
    'ram_used': 'ram_used_mb',
}

with open(src, newline='') as f:
    rows = list(csv.reader(f))

if len(rows) < 3:
    sys.exit(1)

desc_lines = [f'{k}: {v}' for k, v in zip(rows[0], rows[1])]

for line in desc_lines:
    print(line)

with open(desc_out, 'w') as f:
    for line in desc_lines:
        f.write(line + '\n')

hdr = rows[2]
keep = [i for i, c in enumerate(hdr) if c not in drop]

new_hdr = []
for c in hdr:
    if c in drop:
        continue
    new_hdr.append(c + '_mhz' if c.endswith('_clock') else rename.get(c, c))

with open(data_out, 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(new_hdr)
    for row in rows[3:]:
        w.writerow([row[i] if i < len(row) else '' for i in keep])

print()
print(desc_out)
print(data_out)
PY
            if [[ -f /tmp/data.csv && -f /tmp/desc/.txt ]]; then 
                draw-polylines-in-html.py --hide-invalid-columns --desc="$(cat /tmp/desc.txt)" --y-axis-mode=actual --default-attributes="fps_dec" /tmp/data.csv && {
                    cp /tmp/data.html ${latest_mangohud_log%.csv}.html
                    echo "Generated ${latest_mangohud_log%.csv}.html"
                } || echo "Failed to generate HTML report"
            fi 
        else
            echo "Config launch options in steam UI: "
            echo "    MANGOHUD=1 MANGOHUD_CONFIG=autostart_log=1,output_folder=$HOME %command%"
        fi 
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

if [[ $1 == ngfx ]]; then 
    if [[ -z $(which steam) ]]; then 
        ngfx --launch-detached \
            --output-dir=$HOME \
            --exe="/usr/games/steam" \
            --dir="$HOME" \
            --env="DISPLAY=:0" 
        sleep 3
    else
        echo "Assume steam process $(pidof steam) was launched by Ngfx"
    fi 
    read -p "Press [Enter] when steam game launched: "
    pstree -aspT $(pidof steam)
    read -p "Select steam game PID: " PID
    rm -rf   $HOME/StrangeBrigade_Nsight_GPU_Trace_TEMP
    mkdir -p $HOME/StrangeBrigade_Nsight_GPU_Trace_TEMP
    ngfx --attach-pid=$PID \
         --activity="GPU Trace Profiler" \
         --real-time-shader-profiler \
         --no-timeout \
         --auto-export \
         --multi-pass-metrics \
         --set-gpu-clocks=boost \
         --output-dir=$HOME/StrangeBrigade_Nsight_GPU_Trace_TEMP \
         --start-after-hotkey \
         --limit-to-frames=3 \
         --architecture="Blackwell GB20x" \
         --metric-set-name="Top-Level Triage"
else 
    write_graphics_options
    run_benchmark
fi 