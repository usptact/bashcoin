# BashCoin Architecture Documentation

## System Overview

BashCoin is a distributed ledger system that implements blockchain-like concepts using standard Linux tools. This document provides a detailed technical overview of the system architecture.

## Design Principles

1. **Simplicity**: Use standard Linux tools (bash, rsync, jq, gpg)
2. **Transparency**: Text-based ledger that's human-readable
3. **Decentralization**: No single point of failure
4. **Cryptographic Security**: GPG for signing and verification
5. **Time Synchronization**: NTP ensures consistent timestamps
6. **Double-spend Prevention**: Nonces and hash verification

## Component Architecture

### 1. Container Layer

```
┌─────────────────────────────────────────────────────────┐
│                  Docker Host                            │
│                                                         │
│  ┌─────────────┐                                        │
│  │  NTP Server │  (172.25.0.10)                        │
│  │  (Alpine)   │                                        │
│  └──────┬──────┘                                        │
│         │ UDP 123                                       │
│         │                                               │
│  ┌──────┴───────────────────────────────┐              │
│  │                                      │              │
│  ▼                                      ▼              │
│ ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐       │
│ │ Node 1 │  │ Node 2 │  │ Node 3 │  │ ...    │       │
│ │ .0.11  │  │ .0.12  │  │ .0.13  │  │        │       │
│ └────────┘  └────────┘  └────────┘  └────────┘       │
│                                                         │
│           bashcoin-network (172.25.0.0/16)            │
└─────────────────────────────────────────────────────────┘
```

### 2. Node Internal Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Ledger Node                        │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │         entrypoint.sh (Init)                 │  │
│  └────────────────┬─────────────────────────────┘  │
│                   │                                │
│  ┌────────────────▼─────────────────────────────┐  │
│  │         init-node.sh                         │  │
│  │  • Generate GPG keys                         │  │
│  │  • Start rsync daemon                        │  │
│  │  • Initialize ledger                         │  │
│  │  • Exchange public keys                      │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │    Daemon Layer (Background Services)        │  │
│  │                                              │  │
│  │  ┌────────────────┐                        │  │
│  │  │ NTP Client     │                        │  │
│  │  │ (ntpd)         │                        │  │
│  │  └────────────────┘                        │  │
│  │                                              │  │
│  │  ┌────────────────┐  ┌──────────────────┐  │  │
│  │  │ Rsync Daemon   │  │ Ledger Daemon    │  │  │
│  │  │ (port 873)     │  │ (port 9000,socat)│  │  │
│  │  └────────────────┘  └──────────────────┘  │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │      Application Scripts                     │  │
│  │                                              │  │
│  │  • create-transaction.sh                     │  │
│  │  • validate-transaction.sh                   │  │
│  │  • broadcast.sh                              │  │
│  │  • sync-ledger.sh                            │  │
│  │  • consensus.sh                              │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │         Data Storage                         │  │
│  │                                              │  │
│  │  /data/                                      │  │
│  │  ├── ledger/                                 │  │
│  │  │   ├── transactions.jsonl                  │  │
│  │  │   └── balances.json                       │  │
│  │  ├── keys/                                   │  │
│  │  │   ├── public.key                          │  │
│  │  │   └── *_public.key                        │  │
│  │  └── pending/                                │  │
│  │      └── tx_*.json                           │  │
│  └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

### 3. Transaction Flow

```
┌─────────┐                                    ┌─────────┐
│ Node 1  │                                    │ Node 2  │
│ (Sender)│                                    │(Receiver)│
└────┬────┘                                    └────┬────┘
     │                                              │
     │ 1. Create Transaction                        │
     │    • Generate nonce                          │
     │    • Calculate hash                          │
     │    • Sign with GPG                           │
     │                                              │
     │ 2. Validate Locally                          │
     │    • Check balance                           │
     │    • Verify signature                        │
     │                                              │
     │ 3. Broadcast (TCP port 9000)                 │
     ├──────────────────────────────────────────────►
     │                                              │
     │                         4. Receive Transaction
     │                            • Store in pending │
     │                                              │
     │                         5. Validate           │
     │                            • Verify hash      │
     │                            • Check signature  │
     │                            • Check nonce      │
     │                            • Verify balance   │
     │                                              │
     │                         6. Add to Ledger      │
     │                            • Append to JSONL  │
     │                            • Update balances  │
     │                                              │
     │ 7. Sync (rsync)                              │
     ◄──────────────────────────────────────────────┤
     │                                              │
     │ 8. Consensus                                 │
     │    • Recalculate balances                    │
     │    • Verify integrity                        │
     │                                              │
```

