#!/bin/bash
# Quick GPU health snapshot — temperature, memory, ECC, power, clocks
# Works on any node with nvidia-smi. Exit 1 if any critical issue found.
# Includes GPU count verification against lspci to detect fallen-off-bus issues.

set -euo pipefail

RED='\033[0;31m'; YEL='\033[0;33m'; GRN='\033[0;32m'; RST='\033[0m'
ISSUES=0

echo "=== GPU Health Check: $(hostname) @ $(date '+%Y-%m-%d %H:%M:%S') ==="
echo ""

declare -A ONLINE_GPUS
declare -A GPU_PCI_MAP

NVIDIA_SMI_COUNT=$(nvidia-smi --query-gpu=index --format=csv,noheader | wc -l)
LSPCI_COUNT=$(lspci -nn | grep -c '\[10de:' || true)

echo "--- GPU Count Verification ---"
echo -e "PCIe (lspci) NVIDIA devices: ${GRN}$LSPCI_COUNT${RST}"
echo -e "NVIDIA Driver (nvidia-smi) GPUs: ${GRN}$NVIDIA_SMI_COUNT${RST}"

normalize_pci() {
    local addr="$1"
    echo "$addr" | sed 's/^0000://; s/^0*//; s/^://' | cut -d'.' -f1
}

if (( LSPCI_COUNT != NVIDIA_SMI_COUNT )); then
    echo -e "${RED}⚠  MISMATCH: $LSPCI_COUNT devices on PCIe bus, but only $NVIDIA_SMI_COUNT visible to nvidia-smi!${RST}"
    (( ISSUES++ )) || true

    echo ""
    echo "--- PCIe Bus Devices ---"
    while IFS= read -r line; do
        pci_addr=$(echo "$line" | awk '{print $1}')
        echo "  $line"
    done < <(lspci -nn | grep '\[10de:')

    echo ""
    echo "--- Online GPUs (nvidia-smi) ---"
    while IFS=',' read -r idx bus_id name; do
        idx=$(echo "$idx" | xargs)
        bus_id=$(echo "$bus_id" | xargs)
        name=$(echo "$name" | xargs)
        ONLINE_GPUS[$idx]=1
        normalized=$(normalize_pci "$bus_id")
        GPU_PCI_MAP[$normalized]=1
        echo "  GPU $idx: $bus_id ($name)"
    done < <(nvidia-smi --query-gpu=index,pci.bus_id,name --format=csv,noheader)

    echo ""
    echo -e "${RED}--- Missing GPUs (Fallen off the bus) ---${RST}"
    while IFS= read -r line; do
        pci_addr=$(echo "$line" | awk '{print $1}')
        normalized=$(normalize_pci "$pci_addr")
        if [[ -z "${GPU_PCI_MAP[$normalized]}" ]]; then
            echo -e "  ${RED}MISSING: $line${RST}"
        fi
    done < <(lspci -nn | grep '\[10de:')
    echo ""
fi

MAX_INDEX=$(nvidia-smi --query-gpu=index --format=csv,noheader | sort -n | tail -1 || echo "-1")
if (( MAX_INDEX >= 0 )); then
    expected_count=$(( MAX_INDEX + 1 ))
    if (( NVIDIA_SMI_COUNT != expected_count )); then
        echo -e "${YEL}⚠  GPU index gap detected: max index=$MAX_INDEX, but only $NVIDIA_SMI_COUNT GPUs online${RST}"
        echo -e "${YEL}   Missing GPU indices:${RST}"
        for (( i=0; i<=MAX_INDEX; i++ )); do
            if [[ -z "${ONLINE_GPUS[$i]}" ]]; then
                echo -e "     ${RED}GPU $i: OFFLINE${RST}"
            fi
        done
        (( ISSUES++ )) || true
    fi
fi

echo ""
echo "--- GPU Status ---"
while IFS=',' read -r idx name drv temp mem_used mem_total util ecc_unc pwr pwr_lim clk pstate; do
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
done < <(nvidia-smi --query-gpu=index,name,driver_version,temperature.gpu,\
    memory.used,memory.total,utilization.gpu,ecc.errors.uncorrected.volatile.total,\
    power.draw,power.limit,clocks.current.sm,pstate \
    --format=csv,noheader,nounits)

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
# Check for fallen off bus events
FALLEN_COUNT=$(dmesg 2>/dev/null | grep -c "fallen off the bus" || true)
if (( FALLEN_COUNT > 0 )); then
    echo -e "${RED}⚠  $FALLEN_COUNT GPU fallen-off-bus event(s) in dmesg history:${RST}"
    dmesg 2>/dev/null | grep "fallen off the bus" | tail -3
    (( ISSUES++ )) || true
fi

echo ""
if (( ISSUES > 0 )); then
    echo -e "${RED}RESULT: $ISSUES issue(s) detected.${RST}"
    exit 1
else
    echo -e "${GRN}RESULT: All GPUs healthy.${RST}"
fi