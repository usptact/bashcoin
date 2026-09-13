#!/bin/bash
set -e

echo "=================================="
echo "BashCoin Node: ${NODE_ID}"
echo "=================================="

# Configure NTP client
echo "Configuring NTP client to use ${NTP_SERVER}..."
echo "servers ${NTP_SERVER}" > /etc/ntpd.conf
ntpd -s -d -S /usr/sbin/ntpd &

# Wait a bit for NTP to sync
sleep 2

# Initialize the node (GPG keys, ledger, key exchange, etc.)
echo "Initializing node..."
/scripts/init-node.sh

# Check if this is a restart (ledger already exists with transactions)
# If so, sync with other nodes to catch up on missed transactions
LEDGER_FILE="/data/ledger/transactions.jsonl"
if [ -f "${LEDGER_FILE}" ]; then
    TX_COUNT=$(wc -l < "${LEDGER_FILE}")
    if [ "${TX_COUNT}" -gt 1 ]; then
        echo "Existing ledger detected (${TX_COUNT} transactions)"
        echo "Syncing with network to catch up on any missed transactions..."
        
        # Wait a bit for other nodes to be ready
        sleep 5
        
        # Run sync in background to not block startup
        /scripts/sync-ledger.sh &
    fi
fi

# Start the ledger daemon in background
echo "Starting ledger daemon..."
/scripts/ledger-daemon.sh &

# Keep container running and show logs
echo "=================================="
echo "Node ${NODE_ID} is ready!"
echo "=================================="
echo ""
echo "Available commands:"
echo "  - Send transaction: /scripts/create-transaction.sh <to_node> <amount>"
echo "  - View ledger: cat /data/ledger/transactions.jsonl"
echo "  - View balance: /scripts/consensus.sh balance"
echo "  - Check GPG keys: gpg --list-keys"
echo "  - Import missing keys: /scripts/import-keys.sh"
echo "  - Sync ledger: /scripts/sync-ledger.sh"
echo ""

# Keep container alive
tail -f /dev/null

