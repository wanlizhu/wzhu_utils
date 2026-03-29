#!/usr/bin/env bash
# collect_system_info — print one "key<TAB>value" line per row (fixed key order).
# All collection logic lives here so you can change how values are gathered in one place.
# Intended to be sourced by generate-html-report.sh (do not run standalone for JSON; use the function).

collect_system_info() {
  # generate-html-report.sh uses pipefail; grep in pipelines may exit 1 without a match.
  local _csi_restore_pipefail=false
  if [[ -o pipefail ]]; then _csi_restore_pipefail=true; set +o pipefail; fi

  _csi_kv() { printf '%s\t%s\n' "$1" "${2:-N/A}"; }

  # --- hostname ---
  _csi_kv "hostname" "$(hostname 2>/dev/null || uname -n 2>/dev/null)"

  # --- OS / kernel ---
  if [[ -r /etc/os-release ]]; then
    local os_name
    os_name=$( (source /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-${NAME:-}}") | head -1 )
    _csi_kv "OS Name" "${os_name:-}"
  elif command -v sw_vers >/dev/null 2>&1; then
    _csi_kv "OS Name" "$(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null)"
  else
    _csi_kv "OS Name" "$(uname -s 2>/dev/null)"
  fi
  if [[ "$(uname -s 2>/dev/null)" == "Linux" ]]; then
    _csi_kv "Linux Kernel" "$(uname -r 2>/dev/null)"
  else
    _csi_kv "Linux Kernel" "N/A (not Linux; $(uname -s 2>/dev/null) $(uname -r 2>/dev/null))"
  fi

  # --- X11 / display stack (Linux + X session) ---
  local xver wm refresh res desktop_res depth glver
  xver=""
  if command -v xdpyinfo >/dev/null 2>&1; then
    xver=$(xdpyinfo 2>/dev/null | grep -iE '^version number:' | head -1 | sed 's/.*:[[:space:]]*//')
    [[ -z "$xver" ]] && xver=$(xdpyinfo 2>/dev/null | grep -i 'X.Org version' | head -1 | sed 's/.*:[[:space:]]*//')
    res=$(xdpyinfo 2>/dev/null | awk '/dimensions:/{print $2; exit}')
    depth=$(xdpyinfo 2>/dev/null | awk '/depth of root window/{print $5; exit}')
    desktop_res="${res:-}"
  fi
  _csi_kv "X Server Release" "${xver:-N/A}"

  wm=""
  if command -v wmctrl >/dev/null 2>&1; then
    wm=$(wmctrl -m 2>/dev/null | awk -F: '/^Name/{gsub(/^[[:space:]]+/,"",$2); print $2; exit}')
  fi
  [[ -z "$wm" && -n "${XDG_CURRENT_DESKTOP:-}" ]] && wm="${XDG_CURRENT_DESKTOP}"
  [[ -z "$wm" && -n "${DESKTOP_SESSION:-}" ]] && wm="${DESKTOP_SESSION}"
  _csi_kv "X Window Manager" "${wm:-N/A}"

  # --- CPU ---
  local cpu_name cpu_mhz cores ht ram_kb ram_human
  if [[ -r /proc/cpuinfo ]]; then
    cpu_name=$(grep -m1 '^model name' /proc/cpuinfo 2>/dev/null | sed 's/.*:[[:space:]]*//')
  fi
  [[ -z "$cpu_name" && "$(uname -s)" == "Darwin" ]] && cpu_name=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
  _csi_kv "CPU Name" "${cpu_name:-}"

  cpu_mhz=""
  if command -v lscpu >/dev/null 2>&1; then
    cpu_mhz=$(lscpu 2>/dev/null | grep -i 'CPU max MHz' | awk '{print $NF " MHz"}' | head -1)
    [[ -z "$cpu_mhz" ]] && cpu_mhz=$(lscpu 2>/dev/null | grep -i 'CPU(s) MHz' | awk '{print $NF " MHz"}' | head -1)
  fi
  [[ -z "$cpu_mhz" && "$(uname -s)" == "Darwin" ]] && cpu_mhz=$(sysctl -n hw.cpufrequency_max 2>/dev/null | awk '{if ($1>0) printf "%.0f MHz\n", $1/1000000}')
  _csi_kv "CPU Speed (Max Clock)" "${cpu_mhz:-N/A}"

  ram_human=""
  if command -v free >/dev/null 2>&1; then
    ram_human=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}')
  elif [[ -r /proc/meminfo ]]; then
    ram_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)
    [[ -n "$ram_kb" ]] && ram_human="${ram_kb} kB"
  elif [[ "$(uname -s)" == "Darwin" ]]; then
    ram_kb=$(sysctl -n hw.memsize 2>/dev/null)
    [[ -n "$ram_kb" ]] && ram_human=$(awk -v b="$ram_kb" 'BEGIN{printf "%.2f GiB\n", b/1024/1024/1024}')
  fi
  _csi_kv "CPU RAM" "${ram_human:-N/A}"

  cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "")
  _csi_kv "CPU Cores" "${cores:-N/A}"

  ht="N/A"
  if command -v lscpu >/dev/null 2>&1; then
    local tpc
    tpc=$(lscpu 2>/dev/null | grep -i 'Thread(s) per core' | awk '{print $NF}')
    if [[ "$tpc" =~ ^[0-9]+$ ]]; then
      [[ "$tpc" -gt 1 ]] && ht="Yes" || ht="No"
    fi
  elif [[ "$(uname -s)" == "Darwin" ]]; then
    local phy logical
    phy=$(sysctl -n hw.physicalcpu 2>/dev/null)
    logical=$(sysctl -n hw.logicalcpu 2>/dev/null)
    [[ -n "$phy" && -n "$logical" && "$logical" -gt "$phy" ]] && ht="Yes" || ht="No"
  fi
  _csi_kv "CPU Hyper-threading" "$ht"

  # --- GPU (NVIDIA preferred, then lspci) ---
  local gpu_name gpu_mhz vram driver vendev gpcline
  gpu_name=""; gpu_mhz=""; vram=""; driver=""; vendev=""
  gpcline=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' | head -1)
  [[ -n "$gpcline" ]] && vendev=$(echo "$gpcline" | grep -oE '\[[0-9a-f]{4}:[0-9a-f]{4}\]' | tr -d '[]' | head -1)

  if command -v nvidia-smi >/dev/null 2>&1; then
    gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | tr -d '\r')
    gpu_mhz=$(nvidia-smi --query-gpu=clocks.max.sm --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d '\r')
    [[ -n "$gpu_mhz" ]] && gpu_mhz="${gpu_mhz} MHz"
    vram=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1 | tr -d '\r')
    driver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | tr -d '\r')
  else
    [[ -n "$gpcline" ]] && gpu_name=$(echo "$gpcline" | sed 's/^[0-9a-f:.]* //')
    if [[ -r /sys/class/drm/card0/device/mem_info_vram_total ]]; then
      vram=$(awk '{printf "%.0f MiB\n", $1/1024/1024}' /sys/class/drm/card0/device/mem_info_vram_total 2>/dev/null)
    fi
  fi
  if [[ "$(uname -s)" == "Darwin" ]] && command -v system_profiler >/dev/null 2>&1; then
    [[ -z "$gpu_name" ]] && gpu_name=$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F: '/Chipset Model|Model:/{gsub(/^[[:space:]]+/,"",$2); print $2; exit}')
    [[ -z "$vram" ]] && vram=$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F: '/VRAM/{gsub(/^[[:space:]]+/,"",$2); print $2; exit}')
  fi
  _csi_kv "GPU Name" "${gpu_name:-N/A}"
  _csi_kv "GPU Speed (Max Clock)" "${gpu_mhz:-N/A}"
  _csi_kv "GPU VRAM" "${vram:-N/A}"
  _csi_kv "GPU Driver Version" "${driver:-N/A}"
  if [[ -n "$vendev" ]]; then
    _csi_kv "GPU Vendor ID" "${vendev%%:*}"
    _csi_kv "GPU Device ID" "${vendev##*:}"
  else
    _csi_kv "GPU Vendor ID" "N/A"
    _csi_kv "GPU Device ID" "N/A"
  fi

  glver=""
  if command -v glxinfo >/dev/null 2>&1; then
    glver=$(glxinfo 2>/dev/null | grep -i 'OpenGL version string:' | head -1 | sed 's/.*:[[:space:]]*//')
  fi
  _csi_kv "OpenGL Version" "${glver:-N/A}"

  refresh=""
  if command -v xrandr >/dev/null 2>&1; then
    refresh=$(xrandr 2>/dev/null | grep '\*' | head -1 | grep -oE '[0-9]+\.[0-9]+\*' | head -1 | tr -d '*')
    [[ -z "$res" ]] && res=$(xrandr 2>/dev/null | grep '\*' | head -1 | awk '{print $1}')
  fi
  _csi_kv "Display Resolution" "${res:-N/A}"
  [[ -n "$refresh" ]] && _csi_kv "Display Refresh Rate" "${refresh} Hz" || _csi_kv "Display Refresh Rate" "N/A"
  _csi_kv "Desktop Resolution" "${desktop_res:-${res:-N/A}}"
  _csi_kv "Desktop Color Depth" "${depth:-N/A}"

  if [[ "$_csi_restore_pipefail" == true ]]; then set -o pipefail; fi
}
