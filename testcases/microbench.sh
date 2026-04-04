#!/usr/bin/env bash
set -o pipefail

T254_PERFTEST=1

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

config_horizon_for_perftest() {
    sandbag_tool_path=$(command -v sandbag-tool)
    LockToRatedTdp_path=$(command -v LockToRatedTdp)
    perfdebug_path=$(command -v perfdebug)
    [[ ! -e $sandbag_tool_path ]] && { echo_in_red "Failed to find command sandbag-tool which is available under drivers/unix/testutils/sandbag-tool/_out/..."; exit 1; }
    [[ ! -e $LockToRatedTdp_path ]] && { echo_in_red "Failed to find command LockToRatedTdp which is available under drivers/unix/testutils/lock-to-rated-tdp/_out/..."; exit 1; }
    [[ ! -e $perfdebug_path ]] && { echo_in_red "Failed to find command perfdebug which is available under https://dvstransfer.nvidia.com/dvsshare/dvs-binaries-auto1/SW-apps_Debug_Linux_$(uname -m | sed 's/x86_64/AMD64/g')_Perfdebug/"; exit 1; } 
    echo "[1] $sandbag_tool_path"
    echo "[2] $LockToRatedTdp_path"
    echo "[3] $perfdebug_path"
    read -p "Press [Enter] to use selected tools: "

    if [[ $(uname -m) == aarch64 ]]; then 
        echo_in_cyan "Setting up horizon board for perftest ..."
        sudo nvidia-smi -pm 1
        [[ ! -z $(command -v nvidia-persistenced) ]] && sudo nvidia-persistenced
        sudo `which sandbag-tool` -unsandbag
        sudo `which LockToRatedTdp` -lock
        sudo `which perfdebug` --lock_loose  set pstateId P0
        sudo `which perfdebug` --lock_strict set dramclkkHz  4266000
        sudo `which perfdebug` --lock_strict set gpcclkkHz   2000000 
        sudo `which perfdebug` --lock_loose  set xbarclkkHz  1800000 
        sudo `which perfdebug` --lock_loose  set sysclkkHz   1800000
        sudo `which perfdebug` --force_regime ffr 
        sudo `which perfdebug` --getclocks
    else # The x86_64 proxy system (GB203-as-T254)
        echo_in_cyan "Setting up GB203-as-T254 proxy for perftest ..."
        sudo nvidia-smi -pm 1
        [[ ! -z $(command -v nvidia-persistenced) ]] && sudo nvidia-persistenced
        sudo `which sandbag-tool` -unsandbag
        sudo `which LockToRatedTdp` -lock
        sudo `which perfdebug` --lock_loose  set pstateId P0
        sudo `which perfdebug` --lock_strict set dramclkkHz  8000000
        sudo `which perfdebug` --lock_strict set gpcclkkHz   1875000 
        sudo `which perfdebug` --lock_loose  set xbarclkkHz  2250000 
        sudo `which perfdebug` --lock_loose  set sysclkkHz   1695000
        sudo `which perfdebug` --force_regime ffr 
        sudo `which perfdebug` --getclocks
    fi 
}

if [[ $1 == "-h" || $1 == "--help" ]]; then 
    echo "Usage 1: $(basename $0) -- run for new result"
    echo "Usage 2: $(basename $0) output1 [output2] -- process existing results"
    exit 1
fi 

if [[ -z $1 ]]; then 
    echo_in_cyan "Saving results to ~/microbench_results[.txt|.csv]"
    [[ $T254_PERFTEST == 1 ]] && config_horizon_for_perftest || nvidia_smi_max_clocks
    nvperf_vulkan -REST -nullDisplay all | tee ~/microbench_results.txt
    [[ $T254_PERFTEST == 1 ]] || nvidia_smi_max_clocks reset 

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