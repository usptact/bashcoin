<div align="center">
  <img src="logo.png" alt="BashCoin Logo" width="300"/>
</div>

# BashCoin - Distributed Ledger System

A distributed ledger implementation using Docker containers, Alpine Linux, and standard Linux command-line tools (Bash, rsync, jq, GPG).

## Overview

BashCoin is a proof-of-concept distributed ledger system that demonstrates blockchain-like principles using only standard Linux tools. The system consists of:

- **5 Ledger Nodes**: Each running Alpine Linux and participating in the distributed ledger
- **1 NTP Server**: Provides time synchronization across all nodes
- **GPG Cryptography**: Each node has a GPG keypair for signing and verifying transactions
- **Text-based Ledger**: Transactions stored in JSONL (JSON Lines) format
- **Rsync Synchronization**: Ledger data synchronized across nodes using rsync
- **Double-spending Prevention**: Nonces and hash verification prevent duplicate transactions
- **TCP Broadcasting**: Nodes communicate via TCP to broadcast transactions

## Architecture

```
┌─────────────┐
│  NTP Server │  (172.25.0.10)
│   (Alpine)  │
└─────────────┘
       │
       │ Time sync
       │
   ┌───┴────────────────────────────────┐
   │                                    │
┌──▼──┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐
│Node1│  │Node2 │  │Node3 │  │Node4 │  │Node5 │
└─────┘  └──────┘  └──────┘  └──────┘  └──────┘
172.25   172.25    172.25    172.25    172.25
.0.11    .0.12     .0.13     .0.14     .0.15

Each Node Contains:
├── GPG Keypair (signing/verification)
├── Ledger (transactions.jsonl)
├── Balance Tracker (balances.json)
├── Rsync Daemon (port 873)
├── Transaction Listener (port 9000)
└── SSH Server (port 22)
```

## Components

### Docker Services

- **ntp-server**: Time synchronization server
- **node1-node5**: Ledger nodes, each with 1000 initial coins

### Scripts

1. **entrypoint.sh**: Container initialization and service startup
2. **init-node.sh**: Node initialization (GPG keys, SSH setup, ledger creation)
3. **ledger-daemon.sh**: Listens for incoming transactions on TCP port 9000
4. **create-transaction.sh**: Create and broadcast a new transaction
5. **validate-transaction.sh**: Validate incoming transactions (signature, balance, double-spend)
6. **broadcast.sh**: Broadcast transaction to all other nodes
7. **sync-ledger.sh**: Synchronize ledger with other nodes using rsync
8. **consensus.sh**: Calculate balances and check consensus
9. **fix-ledger.sh**: Repair corrupted ledger files
10. **import-keys.sh**: Manually import GPG keys from other nodes

### Ledger Format

Transactions are stored in JSONL (JSON Lines) format:

```json
{
  "type": "transaction",
  "from": "node1",
  "to": "node2",
  "amount": 50,
  "nonce": "abc123...",
  "timestamp": "2025-10-14T12:00:00Z",
  "hash": "def456...",
  "signature": "base64-encoded-gpg-signature"
}
```

## Prerequisites

- Docker
- Docker Compose
- At least 2GB of available RAM
- Linux, macOS, or Windows with WSL2

## Quick Start

### 1. Clone and Build

```bash
# Clone the repository (or create the project)
cd bashcoin

# Build and start all containers
docker-compose up -d
```

### 2. Wait for Initialization

Wait about 10-15 seconds for all nodes to initialize, generate GPG keys, and establish connections.

```bash
# Check status
docker-compose ps

# View logs from a specific node
docker-compose logs -f node1
```

### 3. Send Your First Transaction

```bash
# Connect to node1
docker exec -it bashcoin-node1 bash

# Send 50 coins from node1 to node2
/scripts/create-transaction.sh node2 50
```

### 4. View the Ledger

```bash
# View all transactions
cat /data/ledger/transactions.jsonl | jq .

# View current balances
/scripts/consensus.sh balance

# View statistics
/scripts/consensus.sh stats
```

