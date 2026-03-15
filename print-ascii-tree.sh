#!/usr/bin/env bash

set -o pipefail

: "${TREE_INDENT_CHAR:=$'\t'}"

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

[[ -n $1 ]] || {
    echo "usage: $0 <tree-file>" >&2
    exit 1
}

tree_print_from_file "$1"