#!/usr/bin/env bash
set -o pipefail

GRUB_CFG=/boot/grub/grub.cfg
GRUB_BOOT_ENTRIES=/tmp/grub_boot_entries.cfg

sudo rm -f $GRUB_BOOT_ENTRIES
sudo python3 - "$GRUB_CFG" > $GRUB_BOOT_ENTRIES <<'PY'
import sys

def count_braces_outside_quotes(line):
    open_brace_count = 0
    close_brace_count = 0
    current_quote = None
    is_escaped = False

    for char in line:
        if is_escaped:
            is_escaped = False
            continue

        if char == "\\":
            is_escaped = True
            continue

        if current_quote is not None:
            if char == current_quote:
                current_quote = None
            continue

        if char in ("'", '"'):
            current_quote = char
            continue

        if char == "{":
            open_brace_count += 1
        elif char == "}":
            close_brace_count += 1

    return open_brace_count, close_brace_count

def parse_first_quoted_value(text, start_index):
    stripped_length = len(text)

    while start_index < stripped_length and text[start_index].isspace():
        start_index += 1

    if start_index >= stripped_length or text[start_index] not in ("'", '"'):
        return None, start_index

    quote_char = text[start_index]
    start_index += 1
    parsed_chars = []

    while start_index < stripped_length:
        current_char = text[start_index]

        if current_char == "\\" and start_index + 1 < stripped_length:
            parsed_chars.append(text[start_index + 1])
            start_index += 2
            continue

        if current_char == quote_char:
            return "".join(parsed_chars), start_index + 1

        parsed_chars.append(current_char)
        start_index += 1

    return None, start_index

def parse_grub_header(line):
    stripped_line = line.lstrip()

    if stripped_line.startswith("menuentry"):
        entry_kind = "menuentry"
        parse_position = len("menuentry")
    elif stripped_line.startswith("submenu"):
        entry_kind = "submenu"
        parse_position = len("submenu")
    else:
        return None

    title, parse_position = parse_first_quoted_value(stripped_line, parse_position)
    if title is None:
        return None

    entry_id = None
    search_position = parse_position

    while True:
        id_option_index = stripped_line.find("--id", search_position)
        if id_option_index < 0:
            break

        id_value, next_position = parse_first_quoted_value(
            stripped_line,
            id_option_index + len("--id"),
        )
        if id_value is not None:
            entry_id = id_value
            break

        search_position = id_option_index + 1

    return entry_kind, title, entry_id

def parse_grub_entries(grub_cfg_path):
    parsed_entries = []
    submenu_stack = []
    current_depth = 0

    with open(grub_cfg_path, encoding="utf-8", errors="replace") as grub_cfg_file:
        for raw_line in grub_cfg_file:
            line = raw_line.rstrip("\n")

            while submenu_stack and current_depth < submenu_stack[-1]["depth"]:
                submenu_stack.pop()

            parsed_header = parse_grub_header(line)
            open_brace_count, close_brace_count = count_braces_outside_quotes(line)

            if parsed_header is not None:
                entry_kind, title, entry_id = parsed_header

                if entry_kind == "submenu":
                    submenu_stack.append({
                        "title": title,
                        "depth": current_depth + 1,
                    })
                else:
                    menu_path_parts = [submenu["title"] for submenu in submenu_stack]
                    menu_path_parts.append(title)
                    full_title = ">".join(menu_path_parts)
                    entry_key = entry_id if entry_id else full_title
                    parsed_entries.append((full_title, entry_key))

            current_depth += open_brace_count - close_brace_count

            while submenu_stack and current_depth < submenu_stack[-1]["depth"]:
                submenu_stack.pop()

    return parsed_entries

def print_entries(entries):
    seen_entries = set()
    display_index = 1

    for full_title, entry_key in entries:
        entry_pair = (full_title, entry_key)
        if entry_pair in seen_entries:
            continue

        seen_entries.add(entry_pair)
        print(f"{display_index}\t{full_title}\t{entry_key}")
        display_index += 1

grub_cfg_path = sys.argv[1]
print_entries(parse_grub_entries(grub_cfg_path))
PY

if [[ -e $GRUB_BOOT_ENTRIES ]]; then
    sudo chmod 666 $GRUB_BOOT_ENTRIES
else
    echo "Failed to parse $GRUB_CFG"
    exit 1
fi

echo "GRUB boot entries found:"
awk -F '\t' '{printf "%2d. %s\n", $1, $2}' $GRUB_BOOT_ENTRIES
echo
read -r -p "Enter entry number to set as default: " idx
if [[ ! $idx =~ ^[0-9]+$ ]]; then
    echo "Invalid selection"
    exit 1
fi

title=$(awk -F '\t' -v idx="$idx" '$1 == idx {print $2}' $GRUB_BOOT_ENTRIES)
key=$(awk -F '\t' -v idx="$idx" '$1 == idx {print $3}' $GRUB_BOOT_ENTRIES)
if [[ -z $key ]]; then
    echo "Invalid selection"
    exit 1
fi

if grep -q '^GRUB_DEFAULT=' /etc/default/grub; then
    sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
else
    echo 'GRUB_DEFAULT=saved' | sudo tee -a /etc/default/grub >/dev/null
fi

sudo grub-set-default "$key"
sudo update-grub

saved_entry=$(sudo grub-editenv list | awk -F= '/^saved_entry=/{print $2; exit}')
echo "Saved entry in grubenv: ${saved_entry:-N/A}"