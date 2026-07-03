#!/bin/bash
# Watch kernel ring buffer for NVIDIA Xid GPU errors in real time.
# Prints a clean summary line for each event with timestamp and GPU index.
# Uses journalctl for persistent history (survives reboots), falls back to dmesg.
#
# Usage:
#   ./xid-watch.sh                  # watch live
#   ./xid-watch.sh --history 1h     # show Xid events from the past 1h
#   ./xid-watch.sh --history 24h

set -euo pipefail

RED='\033[0;31m'; YEL='\033[0;33m'; CYN='\033[0;36m'; RST='\033[0m'

# Xid codes that are critical (GPU reset / double-bit ECC / fall-off-bus)
CRITICAL_XIDS="45 48 56 57 58 61 63 64 68 69 74 79 80 92 94 95 119 120"

is_critical() {
    local xid=$1
    for c in $CRITICAL_XIDS; do [[ "$c" == "$xid" ]] && return 0; done
    return 1
}

format_xid() {
    local line=$1
    local ts gpu xid

    ts=$(echo "$line"  | grep -oP '^\S+ \S+ \S+' | head -1 || \
         echo "$line"  | grep -oP '\[\s*\d+\.\d+\]' | head -1 || echo "")

    gpu=$(echo "$line" | grep -oP 'PCI:\K[0-9a-f:\.]+' | head -1 || \
          echo "$line" | grep -oP 'GPU-[0-9a-f\-]+' | head -1 || echo "?")

    xid=$(echo "$line" | grep -oP 'Xid \(.*?\): \K\d+' | head -1 || \
          echo "$line" | grep -oP 'Xid: \K\d+'         | head -1 || echo "?")

    if is_critical "$xid"; then
        echo -e "${RED}[CRITICAL Xid $xid]${RST} GPU=$gpu $ts"
    else
        echo -e "${YEL}[Xid $xid]${RST} GPU=$gpu $ts"
    fi
}

use_journalctl() {
    command -v journalctl >/dev/null 2>&1
}

if [[ "${1:-}" == "--history" ]]; then
    since="${2:-1h}"
    echo -e "${CYN}Xid events in the past $since on $(hostname):${RST}"
    count=0

    if use_journalctl; then
        echo -e "${CYN}  (using journalctl for persistent history)${RST}"
        while IFS= read -r line; do
            format_xid "$line"
            (( count++ )) || true
        done < <(journalctl -k --since "$since ago" --no-pager 2>/dev/null | grep "NVRM.*Xid" || true)
    else
        echo -e "${YEL}  (journalctl not available, using dmesg)${RST}"
        while IFS= read -r line; do
            format_xid "$line"
            (( count++ )) || true
        done < <(dmesg --since "$since ago" 2>/dev/null | grep "NVRM.*Xid" || true)
    fi

    echo ""
    echo "$count Xid event(s) found."
else
    echo -e "${CYN}Watching for Xid errors on $(hostname) — Ctrl+C to stop${RST}"

    if use_journalctl; then
        journalctl -k -f --no-pager 2>/dev/null | grep --line-buffered "NVRM.*Xid" | while IFS= read -r line; do
            format_xid "$line"
        done
    else
        dmesg -W 2>/dev/null | grep --line-buffered "NVRM.*Xid" | while IFS= read -r line; do
            format_xid "$line"
        done
    fi
fi
