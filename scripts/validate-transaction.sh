#!/bin/bash

# Load shared membership helpers (defines NODES_CONFIG, NODES_LEDGER, get_*,
# is_member, is_join_allowed, get_max_join_balance).
source /scripts/nodes-lib.sh

NODE_ID=${NODE_ID:-"node1"}
DATA_DIR="/data"
LEDGER_DIR="${DATA_DIR}/ledger"
PENDING_DIR="${DATA_DIR}/pending"

# Show help
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    cat << 'EOF'
BashCoin - Validate Transaction

Description:
    Validates a transaction by checking:
    - Hash integrity
    - GPG signature
    - Nonce uniqueness (double-spend prevention)
    - Sender balance
    
    Optionally adds the transaction to the ledger if valid.

Usage:
    validate-transaction.sh <transaction_file> [--add-to-ledger]

Arguments:
    transaction_file    Path to JSON file containing the transaction
    --add-to-ledger     Optional: Add to ledger if validation succeeds

Examples:
    # Just validate (no side effects)
    /scripts/validate-transaction.sh /tmp/tx.json
    
    # Validate and add to ledger if valid
    /scripts/validate-transaction.sh /tmp/tx.json --add-to-ledger

Notes:
    - Without --add-to-ledger flag, this is a pure validation function
    - Used by create-transaction.sh (without flag) and ledger-daemon.sh (with flag)

EOF
    exit 0
fi

# Check if transaction file provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <transaction_file> [--add-to-ledger]"
    echo "Run with --help for more information"
    exit 1
fi

TX_FILE=$1
ADD_TO_LEDGER=false

# Check if we should add to ledger
if [ "$2" == "--add-to-ledger" ]; then
    ADD_TO_LEDGER=true
fi

if [ ! -f "${TX_FILE}" ]; then
    echo "Error: Transaction file not found: ${TX_FILE}"
    exit 1
fi

RECORD_TYPE=$(jq -r '.type // "transaction"' "${TX_FILE}" 2>/dev/null)

