#!/usr/bin/env bash
set -o pipefail

print_microbench_output_as_csv() {
    if [[ ! -e "$1" ]]; then 
        echo "Error: result file doesn't exist: $1"
        return 1
    fi 

    echo "Test case,numeric,unit" 
    if [[ ! -z $(cat "$1" | grep '\[REST: ') ]]; then 
        cat "$1" | grep '\[REST: ' | awk -F'[=,\\]]' '{print $2 "," $4 "," $6}'
    else
        cat "$1" | grep '\[Test_case: ' | awk -F' *= *|]|[[:space:]]+' '{printf "%s,%.0f,%s\n", $2, $3, $4}'
    fi 
}

if [[ -z $1 || ! -e $1 ]]; then 
    echo "Usage: $(basename $0) output1 [output2]"
    exit 1
fi 

if [[ -z "$2" ]]; then 
    print_microbench_output_as_csv "$1"
else 
    read -e -i "$(basename $1)" -p "Enter a short name for $(basename $1): " csv1_name 
    read -e -i "$(basename $2)" -p "Enter a short name for $(basename $2): " csv2_name 
    print_microbench_output_as_csv "$1" >/tmp/csv1
    print_microbench_output_as_csv "$2" >/tmp/csv2
    awk -F, '
        BEGIN {
            OFS = ","
        }
        NR == FNR {
            csv1_col1[FNR] = $1
            csv1_col2[FNR] = $2
            csv1_col3[FNR] = $3
            next
        }
        FNR == 1 {
            print csv1_col1[FNR], "numeric 1", "numeric 2", "num2 vs num1", csv1_col3[FNR]
            next
        }
        {
            if (csv1_col2[FNR] + 0 == 0) {
                ratio = "N/A"
            } else {
                ratio = sprintf("%.2f%%", ($2 / csv1_col2[FNR]) * 100)
            }
            print csv1_col1[FNR], csv1_col2[FNR], $2, ratio, csv1_col3[FNR]
        }
    ' /tmp/csv1 /tmp/csv2 > ${csv1_name}_vs_${csv2_name}.csv
fi 