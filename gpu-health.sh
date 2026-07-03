#!/bin/bash
# Quick GPU health snapshot — temperature, memory, ECC, power, clocks
# Works on any node with nvidia-smi. Exit 1 if any critical issue found.

set -euo pipefail

RED='\033[0;31m'; YEL='\033[0;33m'; GRN='\033[0;32m'; RST='\033[0m'
ISSUES=0

echo "=== GPU Health Check: $(hostname) @ $(date '+%Y-%m-%d %H:%M:%S') ==="
echo ""

nvidia-smi --query-gpu=index,name,driver_version,temperature.gpu,\
memory.used,memory.total,utilization.gpu,ecc.errors.uncorrected.volatile.total,\
power.draw,power.limit,clocks.current.sm,pstate \
--format=csv,noheader,nounits | while IFS=',' read -r idx name drv temp \
    mem_used mem_total util ecc_unc pwr pwr_lim clk pstate; do

    name=$(echo "$name" | xargs)
    temp=$(echo "$temp" | xargs)
    ecc_unc=$(echo "$ecc_unc" | xargs)
    pstate=$(echo "$pstate" | xargs)

    flag=""
    if   [[ "$ecc_unc" =~ ^[0-9]+$ ]] && (( ecc_unc > 0 )); then
        flag="${RED}[ECC UNCORRECTED: $ecc_unc]${RST}"; (( ISSUES++ )) || true
    elif [[ "$temp" =~ ^[0-9]+$ ]]    && (( temp >= 90 )); then
        flag="${RED}[TEMP CRITICAL: ${temp}°C]${RST}"; (( ISSUES++ )) || true
    elif [[ "$temp" =~ ^[0-9]+$ ]]    && (( temp >= 80 )); then
        flag="${YEL}[TEMP HIGH: ${temp}°C]${RST}"
    fi

    printf "GPU %-2s  %-30s  %3s°C  %6s/%6s MB  %3s%%  ECC:%-4s  %5sW/%5sW  %s MHz  %s %s\n" \
        "$idx" "$name" "$temp" \
        "$(echo $mem_used|xargs)" "$(echo $mem_total|xargs)" \
        "$(echo $util|xargs)" "$ecc_unc" \
        "$(echo $pwr|xargs)" "$(echo $pwr_lim|xargs)" \
        "$(echo $clk|xargs)" "$pstate" "$flag"
done

echo ""
# Check for Xid errors in dmesg (last 10 min)
XID_COUNT=$(dmesg --since "10 minutes ago" 2>/dev/null | grep -c "NVRM.*Xid" || true)
if (( XID_COUNT > 0 )); then
    echo -e "${RED}⚠  $XID_COUNT Xid error(s) in dmesg (last 10 min):${RST}"
    dmesg --since "10 minutes ago" 2>/dev/null | grep "NVRM.*Xid" | tail -5
    (( ISSUES++ )) || true
else
    echo -e "${GRN}✓  No Xid errors in dmesg (last 10 min)${RST}"
fi

echo ""
if (( ISSUES > 0 )); then
    echo -e "${RED}RESULT: $ISSUES issue(s) detected.${RST}"
    exit 1
else
    echo -e "${GRN}RESULT: All GPUs healthy.${RST}"
fi
