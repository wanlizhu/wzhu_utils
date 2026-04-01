#!/usr/bin/env bash
set -o pipefail

GRUB_CFG=/boot/grub/grub.cfg
GRUB_BOOT_ENTRIES=/tmp/grub_boot_entries.cfg

sudo rm -f $GRUB_BOOT_ENTRIES
sudo python3 - "$GRUB_CFG" > $GRUB_BOOT_ENTRIES <<'PY'
import shlex
import sys

def count_braces_outside_quotes(line):
    lexer = shlex.shlex(line, posix=True)
    lexer.whitespace_split = True
    lexer.commenters = ''
    lexer.wordchars += '{}'

    open_brace_count = 0
    close_brace_count = 0

    for token in lexer:
        open_brace_count += token.count('{')
        close_brace_count += token.count('}')

    return open_brace_count, close_brace_count

def parse_grub_header(line):
    stripped_line = line.lstrip()

    if not stripped_line.startswith('menuentry') and not stripped_line.startswith('submenu'):
        return None

    try:
        tokens = shlex.split(stripped_line, comments=False, posix=True)
    except ValueError:
        return None

    if len(tokens) < 2:
        return None

    entry_kind = tokens[0]
    if entry_kind != 'menuentry' and entry_kind != 'submenu':
        return None

    title = tokens[1]
    entry_id = None

    for token_index, token in enumerate(tokens[:-1]):
        if token == '--id' or token == '$menuentry_id_option':
            entry_id = tokens[token_index + 1]
            break

    return entry_kind, title, entry_id

def parse_grub_entries(grub_cfg_path):
    parsed_entries = []
    submenu_stack = []
    current_depth = 0

    with open(grub_cfg_path, encoding='utf-8', errors='replace') as grub_cfg_file:
        for raw_line in grub_cfg_file:
            line = raw_line.rstrip('\n')

            while submenu_stack and current_depth < submenu_stack[-1]['depth']:
                submenu_stack.pop()

            parsed_header = parse_grub_header(line)
            open_brace_count, close_brace_count = count_braces_outside_quotes(line)

            if parsed_header is not None:
                entry_kind, title, entry_id = parsed_header

                if entry_kind == 'submenu':
                    submenu_stack.append({
                        'title': title,
                        'depth': current_depth + 1,
                    })
                else:
                    menu_path_parts = [submenu['title'] for submenu in submenu_stack]
                    menu_path_parts.append(title)
                    full_title = '>'.join(menu_path_parts)
                    entry_key = full_title
                    parsed_entries.append((full_title, entry_key))

            current_depth += open_brace_count - close_brace_count

            while submenu_stack and current_depth < submenu_stack[-1]['depth']:
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
        print(f'{display_index}\t{full_title}\t{entry_key}')
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
read -r -p "Enter entry number to set as default: " selected_index

if [[ ! $selected_index =~ ^[0-9]+$ ]]; then
    echo "Invalid selection"
    exit 1
fi

selected_title=$(awk -F '\t' -v idx="$selected_index" '$1 == idx {print $2}' $GRUB_BOOT_ENTRIES)
selected_key=$(awk -F '\t' -v idx="$selected_index" '$1 == idx {print $3}' $GRUB_BOOT_ENTRIES)

if [[ -z $selected_key ]]; then
    echo "Invalid selection"
    exit 1
fi

if grep -q '^GRUB_DEFAULT=' /etc/default/grub; then
    sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
else
    echo 'GRUB_DEFAULT=saved' | sudo tee -a /etc/default/grub >/dev/null
fi

sudo grub-set-default "$selected_key"
sudo update-grub

saved_entry=$(sudo grub-editenv list | awk -F= '/^saved_entry=/{print $2; exit}')

echo
echo "Selected entry:"
echo "    $selected_title"

echo
echo "Configured key:"
echo "    $selected_key"

echo
echo "Saved entry in grubenv:"
echo "    ${saved_entry:-N/A}"

if [[ $saved_entry != "$selected_key" ]]; then
    echo
    echo "Warning: saved_entry does not match the selected key"
    exit 1
fi
