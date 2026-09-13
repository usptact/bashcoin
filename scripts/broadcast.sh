#!/bin/bash

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

# List of all nodes
ALL_NODES=("node1" "node2" "node3" "node4" "node5")

echo "Broadcasting transaction to network..."

for node in "${ALL_NODES[@]}"; do
    if [ "${node}" != "${NODE_ID}" ]; then
        NODE_NUM=$(echo ${node} | sed 's/node//')
        NODE_IP="172.25.0.1${NODE_NUM}"
        
        echo "Sending to ${node} (${NODE_IP})..."
        
        # Send transaction via TCP using netcat.
        # -N shuts the socket down after EOF on stdin so the receiver sees end of
        # input immediately (no waiting on the idle timeout). timeout guards hangs.
        timeout 5 sh -c "cat '${TX_FILE}' | nc -N ${NODE_IP} ${PORT}" 2>/dev/null &
        
        # Don't wait for all sends to complete
    fi
done

# Wait a bit for sends to complete
sleep 2

echo "Broadcast complete"

