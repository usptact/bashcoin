#!/bin/bash

# Load shared membership helpers (defines NODES_CONFIG and get_* functions).
source /scripts/nodes-lib.sh

NODE_ID=${NODE_ID:-"node1"}
PORT=9000

# Check if transaction file provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <transaction_file>"
    exit 1
fi

TX_FILE=$1

if [ ! -f "${TX_FILE}" ]; then
    echo "Error: Transaction file not found: ${TX_FILE}"
    exit 1
fi

echo "Broadcasting transaction to network..."

for node in $(get_node_ids_except "${NODE_ID}"); do
    NODE_HOST=$(get_node_host "${node}")

    echo "Sending to ${node} (${NODE_HOST})..."

    # Send transaction via TCP using netcat.
    # -N shuts the socket down after EOF on stdin so the receiver sees end of
    # input immediately (no waiting on the idle timeout). timeout guards hangs.
    timeout 5 sh -c "cat '${TX_FILE}' | nc -N ${NODE_HOST} ${PORT}" 2>/dev/null &

    # Don't wait for all sends to complete
done

# Wait a bit for sends to complete
sleep 2

echo "Broadcast complete"

