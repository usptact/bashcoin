#!/bin/bash
set -e

# Load shared membership helpers (defines NODES_CONFIG, NODES_LEDGER, is_member).
source /scripts/nodes-lib.sh

NODE_ID=${NODE_ID:-"node1"}
DATA_DIR="/data"
LEDGER_DIR="${DATA_DIR}/ledger"

# Show help
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    cat << 'EOF'
BashCoin - Create Transaction

Description:
    Creates and broadcasts a transaction to send coins from this node to another node.
    The transaction is signed with this node's GPG key and broadcast to all other nodes.

Usage:
    create-transaction.sh <to_node> <amount>

Arguments:
    to_node     Destination node (any current member; see 'consensus.sh stats')
    amount      Amount of coins to send (must be positive number)

Examples:
    # Send 50 coins to node2
    /scripts/create-transaction.sh node2 50
    
    # Send 123.45 coins to node3
    /scripts/create-transaction.sh node3 123.45

Notes:
    - You must have sufficient balance
    - Transaction is automatically broadcast to all nodes
    - Cannot send to yourself
    - Each transaction has a unique nonce to prevent double-spending

EOF
    exit 0
fi

# Check arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <to_node> <amount>"
    echo "Example: $0 node2 50"
    echo "Run with --help for more information"
    exit 1
fi

TO_NODE=$1
AMOUNT=$2

# Validate inputs
if ! [[ "$AMOUNT" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Error: Amount must be a positive number"
    exit 1
fi

# Check that the destination is a known member (seed or runtime-joined).
if ! is_member "$TO_NODE"; then
    echo "Error: Unknown destination node '${TO_NODE}'."
    echo "Known members: $(get_all_node_ids | tr '\n' ' ')"
    exit 1
fi

if [ "$TO_NODE" == "$NODE_ID" ]; then
    echo "Error: Cannot send coins to yourself"
    exit 1
fi

# Check balance before creating transaction
/scripts/consensus.sh calculate > /dev/null 2>&1

if [ -f "${LEDGER_DIR}/balances.json" ]; then
    CURRENT_BALANCE=$(jq -r ".\"${NODE_ID}\" // 0" "${LEDGER_DIR}/balances.json")
    
    if (( $(echo "${CURRENT_BALANCE} < ${AMOUNT}" | bc -l) )); then
        echo "Error: Insufficient balance. You have ${CURRENT_BALANCE}, need ${AMOUNT}"
        exit 1
    fi
fi

# Generate nonce (hash of timestamp + random data)
NONCE=$(echo "${NODE_ID}-$(date +%s%N)-${RANDOM}" | sha256sum | cut -d' ' -f1)

# Get current timestamp
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Calculate transaction hash (before signing)
TX_DATA="${NODE_ID}|${TO_NODE}|${AMOUNT}|${NONCE}|${TIMESTAMP}"
TX_HASH=$(echo -n "${TX_DATA}" | sha256sum | cut -d' ' -f1)

# Create transaction JSON
TRANSACTION=$(jq -n \
    --arg from "${NODE_ID}" \
    --arg to "${TO_NODE}" \
    --arg amount "${AMOUNT}" \
    --arg nonce "${NONCE}" \
    --arg timestamp "${TIMESTAMP}" \
    --arg hash "${TX_HASH}" \
    '{
        type: "transaction",
        from: $from,
        to: $to,
        amount: ($amount | tonumber),
        nonce: $nonce,
        timestamp: $timestamp,
        hash: $hash
    }')

# Sign the transaction hash with a *detached* signature so verifiers can bind
# the signature to this exact hash (see validate-transaction.sh).
SIGNATURE=$(echo -n "${TX_HASH}" | gpg --armor --detach-sign --local-user "${NODE_ID}@bashcoin.local" 2>/dev/null | base64 -w 0)

# Add signature to transaction
SIGNED_TRANSACTION=$(echo "${TRANSACTION}" | jq --arg sig "${SIGNATURE}" '. + {signature: $sig}')

echo "Transaction created:"
echo "${SIGNED_TRANSACTION}" | jq .

# Save transaction to file for broadcasting (compact JSON, one line)
TX_FILE="${DATA_DIR}/pending/tx_${TX_HASH}.json"
echo "${SIGNED_TRANSACTION}" | jq -c . > "${TX_FILE}"

# Add to our own ledger immediately (we trust ourselves), but do the balance
# check and append atomically under the ledger lock so rapid successive sends
# from this node cannot overspend (the earlier check above is only advisory).
# IMPORTANT: Use -c flag for compact JSON (JSONL format).
echo "Adding transaction to local ledger..."
(
    flock -x 200

    /scripts/consensus.sh calculate > /dev/null 2>&1
    LOCKED_BALANCE=$(jq -r ".\"${NODE_ID}\" // 0" "${LEDGER_DIR}/balances.json" 2>/dev/null)
    if (( $(echo "${LOCKED_BALANCE:-0} < ${AMOUNT}" | bc -l) )); then
        echo "Error: Insufficient balance. You have ${LOCKED_BALANCE}, need ${AMOUNT}"
        exit 11
    fi

    echo "${SIGNED_TRANSACTION}" | jq -c . >> "${LEDGER_DIR}/transactions.jsonl"

    # Update balances to reflect the newly committed transaction.
    /scripts/consensus.sh calculate > /dev/null 2>&1
) 200>/var/lock/ledger.lock
COMMIT_RC=$?

if [ "${COMMIT_RC}" -ne 0 ]; then
    echo "Transaction aborted before broadcast (code ${COMMIT_RC})"
    rm -f "${TX_FILE}"
    exit 1
fi

# Broadcast to all other nodes
echo "Broadcasting transaction to network..."
/scripts/broadcast.sh "${TX_FILE}"

# Clean up pending file after broadcast
rm -f "${TX_FILE}"

echo "Transaction broadcast complete!"
echo "Transaction hash: ${TX_HASH}"

