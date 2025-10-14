<div align="center">
  <img src="logo.png" alt="BashCoin Logo" width="200"/>
</div>

# BashCoin - Quick Start Guide

Get up and running with BashCoin in 5 minutes!

## Step 1: Start the System

```bash
docker-compose up -d
```

Wait 10-15 seconds for initialization.

## Step 2: Check Status

```bash
docker-compose ps
```

You should see 6 containers running:
- bashcoin-ntp (NTP server)
- bashcoin-node1 through bashcoin-node5 (ledger nodes)

## Step 3: Send Your First Transaction

```bash
# Connect to node1
docker exec -it bashcoin-node1 bash

# Send 50 coins to node2
/scripts/create-transaction.sh node2 50
```

You should see output like:
```
Transaction created:
{
  "type": "transaction",
  "from": "node1",
  "to": "node2",
  "amount": 50,
  ...
}
Broadcasting transaction to network...
Transaction broadcast complete!
```

## Step 4: Check Balances

```bash
# While still in node1
/scripts/consensus.sh balance
```

Expected output:
```
Current balances:
{
  "node1": 950,
  "node2": 1050,
  "node3": 1000,
  "node4": 1000,
  "node5": 1000
}

Your balance (node1): 950
```

## Step 5: Verify on Another Node

```bash
# Exit node1
exit

# Connect to node2
docker exec -it bashcoin-node2 bash

# Check balance
/scripts/consensus.sh balance
```

You should see the same balances!

## Step 6: View Transaction History

```bash
# View all transactions in pretty format
cat /data/ledger/transactions.jsonl | jq .

# Count transactions
wc -l /data/ledger/transactions.jsonl
```

## Common Commands

### Inside a Node Container

```bash
# Send transaction
/scripts/create-transaction.sh <destination> <amount>

# Check balance
/scripts/consensus.sh balance

# View statistics
/scripts/consensus.sh stats

# Sync with network
/scripts/sync-ledger.sh

# View ledger
cat /data/ledger/transactions.jsonl | jq .
```

### From Host Machine

```bash
# View logs
docker-compose logs -f node1

# Execute command in container
docker exec -it bashcoin-node1 /scripts/consensus.sh balance

# Stop all
docker-compose down

# Start all
docker-compose up -d

# Rebuild and restart
docker-compose down
docker-compose build
docker-compose up -d
```

## Test Scenarios

### Scenario 1: Simple Transfer

```bash
docker exec -it bashcoin-node1 /scripts/create-transaction.sh node2 100
docker exec -it bashcoin-node2 /scripts/consensus.sh balance
```

### Scenario 2: Multiple Transactions

```bash
# From node1 to multiple nodes
docker exec -it bashcoin-node1 bash
/scripts/create-transaction.sh node2 50
/scripts/create-transaction.sh node3 50
/scripts/create-transaction.sh node4 50
exit

# Check balance
docker exec -it bashcoin-node1 /scripts/consensus.sh balance
```

### Scenario 3: Node Synchronization

```bash
# Stop node3
docker-compose stop node3

# Send transaction from node1
docker exec -it bashcoin-node1 /scripts/create-transaction.sh node2 25

# Restart node3
docker-compose start node3

# Wait a moment, then sync node3
docker exec -it bashcoin-node3 /scripts/sync-ledger.sh

# Verify balance
docker exec -it bashcoin-node3 /scripts/consensus.sh balance
```

## Troubleshooting

### Problem: Transaction not showing up

**Solution:**
```bash
# Manually sync the node
docker exec -it bashcoin-node2 /scripts/sync-ledger.sh
```

### Problem: Container won't start

**Solution:**
```bash
# Check logs
docker-compose logs node1

# Rebuild
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

### Problem: Insufficient balance error

**Solution:**
```bash
# Check your actual balance first
docker exec -it bashcoin-node1 /scripts/consensus.sh balance

# Recalculate if needed
docker exec -it bashcoin-node1 /scripts/consensus.sh calculate
```

## Clean Up

```bash
# Stop everything
docker-compose down

# Stop and remove all data (including ledgers)
docker-compose down -v
```

## Next Steps

- Read the full [README.md](README.md) for detailed documentation
- Explore the scripts in the `scripts/` directory
- Try modifying transaction amounts and recipients
- Monitor network activity with `docker-compose logs -f`

## Getting Help

If something isn't working:
1. Check logs: `docker-compose logs <service-name>`
2. Verify containers are running: `docker-compose ps`
3. Test network connectivity: `docker network inspect bashcoin_bashcoin-network`
4. Read the detailed [README.md](README.md)

Happy transacting! 🚀

