#!/bin/bash
set -e

# Load shared membership helpers (for is_seed).
source /scripts/nodes-lib.sh

# Default the NTP server to its DNS service name (resolved by Docker's embedded
# DNS); no static IP is required.
NTP_SERVER=${NTP_SERVER:-ntp-server}

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

# If this node is not part of the seed (genesis) set, it is a runtime joiner:
# announce ourselves to the network so existing nodes discover us and import our
# key. Existing seed nodes require no rebuild to learn about us.
if ! is_seed "${NODE_ID}"; then
    echo "${NODE_ID} is not a seed node; announcing join to the network..."
    # Give the ledger daemon and seed nodes a moment to be ready.
    ( sleep 8; /scripts/join-network.sh ) &
fi

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
echo "  - Announce join (non-seed nodes): /scripts/join-network.sh"
echo ""

# Keep container alive
tail -f /dev/null

