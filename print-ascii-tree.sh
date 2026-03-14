#!/usr/bin/env bash

set -o pipefail

: "${TREE_INDENT_CHAR:=$'\t'}"

tree_print_from_file() {
    local input=$1
    local -a tree_levels=()
    local -a tree_labels=()

    [[ -n $input ]] || {
        echo "missing input file" >&2
        return 1
    }

    [[ -r $input ]] || {
        echo "cannot read file: $input" >&2
        return 1
    }

    tree_parse_file "$input" tree_levels tree_labels || return 1
    (( ${#tree_levels[@]} == 0 )) && return 0

    tree_emit_node tree_levels tree_labels 0 '' 1 1
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
    local indent_prefix

    [[ -n $TREE_INDENT_CHAR ]] || {
        echo 'TREE_INDENT_CHAR must not be empty' >&2
        return 1
    }

    while IFS= read -r line || [[ -n $line ]]; do
        (( line_no++ ))

        [[ $line =~ ^[[:space:]]*$ ]] && continue
        [[ $line =~ ^[[:space:]]*# ]] && continue

        text=$line
        level=0
        indent_prefix=

        while [[ $text == "$TREE_INDENT_CHAR"* ]]; do
            text=${text#"$TREE_INDENT_CHAR"}
            indent_prefix+=$TREE_INDENT_CHAR
            (( level++ ))
        done

        [[ $text =~ ^[[:space:]] ]] && {
            echo "invalid tree: malformed indentation, line $line_no" >&2
            return 1
        }

        if (( ${#levels_ref[@]} == 0 )); then
            (( level == 0 )) || {
                echo "invalid tree: first node must have no leading indent, line $line_no" >&2
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

    while (( i < ${#levels_ref[@]} )) && (( levels_ref[i] > level )); do
        (( levels_ref[i] == level + 1 )) || {
            echo "invalid tree: malformed indentation near node: ${labels_ref[i]}" >&2
            return 1
        }

        tree_subtree_end "$levels_name" "$i" next

        child_is_last=1
        if (( next < ${#levels_ref[@]} )) && (( levels_ref[next] == level + 1 )); then
            child_is_last=0
        fi

        tree_emit_node "$levels_name" "$labels_name" "$i" "$next_prefix" "$child_is_last" 0 || return 1
        i=$next
    done
}

[[ -z $1 ]] && {
    echo "usage: $0 <tree-file>" >&2
    exit 1
}

tree_print_from_file "$1"