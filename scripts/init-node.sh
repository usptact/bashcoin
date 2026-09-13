#!/bin/bash
set -e

# Load shared membership helpers (defines NODES_CONFIG and get_* functions).
source /scripts/nodes-lib.sh

NODE_ID=${NODE_ID:-"node1"}
DATA_DIR="/data"
KEYS_DIR="${DATA_DIR}/keys"
LEDGER_DIR="${DATA_DIR}/ledger"
PENDING_DIR="${DATA_DIR}/pending"

# Initialize directories
mkdir -p "${KEYS_DIR}" "${LEDGER_DIR}" "${PENDING_DIR}"

# Note: inter-node transport uses the rsync daemon protocol (port 873) and TCP
# broadcasting (port 9000). No SSH is required, so none is configured.

# Generate GPG key if not exists
if [ ! -f "${KEYS_DIR}/public.key" ]; then
    echo "Generating GPG key pair for ${NODE_ID}..."
    
    # Configure GPG for non-interactive use
    export GNUPGHOME=/root/.gnupg
    mkdir -p ${GNUPGHOME}
    chmod 700 ${GNUPGHOME}
    
    # Generate key
    cat > /tmp/gpg-batch << EOF
%no-protection
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: ${NODE_ID}
Name-Email: ${NODE_ID}@bashcoin.local
Expire-Date: 0
EOF
    
    gpg --batch --gen-key /tmp/gpg-batch
    rm /tmp/gpg-batch
    
    # Export public key
    gpg --armor --export "${NODE_ID}@bashcoin.local" > "${KEYS_DIR}/public.key"
    
    echo "GPG key generated and exported to ${KEYS_DIR}/public.key"
fi

# Initialize ledger file if not exists
if [ ! -f "${LEDGER_DIR}/transactions.jsonl" ]; then
    echo "Initializing ledger..."
    touch "${LEDGER_DIR}/transactions.jsonl"
    
    # Create genesis block (compact JSON - JSONL format)
    GENESIS_BLOCK=$(jq -nc \
        --arg node "${NODE_ID}" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            type: "genesis",
            node: $node,
            timestamp: $timestamp,
            message: "Genesis block for BashCoin distributed ledger"
        }')
    
    echo "${GENESIS_BLOCK}" >> "${LEDGER_DIR}/transactions.jsonl"
fi

# Initialize balance file from the membership config (data-driven).
if [ ! -f "${LEDGER_DIR}/balances.json" ]; then
    jq '[.nodes[] | {(.id): .balance}] | add // {}' "${NODES_CONFIG}" \
        > "${LEDGER_DIR}/balances.json"
fi

# Start rsync daemon BEFORE key exchange (so other nodes can fetch our key)
echo "Starting rsync daemon for key sharing..."
cat > /etc/rsyncd.conf << EOF
uid = root
gid = root
use chroot = no
max connections = 10
log file = /var/log/rsyncd.log

[keys]
    path = /data/keys
    comment = Public keys
    read only = yes

[ledger]
    path = /data/ledger
    comment = Ledger data
    read only = yes

[pending]
    path = /data/pending
    comment = Pending transactions
    read only = yes
EOF

rsync --daemon

# Exchange keys with other nodes
echo "Exchanging public keys with other nodes..."
echo "Waiting for other nodes' rsync daemons to be ready..."
sleep 10

# Try to import public keys from the other nodes listed in the membership config.
IMPORTED_COUNT=0

for node in $(get_node_ids_except "${NODE_ID}"); do
    NODE_HOST=$(get_node_host "${node}")

    echo "Fetching public key from ${node} (${NODE_HOST})..."

    # Try multiple times with increasing backoff
    for attempt in {1..15}; do
        if rsync -az --timeout=5 "rsync://${NODE_HOST}:873/keys/public.key" "${KEYS_DIR}/${node}_public.key" 2>/dev/null; then
            # Import the key
            if gpg --import "${KEYS_DIR}/${node}_public.key" 2>/dev/null; then
                echo "✓ Successfully imported public key from ${node}"
                IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
                break
            fi
        fi

        # Exponential backoff: 2, 4, 6, 8... seconds
        sleep $((attempt * 2))
    done

    if [ ! -f "${KEYS_DIR}/${node}_public.key" ]; then
        echo "✗ Failed to fetch key from ${node} (will retry later)"
    fi
done

echo ""
echo "Key exchange complete: imported ${IMPORTED_COUNT} public keys"
echo "Node initialization complete!"