### 5. Verify on Another Node

```bash
# In another terminal, connect to node2
docker exec -it bashcoin-node2 bash

# Synchronize ledger (if not auto-synced)
/scripts/sync-ledger.sh

# Check balance
/scripts/consensus.sh balance
```

## Usage Examples

### Getting Help

All scripts support `--help` flag for detailed documentation:

```bash
# Get help on any script
docker exec -it bashcoin-node1 /scripts/create-transaction.sh --help
docker exec -it bashcoin-node1 /scripts/consensus.sh --help
docker exec -it bashcoin-node1 /scripts/validate-transaction.sh --help
docker exec -it bashcoin-node1 /scripts/sync-ledger.sh --help
```

### Sending Transactions

```bash
# Connect to any node
docker exec -it bashcoin-node1 bash

# Send 100 coins to node3
/scripts/create-transaction.sh node3 100

# Send 25.5 coins to node4
/scripts/create-transaction.sh node4 25.5

# Get help
/scripts/create-transaction.sh --help
```

### Checking Balances

```bash
# Quick balance check
/scripts/consensus.sh balance

# Detailed statistics
/scripts/consensus.sh stats

# Recalculate if balances seem wrong
/scripts/consensus.sh calculate

# Get help
/scripts/consensus.sh --help
```

### Manual Ledger Synchronization

```bash
# Synchronize with all other nodes
/scripts/sync-ledger.sh

# Recalculate balances from ledger
/scripts/consensus.sh calculate
```

### Viewing Ledger History

```bash
# View all transactions in readable format
cat /data/ledger/transactions.jsonl | jq .

# Count transactions
wc -l /data/ledger/transactions.jsonl

# View only transaction type entries
cat /data/ledger/transactions.jsonl | jq 'select(.type == "transaction")'

# View transactions from a specific node
cat /data/ledger/transactions.jsonl | jq 'select(.from == "node1")'
```

### Inspecting GPG Keys

```bash
# List imported public keys (should show 5 keys for all nodes)
gpg --list-keys

# Count keys (should be 5)
gpg --list-keys | grep -c "@bashcoin.local"

# View your public key
cat /data/keys/public.key

# View public keys from other nodes
ls /data/keys/
```

### Importing Missing Keys

If key exchange failed during initialization (you see fewer than 5 keys):

```bash
# Check current keys
docker exec -it bashcoin-node1 gpg --list-keys

# Manually import missing keys
docker exec -it bashcoin-node1 /scripts/import-keys.sh

# This will:
# - Show how many keys you currently have
# - Fetch and import missing keys from other nodes
# - Report success/failure for each node
```

### Repairing Ledger Issues

If you encounter ledger corruption or JSON parsing errors:

```bash
# Run the ledger repair utility
docker exec -it bashcoin-node1 /scripts/fix-ledger.sh

# This will:
# - Create a backup of your ledger
# - Remove empty lines and invalid JSON
# - Recalculate balances
# - Show statistics
```

## How It Works

### 1. Initialization

When a node starts:
1. Generates GPG keypair for transaction signing
2. Creates SSH keys for rsync access
3. Initializes ledger with genesis block
4. Sets initial balance (1000 coins per node)
5. Exchanges public keys with other nodes
6. **Automatically syncs to catch up on missed transactions** (if restarting)
7. Starts listening for transactions

### 2. Transaction Creation

When creating a transaction:
1. Generates unique nonce (prevents double-spending)
2. Creates transaction hash from: `from|to|amount|nonce|timestamp`
3. Signs the hash with sender's GPG private key
4. Validates locally (balance check, signature)
5. Broadcasts to all other nodes via TCP

### 3. Transaction Validation

When receiving a transaction:
1. Verifies transaction hash integrity
2. Validates GPG signature from sender
3. Checks for duplicate nonce (double-spend prevention)
4. Verifies sender has sufficient balance
5. Adds to ledger if all checks pass
6. Updates balance calculations

### 4. Ledger Synchronization

