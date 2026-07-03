#!/bin/bash
# Map GPU index → PID → username → command.
# Shows who is using which GPU right now.
#
# Usage:
#   ./gpu-process-map.sh           # all GPUs
#   ./gpu-process-map.sh --json    # JSON output

set -euo pipefail

JSON=${1:-}

declare -A GPU_NAME
while IFS=',' read -r idx name; do
    GPU_NAME[$idx]=$(echo "$name" | xargs)
done < <(nvidia-smi --query-gpu=index,name --format=csv,noheader)

if [[ "$JSON" == "--json" ]]; then
    echo "["
    first=1
fi

nvidia-smi --query-compute-apps=pid,used_gpu_memory,gpu_uuid \
    --format=csv,noheader | while IFS=',' read -r pid mem uuid; do

    pid=$(echo "$pid" | xargs)
    mem=$(echo "$mem" | xargs)

    # Resolve UUID → index
    idx=$(nvidia-smi --query-gpu=index,uuid --format=csv,noheader \
        | grep "$uuid" | cut -d',' -f1 | xargs)
    name="${GPU_NAME[$idx]:-unknown}"

    user=$(ps -o user= -p "$pid" 2>/dev/null | xargs || echo "?")
    cmd=$(ps -o comm= -p "$pid"  2>/dev/null | xargs || echo "?")
    full=$(ps -o args= -p "$pid" 2>/dev/null | cut -c1-80 || echo "?")

    if [[ "$JSON" == "--json" ]]; then
        [[ $first -eq 0 ]] && echo ","
        printf '  {"gpu":%s,"gpu_name":"%s","pid":%s,"user":"%s","cmd":"%s","mem_mb":"%s"}' \
            "$idx" "$name" "$pid" "$user" "$cmd" "$mem"
        first=0
    else
        printf "GPU %-2s  %-28s  PID %-7s  %-12s  %-20s  %s MiB\n" \
            "$idx" "$name" "$pid" "$user" "$cmd" "$mem"
    fi
done

if [[ "$JSON" == "--json" ]]; then echo ""; echo "]"; fi
