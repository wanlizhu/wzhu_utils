#!/usr/bin/env bash
#
# print-ascii-tree.sh - Render an indented text file as an ASCII box-drawing tree.
#
# WHAT THIS SCRIPT DOES
#   Reads a file whose lines represent tree nodes: indentation (by default one tab per
#   level) defines depth. Blank lines and lines whose first non-indent character is #
#   are ignored. The first valid line must have no indent (root at level 0); each
#   following line may have the same indent or one more level of indent (no jumps
#   by more than one). The script parses this into level/label arrays and prints a
#   tree using Unicode box-drawing characters: ├─ └─ │ and spaces so the result
#   looks like a directory-style tree. Multiple roots are allowed (separated by
#   blank lines); each root starts a new tree and a blank line is printed between
#   trees.
#
# IMPLEMENTATION
#   - tree_parse_file(): Reads the file line by line, strips leading indent (counts
#     TREE_INDENT_CHAR), validates first node is level 0 and level never increases
#     by more than 1, and fills two nameref arrays: levels (depth) and labels (text).
#   - tree_subtree_end(): Given a node index and the levels array, returns the index
#     past the last descendant (first position where level <= level of start). Used
#     to know where each subtree ends when iterating children.
#   - tree_emit_node(): Prints one node (root with no prefix, or prefix + ├─/└─ +
#     label). Builds next_prefix for children (prefix + "    " or "│   "). Recursively
#     emits each direct child (nodes at level level+1 until subtree_end), computing
#     child_is_last by checking if the next sibling exists. Called by tree_print_from_file
#     for each root and then recursively for each child.
#   - tree_print_from_file(): Validates input path and TREE_INDENT_CHAR, calls
#     tree_parse_file to build levels/labels, then for each root (level 0) finds
#     subtree_end and calls tree_emit_node to print that subtree; advances to the
#     next root. Relationship: parse_file fills the arrays; subtree_end and emit_node
#     work on those arrays; print_from_file orchestrates and handles multiple roots.
#
# CONFIGURATION
#   TREE_INDENT_CHAR - One character (or string) used for one level of indent
#   (default: tab). Must not be empty.
#
set -o pipefail

: "${TREE_INDENT_CHAR:=$'\t'}"

# Print usage to stdout. Used for -h/--help.
print_usage() {
    echo "usage: ${0##*/} [options] <tree-file>"
    echo
    echo "Render an indented text file as an ASCII box-drawing tree."
    echo
    echo "options:"
    echo "  -h, --help    show this help and exit"
    echo
    echo "arguments:"
    echo "  <tree-file>  path to file; each line is a node, indent defines depth (default: one tab per level)"
}

# Parse -h/--help; leave first positional in TREE_FILE. Exits on -h.
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                print_usage
                exit 0
                ;;
            --)
                shift
                if [[ $# -gt 0 ]]; then
                    TREE_FILE=$1
                    shift
                fi
                break
                ;;
            -*)
                echo "error: unknown option: $1" >&2
                print_usage >&2
                exit 1
                ;;
            *)
                if [[ -n ${TREE_FILE:-} ]]; then
                    echo "error: too many arguments" >&2
                    print_usage >&2
                    exit 1
                fi
                TREE_FILE=$1
                shift
                ;;
        esac
    done
}

