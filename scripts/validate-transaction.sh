#!/bin/bash

NODE_ID=${NODE_ID:-"node1"}
DATA_DIR="/data"
LEDGER_DIR="${DATA_DIR}/ledger"
PENDING_DIR="${DATA_DIR}/pending"

# Show help
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    cat << 'EOF'
BashCoin - Validate Transaction

Description:
    Validates a transaction by checking:
    - Hash integrity
    - GPG signature
    - Nonce uniqueness (double-spend prevention)
    - Sender balance
    
    Optionally adds the transaction to the ledger if valid.

Usage:
    validate-transaction.sh <transaction_file> [--add-to-ledger]

Arguments:
    transaction_file    Path to JSON file containing the transaction
    --add-to-ledger     Optional: Add to ledger if validation succeeds

Examples:
    # Just validate (no side effects)
    /scripts/validate-transaction.sh /tmp/tx.json
    
    # Validate and add to ledger if valid
    /scripts/validate-transaction.sh /tmp/tx.json --add-to-ledger

Notes:
    - Without --add-to-ledger flag, this is a pure validation function
    - Used by create-transaction.sh (without flag) and ledger-daemon.sh (with flag)

EOF
    exit 0
fi

# Check if transaction file provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <transaction_file> [--add-to-ledger]"
    echo "Run with --help for more information"
    exit 1
fi

TX_FILE=$1
ADD_TO_LEDGER=false

# Check if we should add to ledger
if [ "$2" == "--add-to-ledger" ]; then
    ADD_TO_LEDGER=true
fi

if [ ! -f "${TX_FILE}" ]; then
    echo "Error: Transaction file not found: ${TX_FILE}"
    exit 1
fi

# Parse transaction
FROM=$(jq -r '.from' "${TX_FILE}" 2>/dev/null)
TO=$(jq -r '.to' "${TX_FILE}" 2>/dev/null)
AMOUNT=$(jq -r '.amount' "${TX_FILE}" 2>/dev/null)
NONCE=$(jq -r '.nonce' "${TX_FILE}" 2>/dev/null)
TIMESTAMP=$(jq -r '.timestamp' "${TX_FILE}" 2>/dev/null)
TX_HASH=$(jq -r '.hash' "${TX_FILE}" 2>/dev/null)
SIGNATURE=$(jq -r '.signature' "${TX_FILE}" 2>/dev/null)

echo "Validating transaction ${TX_HASH}..."

# Basic validation
if [ -z "${FROM}" ] || [ -z "${TO}" ] || [ -z "${AMOUNT}" ] || [ -z "${NONCE}" ]; then
    echo "Error: Missing required fields"
    exit 1
fi

# Validate amount is positive
if (( $(echo "${AMOUNT} <= 0" | bc -l) )); then
    echo "Error: Amount must be positive"
    exit 1
fi

# Verify hash
EXPECTED_HASH=$(echo -n "${FROM}|${TO}|${AMOUNT}|${NONCE}|${TIMESTAMP}" | sha256sum | cut -d' ' -f1)
if [ "${TX_HASH}" != "${EXPECTED_HASH}" ]; then
    echo "Error: Transaction hash mismatch"
    exit 1
fi

# Check for double spending - verify nonce is unique
if grep -q "\"nonce\": \"${NONCE}\"" "${LEDGER_DIR}/transactions.jsonl" 2>/dev/null; then
    echo "Error: Duplicate nonce detected (double spending attempt)"
    exit 1
fi

# Verify signature
echo "${SIGNATURE}" | base64 -d > /tmp/sig_${TX_HASH}.asc 2>/dev/null
if gpg --verify /tmp/sig_${TX_HASH}.asc 2>&1 | grep -q "Good signature from \"${FROM}"; then
    echo "Signature verified"
else
    # Try to verify with email format
    if echo -n "${TX_HASH}" | gpg --verify /tmp/sig_${TX_HASH}.asc - 2>&1 | grep -q "${FROM}"; then
        echo "Signature verified"
    else
        echo "Error: Invalid signature"
        rm -f /tmp/sig_${TX_HASH}.asc
        exit 1
    fi
fi
rm -f /tmp/sig_${TX_HASH}.asc

# Check sender balance (recalculate first)
/scripts/consensus.sh calculate > /dev/null 2>&1

if [ -f "${LEDGER_DIR}/balances.json" ]; then
    SENDER_BALANCE=$(jq -r ".\"${FROM}\" // 0" "${LEDGER_DIR}/balances.json")
    
    if (( $(echo "${SENDER_BALANCE} < ${AMOUNT}" | bc -l) )); then
        echo "Error: Insufficient balance. ${FROM} has ${SENDER_BALANCE}, needs ${AMOUNT}"
        exit 1
    fi
else
    echo "Warning: Could not verify balance"
fi

# All validations passed
echo "Transaction validation successful!"

# Add to ledger if requested
if [ "$ADD_TO_LEDGER" == "true" ]; then
    echo "Adding transaction to ledger..."
    
    # Append to ledger with lock (ensure compact JSON format)
    (
        flock -x 200
        jq -c . "${TX_FILE}" >> "${LEDGER_DIR}/transactions.jsonl"
    ) 200>/var/lock/ledger.lock
    
    # Update balances
    /scripts/consensus.sh calculate > /dev/null 2>&1
    
    # Remove from pending if it's there
    rm -f "${PENDING_DIR}/tx_${TX_HASH}.json"
    
    echo "Transaction added to ledger"
fi

exit 0

