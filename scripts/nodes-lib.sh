#!/bin/bash
# Shared network-membership helpers for BashCoin.
#
# Source this file from other scripts:
#     source /scripts/nodes-lib.sh
#
# Membership is defined in a single JSON config (default: /config/nodes.json),
# which is the one place to edit when adding or removing a node:
#
#     {
#       "nodes": [
#         { "id": "node1", "ip": "172.25.0.11", "balance": 1000 },
#         ...
#       ]
#     }
#
# Override the config location with the NODES_CONFIG environment variable
# (useful for testing).

NODES_CONFIG="${NODES_CONFIG:-/config/nodes.json}"

# Print all node ids, one per line, in config order.
get_all_node_ids() {
    jq -r '.nodes[].id' "${NODES_CONFIG}"
}

# Print all node ids except the given one, one per line, in config order.
get_node_ids_except() {
    local self="$1"
    jq -r --arg self "${self}" '.nodes[] | select(.id != $self) | .id' "${NODES_CONFIG}"
}

# Print the IP address for a node id (empty if the id is unknown).
get_node_ip() {
    local id="$1"
    jq -r --arg id "${id}" '.nodes[] | select(.id == $id) | .ip' "${NODES_CONFIG}"
}

# Print the configured initial (genesis) balance for a node id (0 if unset).
get_initial_balance() {
    local id="$1"
    jq -r --arg id "${id}" '(.nodes[] | select(.id == $id) | .balance) // 0' "${NODES_CONFIG}"
}

# Print the number of configured nodes.
get_node_count() {
    jq -r '.nodes | length' "${NODES_CONFIG}"
}
