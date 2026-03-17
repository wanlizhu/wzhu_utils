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
f_comm="$tmpdir/grep_comm_$pid"
cleanup() { rm -f "$f_page" "$f_labels" "$f_folded" "$f_svg" "$f_comm"; }
trap cleanup EXIT

# Build replacement for __PAGE_TITLE_JS__ (full assignment line; 6 spaces to match template)
page_title_escaped=$(echo "$COMM flame graphs" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '      window.PAGE_TITLE = "%s";\n' "$page_title_escaped" > "$f_page"

# Build replacement for __COMM_JS__ (for dump filename)
comm_escaped=$(echo "$COMM" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '      window.COMM = "%s";\n' "$comm_escaped" > "$f_comm"

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
printf '      window.TAB_SVG_B64 = ' >> "$f_svg"
echo -n '[' >> "$f_svg"
for i in "${!tab_files[@]}"; do
    b64=$(base64 -w0 < "$HOME/${tab_files[$i]}" 2>/dev/null || base64 < "$HOME/${tab_files[$i]}" 2>/dev/null | tr -d '\n')
    [[ $i -gt 0 ]] && echo -n ',' >> "$f_svg"
    printf '"%s"' "$b64" >> "$f_svg"
done
echo '];' >> "$f_svg"

# Substitute placeholders: replace the line containing each placeholder with the contents of the temp file.
# POSIX sed requires newline after 'r filename'; each -e is one fragment, so we use $'\n' for newline.
sed -e "/__PAGE_TITLE_JS__/{ r $f_page" -e $'\nd}' \
   -e "/__COMM_JS__/{ r $f_comm" -e $'\nd}' \
   -e "/__TAB_LABELS_JSON__/{ r $f_labels" -e $'\nd}' \
   -e "/__FOLDED_B64_JSON__/{ r $f_folded" -e $'\nd}' \
   -e "/__TAB_SVG_B64_JSON__/{ r $f_svg" -e $'\nd}' \
   "$TEMPLATE" > "$html_file"

echo "    - $html_file (tab view)"