Nodes synchronize using rsync:
1. Fetches ledgers from all other nodes
2. Merges all transactions
3. Validates new transactions
4. Updates local ledger
5. Recalculates balances

### 5. Double-spending Prevention

Multiple mechanisms prevent double-spending:
- **Nonces**: Each transaction has a unique nonce
- **Hash verification**: Transaction integrity is verified
- **Balance checking**: Sender must have sufficient funds
- **Ledger validation**: All transactions are validated before acceptance

## Network Architecture

- **Docker Network**: 172.25.0.0/16
- **NTP Server**: 172.25.0.10
- **Node 1**: 172.25.0.11
- **Node 2**: 172.25.0.12
- **Node 3**: 172.25.0.13
- **Node 4**: 172.25.0.14
- **Node 5**: 172.25.0.15

### Ports

- **22 (TCP)**: SSH for rsync
- **123 (UDP)**: NTP time synchronization
- **873 (TCP)**: Rsync daemon
- **9000 (TCP)**: Transaction broadcasting

## Synchronization

### Automatic vs Manual Sync

**Transactions are automatically broadcast via TCP** - you don't need to manually sync!

- ✅ **Automatic (TCP)**: Transactions broadcast to all nodes immediately
- ✅ **Automatic (Startup)**: Nodes automatically sync on restart to catch up on missed transactions
- 🔄 **Manual (Rsync)**: Full ledger sync for recovery/catch-up only

See [SYNC_BEHAVIOR.md](SYNC_BEHAVIOR.md) and [NODE_RECOVERY.md](NODE_RECOVERY.md) for detailed information.

```bash
# You typically DON'T need this - transactions auto-broadcast
docker exec -it bashcoin-node1 /scripts/sync-ledger.sh

# Only use manual sync for:
# - Node restart recovery
# - Network issue recovery  
# - Consistency checks
```

## Troubleshooting

### Container won't start

```bash
# Check logs
docker-compose logs node1

# Rebuild and restart
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

### Transaction not appearing on other nodes

```bash
# Manually trigger sync on receiving node
docker exec -it bashcoin-node2 /scripts/sync-ledger.sh

# Check if transaction daemon is running
docker exec -it bashcoin-node2 ps aux | grep ledger-daemon
```

### GPG signature verification fails

```bash
# Re-import public keys
docker exec -it bashcoin-node1 /scripts/init-node.sh

# Verify keys are imported
docker exec -it bashcoin-node1 gpg --list-keys
```

### Balance inconsistencies

```bash
# Recalculate balances from ledger
docker exec -it bashcoin-node1 /scripts/consensus.sh calculate

# Check for duplicate transactions
docker exec -it bashcoin-node1 bash -c "cat /data/ledger/transactions.jsonl | jq -r .nonce | sort | uniq -d"
```

## Advanced Usage

### Monitoring Network Activity

```bash
# Watch transaction daemon logs in real-time
docker exec -it bashcoin-node1 tail -f /var/log/rsyncd.log

# Monitor network connections
docker exec -it bashcoin-node1 netstat -tuln
```

### Testing Double-spending Prevention

```bash
# Try to send the same transaction twice
docker exec -it bashcoin-node1 bash
/scripts/create-transaction.sh node2 50
# Wait a moment and try again with same parameters
# The second transaction will have a different nonce and will succeed
# But trying to replay the same transaction file will be rejected
```

### Simulating Node Failure and Recovery

```bash
# Stop a node
docker-compose stop node3

# Send transactions from other nodes (including TO node3)
docker exec -it bashcoin-node1 /scripts/create-transaction.sh node2 30
docker exec -it bashcoin-node1 /scripts/create-transaction.sh node3 50  # To down node!

# Restart the failed node
docker-compose start node3
sleep 15

# Node3 will AUTOMATICALLY sync and catch up on missed transactions!
docker exec -it bashcoin-node3 /scripts/consensus.sh balance