# Top-level entry: validate input and TREE_INDENT_CHAR, parse file into level/label
# arrays, then for each root (level 0) find subtree end and emit that subtree.
# Multiple roots are separated by a blank line in output.
tree_print_from_file() {
    local input=$1
    local -a tree_levels=()
    local -a tree_labels=()
    local i=0
    local next_root
    local first_tree=1

    [[ -n $input ]] || {
        echo "missing input file" >&2
        return 1
    }

    [[ -f $input ]] || {
        echo "not a regular file (or file not found): $input" >&2
        return 1
    }
    [[ -r $input ]] || {
        echo "cannot read file: $input" >&2
        return 1
    }

    [[ -n $TREE_INDENT_CHAR ]] || {
        echo 'TREE_INDENT_CHAR must not be empty' >&2
        return 1
    }

    tree_parse_file "$input" tree_levels tree_labels || return 1
    (( ${#tree_levels[@]} == 0 )) && return 0

    while (( i < ${#tree_levels[@]} )); do
        (( tree_levels[i] == 0 )) || {
            echo "invalid tree: node without valid root before index $i" >&2
            return 1
        }

        (( first_tree )) || echo
        first_tree=0

        tree_subtree_end tree_levels "$i" next_root
        tree_emit_node tree_levels tree_labels "$i" '' 1 1 "$next_root" || return 1
        i=$next_root
    done
}

# Read input file and fill two nameref arrays: levels (depth per node) and labels (trimmed line text).
# Skips empty lines and lines starting with #. Indent is counted in units of TREE_INDENT_CHAR;
# first valid line must be level 0, and level may only increase by 0 or 1. Used by tree_print_from_file.
tree_parse_file() {
    local input=$1
    local levels_name=$2
    local labels_name=$3
    declare -n levels_ref=$levels_name
    declare -n labels_ref=$labels_name

    local line
    local text
    local level
    local prev_level=-1
    local line_no=0

    while IFS= read -r line || [[ -n $line ]]; do
        (( line_no++ ))

        [[ $line =~ ^[[:space:]]*$ ]] && continue
        [[ $line =~ ^[[:space:]]*# ]] && continue

        text=$line
        level=0

        while [[ $text == "$TREE_INDENT_CHAR"* ]]; do
            text=${text#"$TREE_INDENT_CHAR"}
            (( level++ ))
        done

        if (( ${#levels_ref[@]} == 0 )); then
            (( level == 0 )) || {
                echo "invalid tree: first valid node must have no leading indent, line $line_no" >&2
                return 1
            }
        else
            (( level <= prev_level + 1 )) || {
                echo "invalid tree: indentation jumps by more than one level, line $line_no" >&2
                return 1
            }
        fi

        levels_ref+=("$level")
        labels_ref+=("$text")
        prev_level=$level
    done < "$input"
}

# Return in out_name the index past the last descendant of node at start: first i
# (i > start) such that levels_ref[i] <= levels_ref[start]. Used to bound the
# range of direct children when emitting a subtree.
tree_subtree_end() {
    local levels_name=$1
    local start=$2
    local out_name=$3
    declare -n levels_ref=$levels_name
    declare -n out_ref=$out_name

    local i=$(( start + 1 ))

    while (( i < ${#levels_ref[@]} )) && (( levels_ref[i] > levels_ref[start] )); do
        (( i++ ))
    done

    out_ref=$i
}

# Print one node and recursively all its children. idx is current node; prefix is
# the string to the left (built from parent's prefix + "    " or "│   "); is_last
# and is_root control whether we print ├─ or └─ or nothing; subtree_end is the
# index past the last descendant. For each direct child (level == level+1),
# compute child_is_last and recurse. Builds box-drawing tree lines.
tree_emit_node() {
    local levels_name=$1
    local labels_name=$2
    declare -n levels_ref=$levels_name
    declare -n labels_ref=$labels_name

    local idx=$3
    local prefix=$4
    local is_last=$5
    local is_root=$6
    local subtree_end=$7
    local level=${levels_ref[idx]}
    local next_prefix
    local i=$(( idx + 1 ))
    local next
    local child_is_last

    if (( is_root )); then
        echo "${labels_ref[idx]}"
    elif (( is_last )); then
        echo "${prefix}└─${labels_ref[idx]}"
    else
        echo "${prefix}├─${labels_ref[idx]}"
    fi

    if (( is_root )); then
        next_prefix=
    elif (( is_last )); then
        next_prefix="${prefix}    "
    else
        next_prefix="${prefix}│   "
    fi

    while (( i < subtree_end )); do
        (( levels_ref[i] == level + 1 )) || {
            echo "invalid tree: malformed indentation near node: ${labels_ref[i]}" >&2
            return 1
        }

        tree_subtree_end "$levels_name" "$i" next

        child_is_last=1
        if (( next < subtree_end )) && (( levels_ref[next] == level + 1 )); then
            child_is_last=0
        fi

        tree_emit_node "$levels_name" "$labels_name" "$i" "$next_prefix" "$child_is_last" 0 "$next" || return 1
        i=$next
    done
}

# Parse options; require one positional <tree-file>.
parse_args "$@"

[[ -n ${TREE_FILE:-} ]] || {
    echo "error: missing <tree-file>" >&2
    print_usage >&2
    exit 1
}

tree_print_from_file "$TREE_FILE"