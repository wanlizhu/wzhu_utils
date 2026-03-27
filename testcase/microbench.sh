#!/usr/bin/env bash
set -o pipefail

filename_stem() {
    local name=${1##*/}
    if [[ $name == .* && $name != *.*.* ]]; then
        echo "$name"
    else 
        echo "${name%.*}"
    fi 
}

filename_replace_ext() {
    local dir name stem ext
    dir=${1%/*}
    name=${1##*/}
    stem=${name%.*}
    ext=$2
    [[ $1 != */* ]] && dir=
    if [[ -n $dir ]]; then
        echo "$dir/$stem.$ext"
    else
        echo "$stem.$ext"
    fi
}

post_process_results() {
    awk '
    function trim(s) {
        sub(/^[[:space:]]+/, "", s)
        sub(/[[:space:]]+$/, "", s)
        return s
    }

    function csv_escape(s, t) {
        t = s
        gsub(/"/, "\"\"", t)
        return "\"" t "\""
    }

    BEGIN {
        started = 0
        current_test = ""
        case_index = 0
        print "index,test_name,test_case_name,test_value,test_unit,other_tags"
    }

    {
        line = trim($0)

        if (line ~ /^Running test:[[:space:]]+/) {
            started = 1
            sub(/^Running test:[[:space:]]+/, "", line)
            current_test = trim(line)
            next
        }

        if (!started) {
            next
        }

        if (line !~ /^\[Test_case:/) {
            next
        }

        if (substr(line, 1, 1) != "[" || substr(line, length(line), 1) != "]") {
            next
        }

        content = substr(line, 2, length(line) - 2)
        content = trim(content)
        sub(/^Test_case:[[:space:]]*/, "", content)

        result_sep = ""
        sep_pos = 0

        if (match(content, /[[:space:]]=[[:space:]]/)) {
            result_sep = substr(content, RSTART, RLENGTH)
            sep_pos = RSTART
        } else {
            printf "warning: unable to find result separator: %s\n", $0 > "/dev/stderr"
            next
        }

        tag_part = trim(substr(content, 1, sep_pos - 1))
        result_part = trim(substr(content, sep_pos + length(result_sep)))

        value_sep = index(result_part, " ")
        if (value_sep == 0) {
            printf "warning: unable to parse result value/unit: %s\n", $0 > "/dev/stderr"
            next
        }

        test_value = trim(substr(result_part, 1, value_sep - 1))
        test_unit = trim(substr(result_part, value_sep + 1))

        first_bar = index(tag_part, "|")
        if (first_bar > 0) {
            test_case_name = trim(substr(tag_part, 1, first_bar - 1))
            other_tags = trim(substr(tag_part, first_bar + 1))
        } else {
            test_case_name = trim(tag_part)
            other_tags = ""
        }

        if (current_test != "" && index(test_case_name, current_test ":") != 1) {
            printf "warning: testcase name does not match current test: current_test=%s testcase=%s\n", current_test, test_case_name > "/dev/stderr"
        }

        case_index++

        print \
            case_index "," \
            csv_escape(current_test) "," \
            csv_escape(test_case_name) "," \
            csv_escape(test_value) "," \
            csv_escape(test_unit) "," \
            csv_escape(other_tags)
    }
    ' $1 > $(filename_replace_ext $1 csv)
}

compare_csv_files() {
    awk -F, '
    function trim_quotes(s) {
        sub(/^"/, "", s)
        sub(/"$/, "", s)
        gsub(/""/, "\"", s)
        return s
    }

    function csv_escape(s, t) {
        t = s
        gsub(/"/, "\"\"", t)
        return "\"" t "\""
    }

    NR == FNR {
        if (FNR == 1) {
            next
        }

        test_case_name = trim_quotes($3)
        test_value = trim_quotes($4)

        value2_map[test_case_name] = test_value
        next
    }

    FNR == 1 {
        print \
            "index,test_name,test_case_name,test_value,test_value_file2,delta_pct,test_unit,other_tags"
        next
    }

    {
        idx = $1
        test_name = trim_quotes($2)
        test_case_name = trim_quotes($3)
        test_value = trim_quotes($4)
        test_unit = trim_quotes($5)
        other_tags = trim_quotes($6)

        if (test_case_name in value2_map) {
            test_value_file2 = value2_map[test_case_name]

            if ((test_value + 0) == 0) {
                delta_pct = "N/A"
            } else {
                delta_pct = sprintf("%.2f%%", (test_value_file2 / test_value) * 100)
            }
        } else {
            test_value_file2 = "N/A"
            delta_pct = "N/A"
        }

        print \
            idx "," \
            csv_escape(test_name) "," \
            csv_escape(test_case_name) "," \
            csv_escape(test_value) "," \
            csv_escape(test_value_file2) "," \
            csv_escape(delta_pct) "," \
            csv_escape(test_unit) "," \
            csv_escape(other_tags)
    }
    ' $1 $2 > $3
}

if [[ -f $1 ]]; then
    post_process_results $1
elif [[ $1 == compare ]]; then
    post_process_results $2 || exit 1
    post_process_results $3 || exit 1
    csv_file1=$(filename_replace_ext $2 csv)
    csv_file2=$(filename_replace_ext $3 csv)
    csv_file3=$(filename_stem $csv_file1)_vs_$(filename_stem $csv_file2).csv
    compare_csv_files $csv_file1 $csv_file2 $csv_file3
fi