## Data Structures

### Transaction Object

```json
{
  "type": "transaction",
  "from": "node1",
  "to": "node2",
  "amount": 50,
  "nonce": "abc123def456...",
  "timestamp": "2025-10-14T12:00:00Z",
  "hash": "sha256_hash_of_transaction",
  "signature": "base64_encoded_gpg_signature"
}
```

### Genesis Block

```json
{
  "type": "genesis",
  "node": "node1",
  "timestamp": "2025-10-14T00:00:00Z",
  "message": "Genesis block for BashCoin distributed ledger"
}
```

### Balance State

```json
{
  "node1": 950,
  "node2": 1050,
  "node3": 1000,
  "node4": 1000,
  "node5": 1000
}
```

## Security Mechanisms

### 1. Cryptographic Signing

- **GPG Keys**: Each node has a 2048-bit RSA keypair
- **Signature**: Transaction hash signed with private key
- **Verification**: Other nodes verify using public key

The signature is a **detached** signature over the transaction hash, so verifiers
can bind it to the exact hash of the transaction being validated (the hash itself
is bound to `from|to|amount|nonce|timestamp`). This prevents attaching a valid
signature over one payload to a different transaction.

```bash
# Sign (detached signature over the hash)
echo -n "${TX_HASH}" | gpg --armor --detach-sign --local-user "${NODE_ID}@bashcoin.local"

# Verify against the exact hash
printf '%s' "${TX_HASH}" > data.txt
gpg --verify signature_file data.txt
```

### 2. Double-spending Prevention

**Nonce Generation:**
```bash
NONCE=$(echo "${NODE_ID}-$(date +%s%N)-${RANDOM}" | sha256sum | cut -d' ' -f1)
```

**Nonce Verification:** the ledger is compact JSONL, so uniqueness is checked
with `jq` (a spaced `grep` pattern would never match). The check and the ledger
append are performed together inside an exclusive `flock` critical section so
concurrent transactions cannot race between the check and the commit.
```bash
if [ -n "$(jq -r --arg n "${NONCE}" 'select(.nonce == $n) | .nonce' \
        "${LEDGER_DIR}/transactions.jsonl" | head -n1)" ]; then
    echo "Duplicate nonce detected"
    exit 1
fi
```

### 3. Hash Integrity

**Hash Calculation:**
```bash
TX_DATA="${FROM}|${TO}|${AMOUNT}|${NONCE}|${TIMESTAMP}"
TX_HASH=$(echo -n "${TX_DATA}" | sha256sum | cut -d' ' -f1)
```

**Hash Verification:**
```bash
EXPECTED_HASH=$(echo -n "${FROM}|${TO}|${AMOUNT}|${NONCE}|${TIMESTAMP}" | sha256sum)
if [ "${TX_HASH}" != "${EXPECTED_HASH}" ]; then
    echo "Hash mismatch"
    exit 1
fi
```

### 4. Balance Verification

```bash
SENDER_BALANCE=$(jq -r ".\"${FROM}\" // 0" "${LEDGER_DIR}/balances.json")

if (( $(echo "${SENDER_BALANCE} < ${AMOUNT}" | bc -l) )); then
    echo "Insufficient balance"
    exit 1
fi
```

## Synchronization Mechanism

### Rsync Daemon Configuration

```
[ledger]
    path = /data/ledger
    read only = yes
    
[pending]
    path = /data/pending
    read only = yes
```

### Sync Process

1. **Fetch Ledgers**: Download from all nodes
2. **Merge**: Combine unique transactions
3. **Validate**: Verify each transaction
4. **Update**: Add valid transactions to local ledger
5. **Recalculate**: Update balance state

```bash
rsync -az rsync://172.25.0.12:873/ledger/transactions.jsonl ./remote_ledger.jsonl
```

## Consensus Mechanism

### Simplified Consensus

BashCoin uses a simplified consensus model:

1. **Immediate Acceptance**: Valid transactions are accepted immediately
2. **Balance Calculation**: Balances computed from transaction history
3. **Eventual Consistency**: Nodes sync periodically to ensure consistency

### Balance Calculation Algorithm

```bash
# Initialize with genesis balances
BALANCES = {node1: 1000, node2: 1000, ...}

# Process each transaction in order
for transaction in ledger:
    BALANCES[from] -= amount
    BALANCES[to] += amount
```

### Conflict Resolution

