#!/usr/bin/env bash
# Called from generate-perthread-flamegraph.sh when per-thread flamegraphs exist.
# Do not run directly. Expects: tab_labels, tab_files, COMM (from caller).
# Optional: tab_folded_files (same length as tab_files) for tree view and SVG<->tree sync.
# Uses flamegraph-report-template.html in the same dir; substitutes placeholders with data.
set -o pipefail

# Guardian: required variables and values.
: "${COMM:?generate-html-report.sh: COMM must be set}"
[[ ${#tab_labels[@]} -gt 0 ]] || { echo "generate-html-report.sh: tab_labels must be a non-empty array" >&2; exit 1; }
[[ ${#tab_files[@]} -eq ${#tab_labels[@]} ]] || { echo "generate-html-report.sh: tab_files must have the same length as tab_labels" >&2; exit 1; }

SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")
TEMPLATE="$SCRIPT_DIR/flamegraph-report-template.html"
[[ -f "$TEMPLATE" ]] || { echo "generate-html-report.sh: template not found: $TEMPLATE" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "generate-html-report.sh: python3 is required" >&2; exit 1; }

# Optional: folded data for tree view (gzip then base64 per tab to reduce size)
declare -a folded_b64
for i in "${!tab_files[@]}"; do
    if [[ ${#tab_folded_files[@]} -eq ${#tab_files[@]} ]] && [[ -f "${tab_folded_files[$i]:-}" ]]; then
        folded_b64[i]=$(gzip -cn < "${tab_folded_files[$i]}" 2>/dev/null | base64 -w0 2>/dev/null) || folded_b64[i]=$(base64 -w0 < "${tab_folded_files[$i]}" 2>/dev/null)
        [[ -z "${folded_b64[$i]:-}" ]] && folded_b64[i]=$(base64 < "${tab_folded_files[$i]}" 2>/dev/null | tr -d '\n')
    else
        folded_b64[i]=""
    fi
done

html_file="$HOME/${COMM}_flamegraph_tabs.html"
tmpdir="${TMPDIR:-/tmp}"
pid=$$
f_page="$tmpdir/grep_page_$pid"
f_labels="$tmpdir/grep_labels_$pid"
f_folded="$tmpdir/grep_folded_$pid"
f_svg="$tmpdir/grep_svg_$pid"
f_filenames="$tmpdir/grep_filenames_$pid"
f_comm="$tmpdir/grep_comm_$pid"
f_sysinfo="$tmpdir/grep_sysinfo_$pid"
cleanup() { rm -f "$f_page" "$f_labels" "$f_folded" "$f_svg" "$f_filenames" "$f_comm" "$f_sysinfo"; }
trap cleanup EXIT

# Build replacement for __PAGE_TITLE_JS__ (full assignment line; 6 spaces to match template)
page_title_escaped=$(echo "$COMM flame graphs" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '      window.PAGE_TITLE = "%s";\n' "$page_title_escaped" > "$f_page"

# Build replacement for __COMM_JS__ (for dump filename)
comm_escaped=$(echo "$COMM" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '      window.COMM = "%s";\n' "$comm_escaped" > "$f_comm"

# Build JSON array for SVG display filenames (basename only, for use in UI)
printf '      window.TAB_SVG_FILENAMES = ' > "$f_filenames"
echo -n '[' >> "$f_filenames"
for i in "${!tab_files[@]}"; do
    base=$(basename -- "${tab_files[$i]}")
    base_escaped=$(echo "$base" | sed 's/\\/\\\\/g; s/"/\\"/g')
    [[ $i -gt 0 ]] && echo -n ',' >> "$f_filenames"
    printf '"%s"' "$base_escaped" >> "$f_filenames"
done
echo '];' >> "$f_filenames"

# Build JSON array for tab labels (escape each element for JSON)
printf '      window.TAB_LABELS = ' > "$f_labels"
echo -n '[' >> "$f_labels"
for i in "${!tab_labels[@]}"; do
    lab=$(echo "${tab_labels[$i]}" | sed 's/\\/\\\\/g; s/"/\\"/g')
    [[ $i -gt 0 ]] && echo -n ',' >> "$f_labels"
    printf '"%s"' "$lab" >> "$f_labels"
done
echo '];' >> "$f_labels"

# Build JSON array for folded base64 (each element is a base64 string)
printf '      window.FOLDED_B64 = ' >> "$f_folded"
echo -n '[' >> "$f_folded"
for i in "${!folded_b64[@]}"; do
    [[ $i -gt 0 ]] && echo -n ',' >> "$f_folded"
    if [[ -n "${folded_b64[$i]:-}" ]]; then
        printf '"%s"' "${folded_b64[$i]}" >> "$f_folded"
    else
        echo -n '""' >> "$f_folded"
    fi
done
echo '];' >> "$f_folded"

# Build JSON array for SVG base64
printf '      window.TAB_SVG_B64 = ' > "$f_svg"
echo -n '[' >> "$f_svg"
for i in "${!tab_files[@]}"; do
    path="${tab_files[$i]}"
    b64=$(base64 -w0 < "$path" 2>/dev/null || base64 < "$path" 2>/dev/null | tr -d '\n')
    [[ $i -gt 0 ]] && echo -n ',' >> "$f_svg"
    printf '"%s"' "$b64" >> "$f_svg"
done
echo '];' >> "$f_svg"

# System info: read ${SYSTEM_INFO_FILE:-$HOME/system_info.txt}; each line "key<TAB>value" becomes a row.
# If the file has no tab-separated lines, the whole file is one row (key "System information").
SYS_INFO_FILE="${SYSTEM_INFO_FILE:-$HOME/system_info.txt}"
if [[ -f "$SYS_INFO_FILE" ]] && [[ -s "$SYS_INFO_FILE" ]]; then
    python3 - "$SYS_INFO_FILE" <<'PY' > "$f_sysinfo" || printf '      window.SYSTEM_INFO_ROWS = [];\n' > "$f_sysinfo"
import json, sys

path = sys.argv[1]
rows = []
try:
    with open(path, encoding="utf-8") as f:
        text = f.read()
except OSError:
    text = ""
if text.strip():
    for line in text.splitlines():
        if not line.strip():
            continue
        tab = line.find("\t")
        if tab != -1:
            rows.append({"k": line[:tab], "v": line[tab + 1:]})
    if not rows:
        rows.append({"k": "System information", "v": text.rstrip("\n")})
print("      window.SYSTEM_INFO_ROWS = " + json.dumps(rows, ensure_ascii=False) + ";")
PY
else
    printf '      window.SYSTEM_INFO_ROWS = [];\n' > "$f_sysinfo"
fi

# Substitute placeholders: replace each line that contains a marker with the corresponding fragment file.
# (Python avoids GNU vs BSD sed differences for multiline r/d.)
python3 - "$f_page" "$f_comm" "$f_filenames" "$f_labels" "$f_folded" "$f_svg" "$f_sysinfo" "$TEMPLATE" <<'PY' > "$html_file"
import sys

paths = sys.argv[1:8]
template_path = sys.argv[8]
markers = [
    "__PAGE_TITLE_JS__",
    "__COMM_JS__",
    "__TAB_SVG_FILENAMES_JSON__",
    "__TAB_LABELS_JSON__",
    "__FOLDED_B64_JSON__",
    "__TAB_SVG_B64_JSON__",
    "__SYSTEM_INFO_ROWS_JS__",
]
mapping = list(zip(markers, paths))
with open(template_path, encoding="utf-8") as f:
    for line in f:
        repl = None
        for marker, path in mapping:
            if marker in line:
                with open(path, encoding="utf-8") as pf:
                    repl = pf.read()
                break
        sys.stdout.write(repl if repl is not None else line)
PY

echo "    - $html_file (Merged HTML Tab View)"