# --------------------------------------------------------------------------
# node-join records (runtime membership).
#
# A node-join is a self-signed record carrying the joiner's DNS host and public
# key. Accepting it makes the joiner a discoverable, verifiable member. Admission
# rules prevent abuse:
#   - the embedded key must actually sign the record (proves key ownership),
#   - the id must not already be a member (no impersonation / takeover),
#   - the minted balance must be within policy.max_join_balance (no self-minting;
#     default cap is 0, so joiners must be funded by existing holders).
# --------------------------------------------------------------------------
if [ "${RECORD_TYPE}" == "node-join" ]; then
    JNODE=$(jq -r '.node' "${TX_FILE}" 2>/dev/null)
    JHOST=$(jq -r '.host' "${TX_FILE}" 2>/dev/null)
    JPUB=$(jq -r '.pubkey' "${TX_FILE}" 2>/dev/null)
    JBAL=$(jq -r '.balance' "${TX_FILE}" 2>/dev/null)
    JNONCE=$(jq -r '.nonce' "${TX_FILE}" 2>/dev/null)
    JTS=$(jq -r '.timestamp' "${TX_FILE}" 2>/dev/null)
    JHASH=$(jq -r '.hash' "${TX_FILE}" 2>/dev/null)
    JSIG=$(jq -r '.signature' "${TX_FILE}" 2>/dev/null)

    echo "Validating node-join for ${JNODE}..."

    if [ -z "${JNODE}" ] || [ "${JNODE}" == "null" ] || \
       [ -z "${JHOST}" ] || [ "${JHOST}" == "null" ] || \
       [ -z "${JPUB}" ] || [ "${JPUB}" == "null" ] || \
       [ -z "${JBAL}" ] || [ "${JBAL}" == "null" ]; then
        echo "Error: node-join missing required fields"
        exit 1
    fi

    # Verify hash integrity.
    EXPECTED_JHASH=$(printf '%s' "${JNODE}|${JHOST}|${JPUB}|${JBAL}|${JNONCE}|${JTS}" | sha256sum | cut -d' ' -f1)
    if [ "${JHASH}" != "${EXPECTED_JHASH}" ]; then
        echo "Error: node-join hash mismatch"
        exit 1
    fi

    # Nonce must be unique (dedupe / replay protection).
    if [ -f "${LEDGER_DIR}/transactions.jsonl" ] && \
       [ -n "$(jq -r --arg n "${JNONCE}" 'select(.nonce == $n) | .nonce' "${LEDGER_DIR}/transactions.jsonl" 2>/dev/null | head -n1)" ]; then
        echo "Error: Duplicate nonce detected (node-join replay)"
        exit 1
    fi

    # Admission: is this id permitted to join?
    if ! is_join_allowed "${JNODE}"; then
        echo "Error: ${JNODE} is not in the allowed_joiners policy"
        exit 1
    fi

    # Admission: id must not already belong to a member (prevents takeover).
    if is_member "${JNODE}"; then
        echo "Error: ${JNODE} is already a member (join rejected)"
        exit 1
    fi

    # Admission: minted balance must be within policy.
    MAX_JOIN=$(get_max_join_balance)
    if (( $(echo "${JBAL} < 0 || ${JBAL} > ${MAX_JOIN}" | bc -l) )); then
        echo "Error: node-join balance ${JBAL} exceeds policy max ${MAX_JOIN}"
        exit 1
    fi

    # Verify the self-signature using the embedded public key. Importing the key
    # is required to verify and is also how the joiner's key is distributed.
    echo "${JPUB}" | base64 -d > "/tmp/joinpub_${JHASH}.asc" 2>/dev/null
    gpg --import "/tmp/joinpub_${JHASH}.asc" >/dev/null 2>&1
    JSIG_FILE="/tmp/joinsig_${JHASH}.asc"
    JDATA_FILE="/tmp/joindata_${JHASH}.txt"
    echo "${JSIG}" | base64 -d > "${JSIG_FILE}" 2>/dev/null
    printf '%s' "${JHASH}" > "${JDATA_FILE}"
    if ! gpg --verify "${JSIG_FILE}" "${JDATA_FILE}" 2>&1 | grep -q "Good signature from \"${JNODE} "; then
        echo "Error: node-join self-signature is invalid"
        rm -f "/tmp/joinpub_${JHASH}.asc" "${JSIG_FILE}" "${JDATA_FILE}"
        exit 1
    fi
    rm -f "/tmp/joinpub_${JHASH}.asc" "${JSIG_FILE}" "${JDATA_FILE}"

    echo "Transaction validation successful!"

    if [ "$ADD_TO_LEDGER" == "true" ]; then
        echo "Adding node-join to ledger..."
        (
            flock -x 200
            # Re-check under lock (TOCTOU).
            if [ -n "$(jq -r --arg n "${JNONCE}" 'select(.nonce == $n) | .nonce' "${LEDGER_DIR}/transactions.jsonl" 2>/dev/null | head -n1)" ]; then
                echo "Error: Duplicate nonce under lock (node-join replay)"
                exit 10
            fi
            if is_member "${JNODE}"; then
                echo "Error: ${JNODE} became a member under lock"
                exit 12
            fi
            jq -c . "${TX_FILE}" >> "${LEDGER_DIR}/transactions.jsonl"
            /scripts/consensus.sh calculate > /dev/null 2>&1
        ) 200>/var/lock/ledger.lock
        LOCK_RC=$?

        rm -f "${PENDING_DIR}/join_${JHASH}.json"

        if [ "${LOCK_RC}" -ne 0 ]; then
            echo "node-join rejected during atomic commit (code ${LOCK_RC})"
            exit 1
        fi
        echo "node-join added to ledger; ${JNODE} is now a member"
    fi

    exit 0
fi

# Parse transaction
FROM=$(jq -r '.from' "${TX_FILE}" 2>/dev/null)
TO=$(jq -r '.to' "${TX_FILE}" 2>/dev/null)
AMOUNT=$(jq -r '.amount' "${TX_FILE}" 2>/dev/null)
NONCE=$(jq -r '.nonce' "${TX_FILE}" 2>/dev/null)
TIMESTAMP=$(jq -r '.timestamp' "${TX_FILE}" 2>/dev/null)
TX_HASH=$(jq -r '.hash' "${TX_FILE}" 2>/dev/null)
SIGNATURE=$(jq -r '.signature' "${TX_FILE}" 2>/dev/null)

echo "Validating transaction ${TX_HASH}..."

# Basic validation
if [ -z "${FROM}" ] || [ -z "${TO}" ] || [ -z "${AMOUNT}" ] || [ -z "${NONCE}" ]; then
    echo "Error: Missing required fields"
    exit 1
fi

# Validate amount is positive
if (( $(echo "${AMOUNT} <= 0" | bc -l) )); then
    echo "Error: Amount must be positive"
    exit 1
fi

# Verify hash
EXPECTED_HASH=$(echo -n "${FROM}|${TO}|${AMOUNT}|${NONCE}|${TIMESTAMP}" | sha256sum | cut -d' ' -f1)
if [ "${TX_HASH}" != "${EXPECTED_HASH}" ]; then
    echo "Error: Transaction hash mismatch"
    exit 1
