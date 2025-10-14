#!/bin/bash

NODE_ID=${NODE_ID:-"node1"}
DATA_DIR="/data"
LEDGER_DIR="${DATA_DIR}/ledger"
PENDING_DIR="${DATA_DIR}/pending"
PORT=9000

echo "Starting ledger daemon on port ${PORT}..."

# Rsync daemon already started in init-node.sh
# Just verify it's running
if ! pgrep -x rsync > /dev/null; then
    echo "Warning: rsync daemon not running, attempting to start..."
    rsync --daemon
fi

# Listen for incoming transactions on TCP port
while true; do
    # Listen for incoming transactions using netcat
    nc -l -p ${PORT} > /tmp/incoming_tx.json 2>/dev/null
    
    if [ -s /tmp/incoming_tx.json ]; then
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Received transaction"
        
        # Validate and process the transaction (add to ledger if valid)
        if /scripts/validate-transaction.sh /tmp/incoming_tx.json --add-to-ledger 2>&1 | grep -q "Transaction validation successful"; then
            echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Transaction validated and added to ledger"
        else
            echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Transaction validation failed"
        fi
        
        rm -f /tmp/incoming_tx.json
    fi
    
    sleep 1
done

