#!/bin/bash
set -e

# Load shared membership helpers (defines NODES_CONFIG, NODES_LEDGER, get_*).
source /scripts/nodes-lib.sh

NODE_ID=${NODE_ID:-"node1"}
NODE_HOST=${NODE_HOST:-$(hostname)}
DATA_DIR="/data"
LEDGER_DIR="${DATA_DIR}/ledger"
KEYS_DIR="${DATA_DIR}/keys"
PENDING_DIR="${DATA_DIR}/pending"

# Balance minted to this node on join. Capped by policy.max_join_balance on the
# receiving nodes; the default of 0 means joiners hold nothing until funded.
JOIN_INITIAL_BALANCE=${JOIN_INITIAL_BALANCE:-0}

if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    cat << 'EOF'
BashCoin - Join Network

Description:
    Announces this node to the network as a runtime member by creating a
    self-signed "node-join" record and broadcasting it to the seed nodes.
    The record carries this node's DNS host and public key, so existing nodes
    can discover it and verify its transactions without any rebuild.

Usage:
    join-network.sh

Notes:
    - Runs automatically on boot for any node whose NODE_ID is not a seed.
    - Minted balance is controlled by JOIN_INITIAL_BALANCE (default 0) and is
      capped by the network's policy.max_join_balance (default 0).
    - After announcing, the node syncs the ledger to catch up on history.
EOF
    exit 0
fi

if is_seed "${NODE_ID}"; then
    echo "${NODE_ID} is a seed (genesis) node; no join announcement needed."
    exit 0
fi

if [ ! -f "${KEYS_DIR}/public.key" ]; then
    echo "Error: public key not found (${KEYS_DIR}/public.key). Run init-node.sh first."
    exit 1
fi

echo "Announcing ${NODE_ID} (host ${NODE_HOST}) to the network..."

# Public key travels inside the record (base64 of the armored key, one line).
PUB_B64=$(base64 -w 0 "${KEYS_DIR}/public.key")

NONCE=$(echo "${NODE_ID}-$(date +%s%N)-${RANDOM}" | sha256sum | cut -d' ' -f1)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Hash binds every field of the join record.
JOIN_DATA="${NODE_ID}|${NODE_HOST}|${PUB_B64}|${JOIN_INITIAL_BALANCE}|${NONCE}|${TIMESTAMP}"
JOIN_HASH=$(printf '%s' "${JOIN_DATA}" | sha256sum | cut -d' ' -f1)

# Self-signed detached signature over the hash proves ownership of the key.
SIGNATURE=$(printf '%s' "${JOIN_HASH}" | gpg --armor --detach-sign --local-user "${NODE_ID}@bashcoin.local" 2>/dev/null | base64 -w 0)

JOIN_RECORD=$(jq -nc \
    --arg node "${NODE_ID}" \
    --arg host "${NODE_HOST}" \
    --arg pubkey "${PUB_B64}" \
    --argjson balance "${JOIN_INITIAL_BALANCE}" \
    --arg nonce "${NONCE}" \
    --arg timestamp "${TIMESTAMP}" \
    --arg hash "${JOIN_HASH}" \
    --arg sig "${SIGNATURE}" \
    '{
        type: "node-join",
        node: $node,
        host: $host,
        pubkey: $pubkey,
        balance: $balance,
        nonce: $nonce,
        timestamp: $timestamp,
        hash: $hash,
        signature: $sig
    }')

# Record our own membership locally (we trust ourselves), then recompute.
(
    flock -x 200
    echo "${JOIN_RECORD}" | jq -c . >> "${LEDGER_DIR}/transactions.jsonl"
) 200>/var/lock/ledger.lock
/scripts/consensus.sh calculate > /dev/null 2>&1

# Broadcast the join to the seeds (and any peers we already know).
JOIN_FILE="${PENDING_DIR}/join_${JOIN_HASH}.json"
echo "${JOIN_RECORD}" > "${JOIN_FILE}"
/scripts/broadcast.sh "${JOIN_FILE}"
rm -f "${JOIN_FILE}"

echo "Join announced (hash ${JOIN_HASH})."

# Catch up on the existing ledger/balances from the network.
echo "Syncing ledger to catch up on network history..."
/scripts/sync-ledger.sh || true

echo "Join complete."
