#!/bin/bash

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
        
        # Initialize balances
        declare -A BALANCES
        BALANCES["node1"]=1000
        BALANCES["node2"]=1000
        BALANCES["node3"]=1000
        BALANCES["node4"]=1000
        BALANCES["node5"]=1000
        
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
                        # Update balances
                        BALANCES["${FROM}"]=$(echo "${BALANCES[${FROM}]} - ${AMOUNT}" | bc)
                        BALANCES["${TO}"]=$(echo "${BALANCES[${TO}]} + ${AMOUNT}" | bc)
                    fi
                fi
            done < "${LEDGER_DIR}/transactions.jsonl"
        fi
        
        # Write balances to file
        jq -n \
            --arg node1 "${BALANCES[node1]}" \
            --arg node2 "${BALANCES[node2]}" \
            --arg node3 "${BALANCES[node3]}" \
            --arg node4 "${BALANCES[node4]}" \
            --arg node5 "${BALANCES[node5]}" \
            '{
                "node1": ($node1 | tonumber),
                "node2": ($node2 | tonumber),
                "node3": ($node3 | tonumber),
                "node4": ($node4 | tonumber),
                "node5": ($node5 | tonumber)
            }' > "${LEDGER_DIR}/balances.json"
        
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
            GENESIS_TX=$(grep '"type": "genesis"' "${LEDGER_DIR}/transactions.jsonl" | wc -l)
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

