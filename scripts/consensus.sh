#!/bin/bash

# Load shared membership helpers (defines NODES_CONFIG and get_* functions).
source /scripts/nodes-lib.sh

NODE_ID=${NODE_ID:-"node1"}
DATA_DIR="/data"
LEDGER_DIR="${DATA_DIR}/ledger"

ACTION=${1:-"check"}

# Show help
if [ "$ACTION" == "--help" ] || [ "$ACTION" == "-h" ]; then
    cat << 'EOF'
BashCoin - Consensus Management

Description:
    Manages balance calculation and consensus checking for the distributed ledger.
    Processes all transactions in the ledger to calculate current balances.

Usage:
    consensus.sh {calculate|balance|check|stats}

Commands:
    calculate   Recalculate balances from the ledger
    balance     Show current balances for all nodes
    check       Perform consensus check (recalculates balances)
    stats       Show ledger statistics and balances

Examples:
    # Recalculate balances from ledger
    /scripts/consensus.sh calculate
    
    # Check your balance
    /scripts/consensus.sh balance
    
    # View statistics
    /scripts/consensus.sh stats

Notes:
    - Balances are automatically recalculated after each transaction
    - Use 'calculate' to force recalculation if balances seem incorrect
    - All nodes start with 1000 coins

EOF
    exit 0
fi

case "${ACTION}" in
    "calculate")
        echo "Calculating balances from ledger..."

        # Serialize balance recomputation with a dedicated lock (separate from the
        # ledger lock) so concurrent callers cannot interleave read-modify-write on
        # balances.json. Using a distinct lock file means this is safe to call from
        # within the ledger-lock critical section without deadlocking.
        (
            flock -x 201

            # Initialize balances from the membership config (data-driven, so any
            # set of nodes works without editing this script).
            declare -A BALANCES
            while IFS=$'\t' read -r _id _bal; do
                [ -z "${_id}" ] && continue
                BALANCES["${_id}"]="${_bal}"
            done < <(jq -r '.nodes[] | "\(.id)\t\(.balance)"' "${NODES_CONFIG}")

            # Process all transactions
            if [ -f "${LEDGER_DIR}/transactions.jsonl" ]; then
                while IFS= read -r line; do
                    # Skip empty lines
                    [ -z "$line" ] && continue

                    # Try to parse JSON, skip if invalid
                    TX_TYPE=$(echo "${line}" | jq -r '.type' 2>/dev/null)

                    if [ "${TX_TYPE}" == "transaction" ]; then
                        FROM=$(echo "${line}" | jq -r '.from' 2>/dev/null)
                        TO=$(echo "${line}" | jq -r '.to' 2>/dev/null)
                        AMOUNT=$(echo "${line}" | jq -r '.amount' 2>/dev/null)

                        # Validate parsed data
                        if [ -n "${FROM}" ] && [ -n "${TO}" ] && [ -n "${AMOUNT}" ] && [ "${AMOUNT}" != "null" ]; then
                            # Update balances (accounts not in config default to 0
                            # so supply is still conserved for unknown nodes).
                            BALANCES["${FROM}"]=$(echo "${BALANCES[${FROM}]:-0} - ${AMOUNT}" | bc)
                            BALANCES["${TO}"]=$(echo "${BALANCES[${TO}]:-0} + ${AMOUNT}" | bc)
                        fi
                    fi
                done < "${LEDGER_DIR}/transactions.jsonl"
            fi

            # Write balances to file atomically (write temp then move). Emit one
            # key per known account in deterministic (sorted) order, normalizing
            # bc's bare-decimal output (e.g. ".5" -> "0.5") so jq can parse it.
            {
                for _id in $(printf '%s\n' "${!BALANCES[@]}" | sort); do
                    _val="${BALANCES[${_id}]}"
                    case "${_val}" in
                        .*)  _val="0${_val}" ;;
                        -.*) _val="-0${_val#-}" ;;
                    esac
                    printf '%s\t%s\n' "${_id}" "${_val}"
                done
            } | jq -R -s 'split("\n")
                    | map(select(length > 0) | split("\t") | {(.[0]): (.[1] | tonumber)})
                    | add // {}' > "${LEDGER_DIR}/balances.json.tmp" && \
                mv "${LEDGER_DIR}/balances.json.tmp" "${LEDGER_DIR}/balances.json"
        ) 201>/var/lock/balances.lock

        echo "Balances updated"
        ;;
        
    "balance")
        # Show current balance
        if [ -f "${LEDGER_DIR}/balances.json" ]; then
            echo "Current balances:"
            cat "${LEDGER_DIR}/balances.json" | jq .
            echo ""
            echo "Your balance (${NODE_ID}): $(jq -r ".\"${NODE_ID}\"" "${LEDGER_DIR}/balances.json")"
        else
            echo "No balance information available"
        fi
        ;;
        
    "check")
        # Perform consensus check
        echo "Performing consensus check..."
        
        # Calculate our balances
        /scripts/consensus.sh calculate
        
        # In a real implementation, we would:
        # 1. Get balance state from other nodes
        # 2. Compare with our state
        # 3. Resolve conflicts based on majority or other consensus mechanism
        
        echo "Consensus check complete"
        ;;
        
    "stats")
        echo "Ledger Statistics"
        echo "================="
        echo "Node: ${NODE_ID}"
        echo ""
        
        if [ -f "${LEDGER_DIR}/transactions.jsonl" ]; then
            TOTAL_TX=$(wc -l < "${LEDGER_DIR}/transactions.jsonl")
            GENESIS_TX=$(jq -r 'select(.type == "genesis") | .type' "${LEDGER_DIR}/transactions.jsonl" 2>/dev/null | wc -l)
            REGULAR_TX=$((TOTAL_TX - GENESIS_TX))
            
            echo "Total transactions: ${TOTAL_TX}"
            echo "Genesis blocks: ${GENESIS_TX}"
            echo "Regular transactions: ${REGULAR_TX}"
            echo ""
        fi
        
        /scripts/consensus.sh balance
        ;;
        
    *)
        echo "Usage: $0 {calculate|balance|check|stats}"
        echo "Run with --help for more information"
        exit 1
        ;;
esac

