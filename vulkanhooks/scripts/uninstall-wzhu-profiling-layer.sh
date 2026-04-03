#!/usr/bin/env bash
# Removes this layer from the same install prefix as this script (PREFIX/bin/... -> PREFIX).
set -euo pipefail

THIS="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")"
BIN_DIR="$(dirname "$THIS")"
PREFIX="$(dirname "$BIN_DIR")"
JSON="${PREFIX}/share/vulkan/implicit_layer.d/VkLayer_wzhu_profiling.json"
SO="${PREFIX}/lib/libVkLayer_wzhu_profiling.so"
UNINSTALL="${PREFIX}/bin/uninstall-wzhu-profiling-layer.sh"

sudo rm -f "$JSON" "$SO"
echo "Removed (if present):"
echo "  $JSON"
echo "  $SO"

if [[ -f "$UNINSTALL" ]]; then
    rm -f "$UNINSTALL"
    echo "  $UNINSTALL"
fi

echo "VK_LAYER_WZHU_profiling layer uninstalled from ${PREFIX}"
