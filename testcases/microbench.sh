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
from decimal import Decimal, getcontext, InvalidOperation
import sys
try:
    getcontext().prec = 100
    a = Decimal(sys.argv[1])
    b = Decimal(sys.argv[2])
    result = a / b * 100
    print(f"{result:.2f}%")
except Exception:
    print("N/A")
' $1 $2 
}

if [[ -z $1 || ! -e $1 ]]; then 
    echo "Usage: $(basename $0) output1 [output2]"
    exit 1
fi 

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