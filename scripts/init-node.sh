#!/bin/bash
set -e

NODE_ID=${NODE_ID:-"node1"}
DATA_DIR="/data"
KEYS_DIR="${DATA_DIR}/keys"
LEDGER_DIR="${DATA_DIR}/ledger"
PENDING_DIR="${DATA_DIR}/pending"

# Initialize directories
mkdir -p "${KEYS_DIR}" "${LEDGER_DIR}" "${PENDING_DIR}"

# Generate SSH key if not exists
if [ ! -f /root/.ssh/id_rsa ]; then
    echo "Generating SSH key..."
    ssh-keygen -t rsa -b 2048 -f /root/.ssh/id_rsa -N ""
    cp /root/.ssh/id_rsa.pub "${KEYS_DIR}/ssh_key.pub"
fi

# Setup SSH authorized_keys for all nodes
echo "Setting up SSH authorized keys..."
cat > /root/.ssh/authorized_keys << 'EOF'
# This will be populated by nodes exchanging keys
# For now, we'll use a shared key approach
EOF

# Generate a shared SSH key for simplicity (in production, each would have unique keys)
if [ ! -f /root/.ssh/known_hosts ]; then
    touch /root/.ssh/known_hosts
    # Accept all hosts in our network (not secure for production!)
    cat > /root/.ssh/config << 'EOF'
Host 172.25.0.*
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
EOF
fi

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

# Initialize balance file
if [ ! -f "${LEDGER_DIR}/balances.json" ]; then
    # Each node starts with 1000 coins
    jq -n \
        --arg node1 "node1" \
        --arg node2 "node2" \
        --arg node3 "node3" \
        --arg node4 "node4" \
        --arg node5 "node5" \
        '{
            ($node1): 1000,
            ($node2): 1000,
            ($node3): 1000,
            ($node4): 1000,
            ($node5): 1000
        }' > "${LEDGER_DIR}/balances.json"
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
    read only = no
EOF

rsync --daemon

# Exchange keys with other nodes
echo "Exchanging public keys with other nodes..."
echo "Waiting for other nodes' rsync daemons to be ready..."
sleep 10

# Try to import public keys from other nodes
OTHER_NODES=("node1" "node2" "node3" "node4" "node5")
IMPORTED_COUNT=0

for node in "${OTHER_NODES[@]}"; do
    if [ "${node}" != "${NODE_ID}" ]; then
        NODE_NUM=$(echo ${node} | sed 's/node//')
        NODE_IP="172.25.0.1${NODE_NUM}"
        
        echo "Fetching public key from ${node} (${NODE_IP})..."
        
        # Try multiple times with increasing backoff
        for attempt in {1..15}; do
            if rsync -az --timeout=5 "rsync://${NODE_IP}:873/keys/public.key" "${KEYS_DIR}/${node}_public.key" 2>/dev/null; then
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
    fi
done

echo ""
echo "Key exchange complete: imported ${IMPORTED_COUNT} public keys"
echo "Node initialization complete!"

