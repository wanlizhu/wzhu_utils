#!/usr/bin/env bash
set -o pipefail

print_microbench_output_as_csv() {
    if [[ ! -e "$1" ]]; then 
        echo "Error: result file doesn't exist: $1"
        return 1
    fi 

    echo "Test case,numeric,unit" 
    if [[ ! -z $(cat "$1" | grep '\[REST: ') ]]; then 
        cat "$1" | grep '\[REST: ' | sed 's/test_case=/^/g' | sed 's/, numeric=/^/g' | sed 's/, units=/^/g' | sed 's/]/^/g' | awk -F'\\^' '{printf "%s,%.0f,%s\n", $2, $3, $4}'
    else
        cat "$1" | grep '\[Test_case: ' | sed 's/: /^/g' | sed 's/ = /^/g' | sed 's/ /^/g' | sed 's/]/^/g' | awk -F'\\^' '{printf "%s,%.0f,%s\n", $2, $3, $4}'
    fi 
}

a_over_b() {
    python3 -c '
from decimal import Decimal, getcontext
import sys
try:
    getcontext().prec = 100
    a = Decimal(sys.argv[1])
    b = Decimal(sys.argv[2])
    result = a / b
    print(f"{result}")
except Exception:
    print("N/A")
' $1 $2 
}

if [[ $1 == "-h" || $1 == "--help" ]]; then 
    echo "Usage 1: $(basename $0) -- run for new result"
    echo "Usage 2: $(basename $0) output1 [output2] -- process existing results"
    exit 1
fi 

if [[ -z $1 ]]; then 
    echo_in_cyan "Saving results to ~/microbench_results[.txt|.csv]"
    nvidia_smi_max_clocks
    nvperf_vulkan -REST -nullDisplay all | tee ~/microbench_results.txt
    nvidia_smi_max_clocks reset 

    if [[ -s ~/microbench_results.txt ]]; then 
        $0 $(realpath ~/microbench_results.txt) | tee ~/microbench_results.csv
    fi 
    echo_in_green "Generated ~/microbench_results.txt"
    echo_in_green "Generated ~/microbench_results.csv"
else 
    if [[ -z "$2" ]]; then 
        print_microbench_output_as_csv "$1"
    else 
        print_microbench_output_as_csv "$1" >/tmp/csv1
        print_microbench_output_as_csv "$2" >/tmp/csv2
        echo "Test case,numeric1,numeric2,numeric2/numeric1,unit"
        while IFS= read -r line2; do 
            [[ $line2 == "Test case"* ]] && continue 
            IFS=, read -r name2 value2 unit2 <<< "$line2"
            line1=$(cat /tmp/csv1 | grep "$name2")
            [[ -z $line1 ]] && continue 
            IFS=, read -r name1 value1 unit1 <<< "$line1"
            rate=$(a_over_b $value2 $value1)
            [[ $rate == "N/A" ]] && continue 
            echo "$name2,$value1,$value2,$rate,$unit2"
        done </tmp/csv2 
    fi 
fi 