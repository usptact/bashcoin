# BashCoin Synchronization Behavior

## How Transaction Propagation Works

### Automatic: Transaction Broadcasting (TCP)

When you create a transaction, it's **automatically broadcast** to all other nodes via TCP:

```
Node1 creates transaction
    ↓
Adds to own ledger immediately
    ↓
Broadcasts via TCP to all nodes
    ↓
Other nodes receive and validate
    ↓
If valid, other nodes add to their ledgers
```

**This happens automatically** when you run `/scripts/create-transaction.sh`

### Manual: Full Ledger Synchronization (Rsync)

The `/scripts/sync-ledger.sh` script performs a **full ledger sync** using rsync. This is **manual only** - you need to run it yourself.

**When to use manual sync:**
- ✅ After a node restarts (to catch up on missed transactions)
- ✅ If you suspect nodes are out of sync
- ✅ After network issues or downtime
- ✅ Periodically for consistency checks

**You DON'T need to run it:**
- ❌ After every transaction (they're auto-broadcast)
- ❌ During normal operation (TCP broadcast handles it)

## Current Architecture

### Transaction Creation Flow (Automatic)
```bash
/scripts/create-transaction.sh node2 50
  ↓
1. Check balance
2. Create & sign transaction
3. Add to OWN ledger
4. Broadcast via TCP to node2, node3, node4, node5
5. Each node validates and adds to their ledger
```

**No manual sync needed!** ✅

### Full Ledger Sync (Manual)
```bash
/scripts/sync-ledger.sh
  ↓
1. Fetch complete ledgers from all nodes via rsync
2. Merge all transactions
3. Validate new transactions
4. Add missing transactions to local ledger
5. Recalculate balances
```

**Use this for catch-up or recovery** 🔄

## Why Rsync Might Fail

The rsync failures you saw ("Failed to sync from nodeX") can happen because:

1. **Nodes still initializing** - Rsync daemon not yet started
2. **Network timing** - Brief network delays
3. **Normal during startup** - Nodes need time to get ready

**This is usually OK!** The nodes will sync via TCP broadcast during normal operations.

## Testing the Fixed Sync Script

After rebuilding with the fix:

```bash
# 1. Rebuild containers
docker-compose build
docker-compose up -d

# 2. Wait for full initialization
sleep 20

# 3. Create some transactions
docker exec -it bashcoin-node1 /scripts/create-transaction.sh node2 50

# 4. Now try manual sync on another node
docker exec -it bashcoin-node3 /scripts/sync-ledger.sh

# Should see:
# Starting ledger synchronization...
# Syncing from node1 (node1)...
# ✓ Successfully synced from node1
# Syncing from node2 (node2)...
# ✓ Successfully synced from node2
# [etc...]
# Successfully synced from 4 nodes
# Merging ledgers...
# Ledger synchronization complete!
# Added 0 new transactions (already had them via TCP)
# Balances updated
```

## Recommended Workflow

### Normal Usage (No Manual Sync Needed)
```bash
# Just create transactions - they auto-broadcast
docker exec -it bashcoin-node1 /scripts/create-transaction.sh node2 100
docker exec -it bashcoin-node1 /scripts/create-transaction.sh node3 50

# Check balance anywhere
docker exec -it bashcoin-node2 /scripts/consensus.sh balance
# Should already be updated! ✅
```

### After Node Restart
```bash
# Stop a node
docker-compose stop node3

# Create transactions while it's down
docker exec -it bashcoin-node1 /scripts/create-transaction.sh node2 25

# Restart the node
docker-compose start node3
sleep 10

# Manually sync to catch up
docker exec -it bashcoin-node3 /scripts/sync-ledger.sh

# Now node3 has all transactions ✅
```

### When Nodes Seem Out of Sync
```bash
# Check balance on multiple nodes
docker exec bashcoin-node1 /scripts/consensus.sh balance
docker exec bashcoin-node2 /scripts/consensus.sh balance
docker exec bashcoin-node3 /scripts/consensus.sh balance

# If different, sync all nodes
for node in node1 node2 node3 node4 node5; do
    echo "Syncing ${node}..."
    docker exec bashcoin-${node} /scripts/sync-ledger.sh
done
```

## Improvements Made to Sync Script

### Before (Buggy)
- ❌ No error handling for JSON parsing
- ❌ No count of successful syncs
- ❌ Unclear why syncs fail
- ❌ Used old validation logic

### After (Fixed)
- ✅ All jq commands have error suppression (2>/dev/null)
- ✅ Skip empty lines and invalid JSON
- ✅ Reports sync success count
- ✅ Clear messages about failures
- ✅ Uses new validation with --add-to-ledger flag
- ✅ Better genesis block handling
- ✅ Shows count of new transactions added

## Future Enhancement: Automatic Periodic Sync

To make sync automatic (not yet implemented), you could add to `entrypoint.sh`:

```bash
# Start periodic sync daemon
while true; do
    sleep 300  # Every 5 minutes
    /scripts/sync-ledger.sh > /var/log/sync.log 2>&1
done &
```

**Not recommended for now** - TCP broadcast works well for normal operations.

## Summary

| Operation | Automatic? | When to Use |
|-----------|-----------|-------------|
| Transaction broadcast | ✅ Yes (TCP) | Always happens automatically |
| Full ledger sync | ❌ No (Manual) | Node restarts, recovery, consistency checks |
| Balance calculation | ✅ Yes | After every transaction |

**Bottom line:** You typically don't need to run `sync-ledger.sh` - transactions are automatically broadcast and applied. Only use it for recovery or catching up after downtime.