fi

# Check for double spending - verify nonce is unique.
# NOTE: the ledger is stored as compact JSONL (jq -c, no spaces), so we must
# match with jq rather than a spaced grep pattern which would never match.
if [ -f "${LEDGER_DIR}/transactions.jsonl" ] && \
   [ -n "$(jq -r --arg n "${NONCE}" 'select(.nonce == $n) | .nonce' "${LEDGER_DIR}/transactions.jsonl" 2>/dev/null | head -n1)" ]; then
    echo "Error: Duplicate nonce detected (double spending attempt)"
    exit 1
fi

# Verify signature.
# The signature is a *detached* GPG signature over the transaction hash, so we
# verify it against the exact TX_HASH. This binds the signature to this specific
# transaction (the hash itself is bound to from|to|amount|nonce|timestamp and was
# verified above). A signature over any other payload will fail here.
SIG_FILE="/tmp/sig_${TX_HASH}.asc"
DATA_FILE="/tmp/data_${TX_HASH}.txt"
echo "${SIGNATURE}" | base64 -d > "${SIG_FILE}" 2>/dev/null
printf '%s' "${TX_HASH}" > "${DATA_FILE}"

if gpg --verify "${SIG_FILE}" "${DATA_FILE}" 2>&1 | grep -q "Good signature from \"${FROM} "; then
    echo "Signature verified"
else
    echo "Error: Invalid signature"
    rm -f "${SIG_FILE}" "${DATA_FILE}"
    exit 1
fi
rm -f "${SIG_FILE}" "${DATA_FILE}"

# Pre-check sender balance (advisory, fast fail). The authoritative check is
# performed again inside the locked critical section below to avoid TOCTOU races.
/scripts/consensus.sh calculate > /dev/null 2>&1

if [ -f "${LEDGER_DIR}/balances.json" ]; then
    SENDER_BALANCE=$(jq -r ".\"${FROM}\" // 0" "${LEDGER_DIR}/balances.json")
    
    if (( $(echo "${SENDER_BALANCE} < ${AMOUNT}" | bc -l) )); then
        echo "Error: Insufficient balance. ${FROM} has ${SENDER_BALANCE}, needs ${AMOUNT}"
        exit 1
    fi
else
    echo "Warning: Could not verify balance"
fi

# All validations passed
echo "Transaction validation successful!"

# Add to ledger if requested.
#
# The whole "check nonce -> check balance -> append -> recompute balances" must
# be atomic: we hold an exclusive ledger lock for the entire critical section so
# no concurrent transaction can be admitted between the balance check and the
# append (which would otherwise allow a double-spend). consensus.sh uses a
# separate balances lock, so calling it here does not deadlock on this lock.
if [ "$ADD_TO_LEDGER" == "true" ]; then
    echo "Adding transaction to ledger..."

    (
        flock -x 200

        # Re-check for duplicate nonce under lock.
        if [ -n "$(jq -r --arg n "${NONCE}" 'select(.nonce == $n) | .nonce' "${LEDGER_DIR}/transactions.jsonl" 2>/dev/null | head -n1)" ]; then
            echo "Error: Duplicate nonce detected under lock (double spending attempt)"
            exit 10
        fi

        # Re-check balance under lock (authoritative).
        /scripts/consensus.sh calculate > /dev/null 2>&1
        SENDER_BALANCE=$(jq -r ".\"${FROM}\" // 0" "${LEDGER_DIR}/balances.json" 2>/dev/null)
        if (( $(echo "${SENDER_BALANCE:-0} < ${AMOUNT}" | bc -l) )); then
            echo "Error: Insufficient balance under lock. ${FROM} has ${SENDER_BALANCE}, needs ${AMOUNT}"
            exit 11
        fi

        # Append to ledger (ensure compact JSONL format).
        jq -c . "${TX_FILE}" >> "${LEDGER_DIR}/transactions.jsonl"

        # Recompute balances to reflect the newly committed transaction.
        /scripts/consensus.sh calculate > /dev/null 2>&1
    ) 200>/var/lock/ledger.lock
    LOCK_RC=$?

    # Always drop the pending copy for this tx.
    rm -f "${PENDING_DIR}/tx_${TX_HASH}.json"

    if [ "${LOCK_RC}" -ne 0 ]; then
        echo "Transaction rejected during atomic commit (code ${LOCK_RC})"
        exit 1
    fi

    echo "Transaction added to ledger"
fi

exit 0