In case of conflicts:
1. Transaction with earlier timestamp wins
2. If timestamps equal, lower hash value wins
3. Nodes with incorrect state will sync and update

## Network Communication

### TCP Broadcasting (Port 9000)

Used for transaction propagation:

```bash
# Sender (broadcast.sh)
cat transaction.json | nc ${NODE_IP} 9000

# Receiver (ledger-daemon.sh) — a persistent, concurrent listener that forks a
# handler per connection so broadcasts are not dropped while one is processed.
socat -T 15 TCP-LISTEN:9000,reuseaddr,fork EXEC:"/scripts/ledger-daemon.sh --handle"
```

### Rsync (Port 873)

Used for ledger synchronization and public key sharing:

```bash
rsync -az rsync://${NODE_IP}:873/ledger/transactions.jsonl local_copy.jsonl
```

### NTP (Port 123 UDP)

Used for time synchronization:

```bash
ntpd -s -S /usr/sbin/ntpd
```

## File System Layout

```
/data/
├── ledger/
│   ├── transactions.jsonl    # Main ledger file (append-only)
│   └── balances.json         # Current balance state
├── keys/
│   ├── public.key            # This node's public key
│   ├── node1_public.key      # Other nodes' public keys
│   ├── node2_public.key
│   └── ...
└── pending/
    └── tx_*.json             # Pending transactions

/root/.gnupg/                 # GPG keyring
/scripts/                     # Application scripts
```

## Performance Considerations

### Scalability

- **Current**: 5 nodes, ~10 TPS (transactions per second)
- **Bottleneck**: Single-threaded transaction processing
- **Optimization**: Could use parallel processing with proper locking

### Network Bandwidth

- **Transaction Size**: ~1KB per transaction
- **Ledger Sync**: Full ledger transferred during sync
- **Optimization**: Implement incremental sync

### Storage

- **Ledger Growth**: Linear with transaction count
- **Current**: ~1KB per transaction
- **1000 transactions**: ~1MB
- **1 million transactions**: ~1GB

## Failure Modes and Recovery

### Node Failure

**Detection**: Node doesn't respond to network requests

**Recovery:**
1. Restart node
2. Run `/scripts/sync-ledger.sh`
3. Node catches up with network

### Network Partition

**Detection**: Nodes can't communicate

**Recovery:**
1. When partition heals, nodes sync
2. Conflicts resolved by consensus rules

### Data Corruption

**Detection**: Hash mismatch, invalid signatures

**Recovery:**
1. Delete corrupted ledger
2. Sync from healthy nodes
3. Rebuild local state

## Future Enhancements

### 1. Byzantine Fault Tolerance

Implement PBFT or similar consensus algorithm to handle malicious nodes.

### 2. Sharding

Partition ledger across nodes for better scalability.

### 3. Smart Contracts

Add programmable transaction logic using bash scripts or embedded language.

### 4. Merkle Trees

Implement Merkle trees for efficient ledger verification.

### 5. Proof of Work

Add mining mechanism for transaction validation.

### 6. REST API

Create HTTP API for easier integration with external applications.

## Monitoring and Debugging

### Log Files

```bash
# Rsync logs
/var/log/rsyncd.log

# System logs
/var/log/messages
```

### Metrics

```bash
# Transaction count
wc -l /data/ledger/transactions.jsonl

# Node balance
jq ".\"${NODE_ID}\"" /data/ledger/balances.json

# Network connections
netstat -tuln
```

### Debug Mode

```bash
# Run script with debugging
bash -x /scripts/create-transaction.sh node2 50

# Verbose GPG
gpg --verbose --verify signature
```

## Security Best Practices

### For Production Use

1. **Use TLS**: Encrypt all network communication
2. **Key Management**: Secure key storage and rotation
3. **Access Control**: Implement proper authentication
4. **Audit Logs**: Comprehensive logging of all operations
5. **Rate Limiting**: Prevent DoS attacks
6. **Input Validation**: Sanitize all inputs
7. **Regular Backups**: Backup ledger data regularly

## Testing Strategy

### Unit Tests

Test individual components:
- Transaction creation
- Signature verification
- Balance calculation
- Nonce uniqueness

### Integration Tests

Test component interaction:
- End-to-end transaction flow
- Multi-node synchronization
- Failure recovery

### Stress Tests

Test under load:
- High transaction volume
- Network latency
- Node failures

## Conclusion

BashCoin demonstrates distributed ledger concepts using simple, understandable tools. While not suitable for production use, it provides excellent learning opportunities for understanding blockchain technology, distributed systems, and cryptographic security.

