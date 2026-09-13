#!/bin/bash
# Shared network-membership helpers for BashCoin.
#
# Source this file from other scripts:
#     source /scripts/nodes-lib.sh
#
# Membership has two layers:
#
#   1. Seed (genesis) members — defined in a single JSON config
#      (default: /config/nodes.json). These are the bootstrap nodes and their
#      initial balances. This is baked into the image and identical on every
#      node, so all nodes agree on the genesis set.
#
#         {
#           "policy": { "max_join_balance": 0, "allowed_joiners": [] },
#           "nodes": [
#             { "id": "node1", "host": "node1", "balance": 1000 },
#             ...
#           ]
#         }
#
#   2. Joined members — added at runtime via "node-join" records that live in
#      the ledger itself (see join-network.sh). Each carries the joiner's DNS
#      host and public key, so any node that has the ledger can discover and
#      verify a joiner without a rebuild or config edit.
#
# "Effective" membership = seeds ∪ joined members (seeds win on id collision).
# 'host' is a DNS name resolved by Docker's embedded DNS (matching the compose
# service name), so no static IP addresses are required.
#
# Override locations with NODES_CONFIG / NODES_LEDGER (useful for testing).

NODES_CONFIG="${NODES_CONFIG:-/config/nodes.json}"
NODES_LEDGER="${NODES_LEDGER:-/data/ledger/transactions.jsonl}"

# --- internal: membership as JSON arrays of {id, host, balance} ---------------

# Seed (genesis) members from the config.
_seed_members_json() {
    jq -c '[.nodes[] | {id: .id, host: .host, balance: (.balance // 0)}]' "${NODES_CONFIG}"
}

# Joined members derived from node-join records in the ledger. Parsed line by
# line with fromjson? so a stray malformed line cannot wipe out discovery.
_joined_members_json() {
    if [ -f "${NODES_LEDGER}" ]; then
        jq -R 'fromjson? // empty' "${NODES_LEDGER}" 2>/dev/null \
            | jq -s -c '[.[] | select(.type == "node-join") | {id: .node, host: .host, balance: (.balance // 0)}]'
    else
        echo '[]'
    fi
}

# Effective membership: seeds first (so they win on id collision), then joins,
# de-duplicated by id.
_effective_members_json() {
    jq -n -c \
        --argjson seeds "$(_seed_members_json)" \
        --argjson joins "$(_joined_members_json)" \
        '($seeds + $joins) | group_by(.id) | map(.[0])'
}

# --- public helpers -----------------------------------------------------------

# Print all seed (genesis) node ids, one per line.
get_seed_node_ids() {
    _seed_members_json | jq -r '.[].id'
}

# Print all effective node ids (seeds + joined), one per line.
get_all_node_ids() {
    _effective_members_json | jq -r '.[].id'
}

# Print all effective node ids except the given one, one per line.
get_node_ids_except() {
    local self="$1"
    _effective_members_json | jq -r --arg self "${self}" '.[] | select(.id != $self) | .id'
}

# Print the DNS host name for a node id (empty if the id is unknown).
get_node_host() {
    local id="$1"
    _effective_members_json | jq -r --arg id "${id}" '.[] | select(.id == $id) | .host' | head -n1
}

# Print the initial (genesis/minted) balance for a node id (0 if unset).
get_initial_balance() {
    local id="$1"
    _effective_members_json | jq -r --arg id "${id}" '(.[] | select(.id == $id) | .balance) // 0' | head -n1
}

# Print the number of effective nodes.
get_node_count() {
    _effective_members_json | jq 'length'
}

# Succeed (0) if the id is an effective member.
is_member() {
    local id="$1"
    [ -n "$(_effective_members_json | jq -r --arg id "${id}" '.[] | select(.id == $id) | .id' | head -n1)" ]
}

# Succeed (0) if the id is a seed (genesis) member.
is_seed() {
    local id="$1"
    _seed_members_json | jq -e --arg id "${id}" 'any(.[]; .id == $id)' >/dev/null 2>&1
}

# --- admission policy ---------------------------------------------------------

# Maximum balance a node-join record may mint (default 0 = no minting on join).
get_max_join_balance() {
    jq -r '.policy.max_join_balance // 0' "${NODES_CONFIG}"
}

# Succeed (0) if the given id is allowed to join. If policy.allowed_joiners is
# empty/absent, open join is permitted (subject to the balance cap elsewhere).
is_join_allowed() {
    local id="$1"
    local allowed
    allowed=$(jq -c '.policy.allowed_joiners // []' "${NODES_CONFIG}")
    if [ "${allowed}" == "[]" ]; then
        return 0
    fi
    echo "${allowed}" | jq -e --arg id "${id}" 'any(.[]; . == $id)' >/dev/null 2>&1
}
