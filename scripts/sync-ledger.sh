#!/bin/bash

# Load shared membership helpers (defines NODES_CONFIG and get_* functions).
source /scripts/nodes-lib.sh

NODE_ID=${NODE_ID:-"node1"}
DATA_DIR="/data"
LEDGER_DIR="${DATA_DIR}/ledger"
TEMP_DIR="/tmp/sync"

# Show help
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    cat << 'EOF'
BashCoin - Ledger Synchronization

Description:
    Performs full ledger synchronization with all other nodes using rsync.
    Fetches ledgers from all nodes, merges them, validates new transactions,
    and adds missing transactions to the local ledger.

Usage:
    sync-ledger.sh

Examples:
    # Sync ledger with all nodes
    /scripts/sync-ledger.sh

When to use:
    - After node restart (to catch up on missed transactions)
    - After network issues
    - For periodic consistency checks
    - When nodes seem out of sync

Notes:
    - Transactions are automatically broadcast via TCP (no sync needed normally)
    - This is mainly for recovery and catch-up scenarios
    - May show "Failed to sync from nodeX" if nodes are still initializing

EOF
    exit 0
fi

echo "Starting ledger synchronization..."

# Create temp directory
mkdir -p "${TEMP_DIR}"

SYNC_COUNT=0

# Collect ledgers from all other nodes listed in the membership config.
for node in $(get_node_ids_except "${NODE_ID}"); do
    NODE_HOST=$(get_node_host "${node}")

    echo "Syncing from ${node} (${NODE_HOST})..."

    # Try to rsync the ledger
    if rsync -az --timeout=10 "rsync://${NODE_HOST}:873/ledger/transactions.jsonl" "${TEMP_DIR}/${node}_transactions.jsonl" 2>/dev/null; then
        echo "✓ Successfully synced from ${node}"
        SYNC_COUNT=$((SYNC_COUNT + 1))
    else
        echo "✗ Failed to sync from ${node} (node may not be ready)"
    fi
done

# Copy our own ledger
if [ -f "${LEDGER_DIR}/transactions.jsonl" ]; then
    cp "${LEDGER_DIR}/transactions.jsonl" "${TEMP_DIR}/${NODE_ID}_transactions.jsonl"
fi

echo ""
echo "Successfully synced from ${SYNC_COUNT} nodes"
echo "Merging ledgers..."

# Check if we have any ledgers to merge
if [ ! "$(ls -A ${TEMP_DIR}/*_transactions.jsonl 2>/dev/null)" ]; then
    echo "No ledgers to sync"
    rm -rf "${TEMP_DIR}"
    exit 0
fi

# Combine all transaction files (remove duplicates)
cat "${TEMP_DIR}"/*_transactions.jsonl 2>/dev/null | sort | uniq > "${TEMP_DIR}/all_transactions.jsonl"

NEW_TX_COUNT=0

# Process each transaction
while IFS= read -r line; do
    # Skip empty lines
    [ -z "$line" ] && continue
    
    # Try to extract hash (with error suppression)
    TX_HASH=$(echo "${line}" | jq -r '.hash // empty' 2>/dev/null)
    TX_TYPE=$(echo "${line}" | jq -r '.type // empty' 2>/dev/null)
    
    # Skip if we couldn't parse the line
    if [ -z "${TX_TYPE}" ]; then
        continue
    fi
    
    # Check if this is a new transaction
    if [ -n "${TX_HASH}" ]; then
        # Transaction has a hash - check if we already have it.
        # Use jq (not a spaced grep) because the ledger is compact JSONL.
        if [ -z "$(jq -r --arg h "${TX_HASH}" 'select(.hash == $h) | .hash' "${LEDGER_DIR}/transactions.jsonl" 2>/dev/null | head -n1)" ]; then
            # This is a new transaction - validate and add it
            echo "${line}" > "${TEMP_DIR}/temp_tx.json"
            
            if /scripts/validate-transaction.sh "${TEMP_DIR}/temp_tx.json" --add-to-ledger 2>/dev/null; then
                NEW_TX_COUNT=$((NEW_TX_COUNT + 1))
                echo "  Added transaction ${TX_HASH:0:16}..."
            fi
        fi
    else
        # No hash - probably genesis block
        if [ "${TX_TYPE}" == "genesis" ]; then
            # Check if we already have a genesis block from this node
            GENESIS_NODE=$(echo "${line}" | jq -r '.node // empty' 2>/dev/null)
            if [ -n "${GENESIS_NODE}" ]; then
                if [ -z "$(jq -r --arg gn "${GENESIS_NODE}" 'select(.type == "genesis" and .node == $gn) | .node' "${LEDGER_DIR}/transactions.jsonl" 2>/dev/null | head -n1)" ]; then
                    # Add genesis block
                    (
                        flock -x 200
                        echo "${line}" >> "${LEDGER_DIR}/transactions.jsonl"
                    ) 200>/var/lock/ledger.lock
                    NEW_TX_COUNT=$((NEW_TX_COUNT + 1))
                    echo "  Added genesis block from ${GENESIS_NODE}"
                fi
            fi
        fi
    fi
done < "${TEMP_DIR}/all_transactions.jsonl"

# Clean up
rm -rf "${TEMP_DIR}"

echo ""
echo "Ledger synchronization complete!"
echo "Added ${NEW_TX_COUNT} new transactions"

# Recalculate balances
/scripts/consensus.sh calculate > /dev/null 2>&1

echo "Balances updated"

