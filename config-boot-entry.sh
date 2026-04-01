#!/usr/bin/env bash
set -o pipefail

GRUB_CFG=/boot/grub/grub.cfg
GRUB_BOOT_ENTRIES=/tmp/grub_boot_entries.cfg

sudo rm -f $GRUB_BOOT_ENTRIES
sudo python3 - "$GRUB_CFG" > $GRUB_BOOT_ENTRIES <<'PY'
import sys

cfg = sys.argv[1]

def parse_quoted(s, pos):
    if pos >= len(s) or s[pos] not in ("'", '"'):
        return None, pos

    quote = s[pos]
    pos += 1
    out = []

    while pos < len(s):
        c = s[pos]

        if c == "\\" and pos + 1 < len(s):
            out.append(s[pos + 1])
            pos += 2
            continue

        if c == quote:
            pos += 1
            return "".join(out), pos

        out.append(c)
        pos += 1

    return None, pos

def count_braces_outside_quotes(s):
    opens = 0
    closes = 0
    quote = None
    escape = False

    for c in s:
        if escape:
            escape = False
            continue

        if c == "\\":
            escape = True
            continue

        if quote is not None:
            if c == quote:
                quote = None
            continue

        if c in ("'", '"'):
            quote = c
            continue

        if c == "{":
            opens += 1
        elif c == "}":
            closes += 1

    return opens, closes

def parse_header(line):
    i = 0
    n = len(line)

    while i < n and line[i].isspace():
        i += 1

    if line.startswith("menuentry", i):
        kind = "menuentry"
        i += len("menuentry")
    elif line.startswith("submenu", i):
        kind = "submenu"
        i += len("submenu")
    else:
        return None

    while i < n and line[i].isspace():
        i += 1

    title, i = parse_quoted(line, i)
    if title is None:
        return None

    entry_id = None
    search = 0

    while True:
        j = line.find("--id", search)
        if j < 0:
            break

        k = j + len("--id")
        while k < n and line[k].isspace():
            k += 1

        value, end = parse_quoted(line, k)
        if value is not None:
            entry_id = value
            break

        search = j + 1

    return kind, title, entry_id

entries = []
submenu_stack = []
depth = 0

with open(cfg, encoding="utf-8", errors="replace") as f:
    for raw in f:
        line = raw.rstrip("\n")

        while submenu_stack and depth < submenu_stack[-1][1]:
            submenu_stack.pop()

        parsed = parse_header(line)
        opens, closes = count_braces_outside_quotes(line)

        if parsed is not None:
            kind, title, entry_id = parsed

            if kind == "submenu":
                submenu_stack.append((title, depth + 1))
            else:
                path = [x[0] for x in submenu_stack]
                path.append(title)
                full_title = ">".join(path)
                key = entry_id if entry_id else full_title
                entries.append((full_title, key))

        depth += opens - closes

        while submenu_stack and depth < submenu_stack[-1][1]:
            submenu_stack.pop()

seen = set()
index = 1

for full_title, key in entries:
    pair = (full_title, key)
    if pair in seen:
        continue
    seen.add(pair)
    print(f"{index}\t{full_title}\t{key}")
    index += 1
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