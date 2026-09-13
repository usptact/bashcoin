#!/bin/bash

NODE_ID=${NODE_ID:-"node1"}
DATA_DIR="/data"
LEDGER_DIR="${DATA_DIR}/ledger"
PENDING_DIR="${DATA_DIR}/pending"
PORT=9000
LOG_FILE="/var/log/ledger-daemon.log"

# --------------------------------------------------------------------------
# Per-connection handler mode.
#
# socat invokes this script with `--handle` for every inbound connection, with
# the TCP socket wired to stdin/stdout. We read the transaction payload from
# stdin, then validate + commit it. Because socat forks a handler per
# connection, the listener never stops accepting, so broadcasts are no longer
# dropped while a transaction is being processed. Concurrent commits are made
# safe by the exclusive ledger lock inside validate-transaction.sh.
# --------------------------------------------------------------------------
if [ "$1" == "--handle" ]; then
    TMP_TX=$(mktemp /tmp/incoming_tx.XXXXXX)
    cat > "${TMP_TX}"

    if [ -s "${TMP_TX}" ]; then
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Received transaction" >> "${LOG_FILE}"
        if /scripts/validate-transaction.sh "${TMP_TX}" --add-to-ledger >> "${LOG_FILE}" 2>&1; then
            echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Transaction validated and added to ledger" >> "${LOG_FILE}"
        else
            echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Transaction validation failed" >> "${LOG_FILE}"
        fi
    fi

    rm -f "${TMP_TX}"
    exit 0
fi

# --------------------------------------------------------------------------
# Listener mode (default).
# --------------------------------------------------------------------------
echo "Starting ledger daemon on port ${PORT}..."

# Rsync daemon already started in init-node.sh; just make sure it's running.
if ! pgrep -x rsync > /dev/null; then
    echo "Warning: rsync daemon not running, attempting to start..."
    rsync --daemon
fi

# Persistent, concurrent listener. `fork` handles each connection in its own
# child so we keep accepting without the gaps/single-connection limits of a
# `nc -l` loop. `reuseaddr` allows quick restarts.
exec socat -T 15 TCP-LISTEN:${PORT},reuseaddr,fork EXEC:"/scripts/ledger-daemon.sh --handle"
