#!/bin/bash
# Helper script to import missing public keys from other nodes
# Run this if key exchange failed during initialization

# Load shared membership helpers (defines NODES_CONFIG and get_* functions).
source /scripts/nodes-lib.sh

NODE_ID=${NODE_ID:-"node1"}
KEYS_DIR="/data/keys"

# Show help
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    cat << 'EOF'
BashCoin - GPG Key Import Utility

Description:
    Manually imports missing GPG public keys from other nodes.
    Use this if key exchange failed during node initialization.

Usage:
    import-keys.sh

Examples:
    # Import missing keys
    /scripts/import-keys.sh

When to use:
    - If 'gpg --list-keys' shows fewer keys than there are nodes
    - After key exchange failures during initialization
    - To verify all nodes can communicate

Notes:
    - Each node should have one GPG key per node in config/nodes.json
      (including its own)
    - Without all keys, signature verification fails
    - Keys are needed to verify transaction authenticity

EOF
    exit 0
fi

echo "BashCoin Key Import Utility"
echo "============================"
echo ""

# Check current keys
CURRENT_KEYS=$(gpg --list-keys 2>/dev/null | grep -c "@bashcoin.local")
echo "Currently imported keys: ${CURRENT_KEYS}"
echo ""

# Try to import public keys from the other nodes listed in the membership config.
IMPORTED_COUNT=0
ALREADY_HAVE=0

for node in $(get_node_ids_except "${NODE_ID}"); do
    # Check if we already have this key
    if gpg --list-keys 2>/dev/null | grep -q "${node}@bashcoin.local"; then
        echo "✓ Already have key from ${node}"
        ALREADY_HAVE=$((ALREADY_HAVE + 1))
        continue
    fi

    NODE_IP=$(get_node_ip "${node}")

    echo "Importing key from ${node} (${NODE_IP})..."

    # Try to fetch and import
    if rsync -az --timeout=5 "rsync://${NODE_IP}:873/keys/public.key" "${KEYS_DIR}/${node}_public.key" 2>/dev/null; then
        if gpg --import "${KEYS_DIR}/${node}_public.key" 2>/dev/null; then
            echo "✓ Successfully imported key from ${node}"
            IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
        else
            echo "✗ Failed to import key from ${node} (GPG error)"
        fi
    else
        echo "✗ Failed to fetch key from ${node} (network error)"
    fi
done

echo ""
echo "=============================="
echo "Import Summary:"
echo "  Already had: ${ALREADY_HAVE}"
echo "  Newly imported: ${IMPORTED_COUNT}"
echo "  Total keys now: $(gpg --list-keys 2>/dev/null | grep -c "@bashcoin.local")"
echo ""

# List all keys
echo "All imported keys:"
gpg --list-keys 2>/dev/null | grep "uid" | grep "@bashcoin.local"
echo ""

# We expect one key per other node (total configured nodes minus ourselves).
EXPECTED_KEYS=$(( $(get_node_count) - 1 ))
if [ $((ALREADY_HAVE + IMPORTED_COUNT)) -eq "${EXPECTED_KEYS}" ]; then
    echo "✓ All keys imported successfully!"
else
    echo "⚠ Some keys are still missing. Check that other nodes are running."
fi

