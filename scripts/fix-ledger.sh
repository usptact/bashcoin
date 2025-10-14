#!/bin/bash

# Helper script to fix ledger corruption issues

NODE_ID=${NODE_ID:-"node1"}
DATA_DIR="/data"
LEDGER_DIR="${DATA_DIR}/ledger"

# Show help
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    cat << 'EOF'
BashCoin - Ledger Repair Tool

Description:
    Repairs corrupted ledger files by:
    - Removing empty lines
    - Removing invalid JSON entries
    - Creating backup before fixing
    - Recalculating balances

Usage:
    fix-ledger.sh

Examples:
    # Repair ledger
    /scripts/fix-ledger.sh

When to use:
    - After JSON parsing errors
    - If balances seem incorrect
    - After ledger corruption
    - Before manual recovery

Notes:
    - Always creates a backup first
    - Reports number of valid/invalid lines
    - Safe to run multiple times

EOF
    exit 0
fi

echo "BashCoin Ledger Repair Tool"
echo "============================="
echo ""

if [ ! -f "${LEDGER_DIR}/transactions.jsonl" ]; then
    echo "No ledger file found. Nothing to repair."
    exit 0
fi

# Backup the current ledger
BACKUP_FILE="${LEDGER_DIR}/transactions.jsonl.backup.$(date +%Y%m%d_%H%M%S)"
echo "Creating backup: ${BACKUP_FILE}"
cp "${LEDGER_DIR}/transactions.jsonl" "${BACKUP_FILE}"

# Clean the ledger file
echo "Cleaning ledger file..."
TEMP_FILE="${LEDGER_DIR}/transactions.jsonl.tmp"
> "${TEMP_FILE}"

LINE_NUM=0
VALID_LINES=0
INVALID_LINES=0

while IFS= read -r line; do
    LINE_NUM=$((LINE_NUM + 1))
    
    # Skip empty lines
    if [ -z "$line" ]; then
        INVALID_LINES=$((INVALID_LINES + 1))
        continue
    fi
    
    # Validate JSON
    if echo "${line}" | jq empty 2>/dev/null; then
        echo "${line}" >> "${TEMP_FILE}"
        VALID_LINES=$((VALID_LINES + 1))
    else
        echo "Line ${LINE_NUM}: Invalid JSON - skipped"
        INVALID_LINES=$((INVALID_LINES + 1))
    fi
done < "${LEDGER_DIR}/transactions.jsonl"

# Replace the original file with cleaned version
mv "${TEMP_FILE}" "${LEDGER_DIR}/transactions.jsonl"

echo ""
echo "Repair complete!"
echo "==============="
echo "Total lines processed: ${LINE_NUM}"
echo "Valid transactions: ${VALID_LINES}"
echo "Invalid/empty lines removed: ${INVALID_LINES}"
echo "Backup saved to: ${BACKUP_FILE}"
echo ""

# Recalculate balances
echo "Recalculating balances..."
/scripts/consensus.sh calculate

echo ""
echo "Done! Your ledger has been repaired."