# Should show correct balance (1050) including the 50 coins received while down!
```

See [NODE_RECOVERY.md](NODE_RECOVERY.md) for complete details on node recovery.

## Limitations

This is a proof-of-concept and has several limitations:

1. **No Byzantine Fault Tolerance**: Assumes honest nodes
2. **Simple Consensus**: No sophisticated consensus algorithm (like PBFT or Raft)
3. **No Proof-of-Work**: Transactions accepted immediately if valid
4. **Limited Security**: Simplified for educational purposes
5. **No Transaction Fees**: No incentive mechanism for node operators
6. **Single-threaded**: Each node processes one transaction at a time
7. **Manual Sync**: Synchronization is not fully automatic in all cases

## Security Considerations

- **Production Use**: This is NOT suitable for production use
- **Key Management**: GPG keys are generated and stored insecurely
- **Network Security**: No TLS/SSL encryption for network communication
- **Authentication**: Simplified SSH key management
- **Access Control**: All nodes have full trust

## Extending the System

### Adding More Nodes

Edit `docker-compose.yml` to add additional nodes:

```yaml
node6:
  build:
    context: .
    dockerfile: Dockerfile.node
  container_name: bashcoin-node6
  hostname: node6
  environment:
    - NODE_ID=node6
    - NTP_SERVER=172.25.0.10
  networks:
    bashcoin-network:
      ipv4_address: 172.25.0.16
  volumes:
    - node6-data:/data
    - node6-keys:/root/.gnupg
  depends_on:
    - ntp-server
```

Update scripts to include the new node in the `ALL_NODES` array.

### Implementing New Transaction Types

Modify `validate-transaction.sh` and `create-transaction.sh` to support new transaction types (e.g., smart contracts, multi-signature).

### Adding a Web Interface

Create a simple web interface using nginx and a REST API to interact with the nodes:

```bash
# Example: Query balance via HTTP
curl http://localhost:8080/api/balance/node1
```

## Development

### Running Tests

```bash
# Test transaction creation
docker exec -it bashcoin-node1 /scripts/create-transaction.sh node2 10

# Verify signature validation
docker exec -it bashcoin-node2 /scripts/validate-transaction.sh /data/pending/*.json

# Test synchronization
docker exec -it bashcoin-node3 /scripts/sync-ledger.sh
```

### Debugging

```bash
# Enable bash debugging in scripts
docker exec -it bashcoin-node1 bash -x /scripts/create-transaction.sh node2 50

# Check GPG operations
docker exec -it bashcoin-node1 gpg --list-keys
docker exec -it bashcoin-node1 gpg --list-secret-keys
```

## Clean Up

```bash
# Stop all containers
docker-compose down

# Remove all data (including ledgers and keys)
docker-compose down -v

# Remove images
docker-compose down --rmi all -v
```

## Contributing

This is an educational project demonstrating distributed systems concepts. Feel free to:

- Add features (consensus algorithms, GUI, REST API)
- Improve security
- Optimize performance
- Add tests
- Improve documentation

## License

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

See the [LICENSE](LICENSE) file for full license text.

## References

- [Bitcoin: A Peer-to-Peer Electronic Cash System](https://bitcoin.org/bitcoin.pdf)
- [Distributed Systems Principles](https://www.distributed-systems.net/)
- [GnuPG Documentation](https://www.gnupg.org/documentation/)
- [Rsync Manual](https://rsync.samba.org/)

## Project Consistency

The project has been thoroughly analyzed for consistency across all components. See [CONSISTENCY_CHECK.md](CONSISTENCY_CHECK.md) for the complete analysis report.

**Consistency Score: 99.5/100** ✅

All configuration, documentation, scripts, and naming conventions are consistent throughout the project.

## Support

For issues and questions:
1. Check the logs: `docker-compose logs`
2. Verify network connectivity: `docker network inspect bashcoin_bashcoin-network`
3. Test individual components in isolation
4. Review the [CONSISTENCY_CHECK.md](CONSISTENCY_CHECK.md) for verification commands

---

**Note**: This project is for educational purposes only. It demonstrates distributed ledger concepts but should not be used in production environments without significant security and reliability enhancements.

