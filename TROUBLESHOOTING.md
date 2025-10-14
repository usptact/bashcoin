# BashCoin Troubleshooting Guide

This guide helps you diagnose and fix common issues with BashCoin.

## Quick Diagnostics

```bash
# Check if all containers are running
make status

# View logs from all containers
make logs

# Check specific node logs
docker-compose logs node1
```

## Common Issues

### 1. Containers Won't Start

#### Symptoms
- `docker-compose up` fails
- Containers immediately exit
- Port binding errors

#### Solutions

**Check if ports are already in use:**
```bash
# On Linux/Mac
sudo lsof -i :123
sudo lsof -i :9000

# On Windows PowerShell
netstat -ano | findstr :123
netstat -ano | findstr :9000
```

**Rebuild from scratch:**
```bash
make rebuild
```

**Check Docker resources:**
```bash
docker info
docker system df
```

**Clear Docker cache:**
```bash
docker system prune -a
make rebuild
```

### 2. Transaction Not Appearing on Other Nodes

#### Symptoms
- Transaction sent from node1
- Balance not updated on node2

#### Solutions

**Manual sync:**
```bash
docker exec -it bashcoin-node2 /scripts/sync-ledger.sh
docker exec -it bashcoin-node2 /scripts/consensus.sh balance
```

**Check if ledger daemon is running:**
```bash
docker exec -it bashcoin-node2 ps aux | grep ledger-daemon
```

**Restart the daemon:**
```bash
docker-compose restart node2
```

**Check network connectivity:**
```bash
docker exec -it bashcoin-node1 ping 172.25.0.12
docker exec -it bashcoin-node1 nc -zv 172.25.0.12 9000
```

### 3. GPG Signature Verification Fails

#### Symptoms
- "Invalid signature" error
- Transactions rejected

#### Solutions

**Check imported keys:**
```bash
docker exec -it bashcoin-node1 gpg --list-keys
```

**Reimport keys:**
```bash
docker exec -it bashcoin-node1 /scripts/init-node.sh
```

**Verify key exchange:**
```bash
# Check if other nodes' keys are present
docker exec -it bashcoin-node1 ls -la /data/keys/
```

**Manual key import:**
```bash
docker exec -it bashcoin-node1 bash
gpg --import /data/keys/node2_public.key
```

### 4. Insufficient Balance Error

#### Symptoms
- Transaction rejected with "Insufficient balance"
- Balance seems wrong

#### Solutions

**Recalculate balances:**
```bash
docker exec -it bashcoin-node1 /scripts/consensus.sh calculate
docker exec -it bashcoin-node1 /scripts/consensus.sh balance
```

**Check ledger integrity:**
```bash
docker exec -it bashcoin-node1 cat /data/ledger/transactions.jsonl | jq .
```

**Look for duplicate transactions:**
```bash
docker exec -it bashcoin-node1 bash -c "cat /data/ledger/transactions.jsonl | jq -r .nonce | sort | uniq -d"
```

**Sync with other nodes:**
```bash
docker exec -it bashcoin-node1 /scripts/sync-ledger.sh
```

### 5. NTP Time Synchronization Issues

#### Symptoms
- Timestamp errors
- "Time sync failed" messages

#### Solutions

**Check NTP server:**
```bash
docker-compose logs ntp-server
docker exec -it bashcoin-ntp ps aux | grep ntpd
```

**Restart NTP server:**
```bash
docker-compose restart ntp-server
```

**Manual time sync on nodes:**
```bash
docker exec -it bashcoin-node1 ntpd -s
```

**Verify time sync:**
```bash
# Check time on all nodes
docker exec bashcoin-node1 date
docker exec bashcoin-node2 date
docker exec bashcoin-node3 date
```

### 6. Rsync Connection Failures

#### Symptoms
- "Connection refused" during sync
- Sync fails silently

#### Solutions

**Check rsync daemon:**
```bash
docker exec -it bashcoin-node1 ps aux | grep rsync
```

**Test rsync manually:**
```bash
docker exec -it bashcoin-node1 rsync rsync://172.25.0.12:873/
```

**Check rsync configuration:**
```bash
docker exec -it bashcoin-node1 cat /etc/rsyncd.conf
```

**Restart rsync daemon:**
```bash
docker-compose restart node1
```

### 7. High Memory/CPU Usage

#### Symptoms
- Containers using too much resources
- System becomes slow

#### Solutions

**Check resource usage:**
```bash
docker stats
```

**Limit container resources (edit docker-compose.yml):**
```yaml
services:
  node1:
    # ... existing config ...
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
```

**Clean up old data:**
```bash
docker exec -it bashcoin-node1 bash -c "wc -l /data/ledger/transactions.jsonl"
# If very large, consider archiving
```

### 8. Ledger Corruption

#### Symptoms
- Hash mismatches
- Invalid JSON in ledger
- Consensus errors

#### Solutions

**Validate ledger:**
```bash
docker exec -it bashcoin-node1 bash -c "cat /data/ledger/transactions.jsonl | jq empty"
```

**Find corrupted entries:**
```bash
docker exec -it bashcoin-node1 bash -c "while IFS= read -r line; do echo \$line | jq empty || echo 'Invalid JSON: '\$line; done < /data/ledger/transactions.jsonl"
```

**Restore from other node:**
```bash
# Backup current ledger
docker exec -it bashcoin-node1 cp /data/ledger/transactions.jsonl /data/ledger/transactions.jsonl.backup

# Sync from healthy node
docker exec -it bashcoin-node1 /scripts/sync-ledger.sh
```

**Nuclear option - rebuild ledger:**
```bash
docker exec -it bashcoin-node1 bash
rm /data/ledger/transactions.jsonl
/scripts/init-node.sh
/scripts/sync-ledger.sh
```

### 9. Network Partition

#### Symptoms
- Some nodes can't communicate
- Split brain scenario

#### Solutions

**Check Docker network:**
```bash
docker network inspect bashcoin_bashcoin-network
```

**Test connectivity between nodes:**
```bash
docker exec -it bashcoin-node1 ping 172.25.0.12
docker exec -it bashcoin-node1 ping 172.25.0.13
```

**Recreate network:**
```bash
make down
docker network rm bashcoin_bashcoin-network
make up
```

### 10. Permission Denied Errors

#### Symptoms
- Can't write to files
- Script execution fails

#### Solutions

**Check file permissions:**
```bash
docker exec -it bashcoin-node1 ls -la /scripts/
docker exec -it bashcoin-node1 ls -la /data/
```

**Fix script permissions:**
```bash
docker exec -it bashcoin-node1 chmod +x /scripts/*.sh
```

**Check volume permissions:**
```bash
docker-compose down -v
make up
```

## Debugging Tools

### View Real-time Logs

```bash
# All containers
docker-compose logs -f

# Specific container
docker-compose logs -f node1

# Last 50 lines
docker-compose logs --tail=50 node1
```

### Interactive Shell

```bash
# Open shell in any node
make shell-node1
make shell-node2

# Or manually
docker exec -it bashcoin-node1 bash
```

### Inspect Network

```bash
# List all networks
docker network ls

# Inspect BashCoin network
docker network inspect bashcoin_bashcoin-network

# Test connectivity
docker exec -it bashcoin-node1 ping 172.25.0.12
docker exec -it bashcoin-node1 nc -zv 172.25.0.12 9000
```

### Monitor Processes

```bash
# List processes in container
docker exec -it bashcoin-node1 ps aux

# Check specific process
docker exec -it bashcoin-node1 ps aux | grep ledger-daemon
```

### Inspect Volumes

```bash
# List volumes
docker volume ls

# Inspect volume
docker volume inspect bashcoin_node1-data

# Access volume data (Linux/Mac)
docker run --rm -v bashcoin_node1-data:/data alpine ls -la /data
```

### Network Debugging

```bash
# Check listening ports
docker exec -it bashcoin-node1 netstat -tuln

# Check established connections
docker exec -it bashcoin-node1 netstat -tupn

# Capture network traffic (requires tcpdump)
docker exec -it bashcoin-node1 tcpdump -i any port 9000
```

## Performance Issues

### Slow Transaction Processing

**Check:**
1. Number of transactions in ledger
2. Available system resources
3. Network latency between nodes

**Solutions:**
```bash
# Check transaction count
docker exec -it bashcoin-node1 wc -l /data/ledger/transactions.jsonl

# Monitor resource usage
docker stats

# Archive old transactions (manual process)
# Keep only recent transactions in active ledger
```

### Slow Synchronization

**Check:**
1. Ledger size
2. Network bandwidth
3. Rsync efficiency

**Solutions:**
```bash
# Check ledger size
docker exec -it bashcoin-node1 du -sh /data/ledger/

# Test network speed between nodes
docker exec -it bashcoin-node1 time rsync -az rsync://172.25.0.12:873/ledger/transactions.jsonl /tmp/test.jsonl
```

## Preventive Measures

### Regular Maintenance

```bash
# Daily: Check balances
make balance

# Weekly: Verify ledger integrity
docker exec -it bashcoin-node1 cat /data/ledger/transactions.jsonl | jq empty

# Monthly: Archive old data (if needed)
# Backup ledger before cleaning
```

### Monitoring

Set up basic monitoring:

```bash
# Create monitoring script
cat > monitor.sh << 'EOF'
#!/bin/bash
while true; do
    echo "=== $(date) ==="
    docker-compose ps
    docker stats --no-stream
    echo ""
    sleep 300  # Every 5 minutes
done
EOF

chmod +x monitor.sh
./monitor.sh > monitor.log &
```

### Backups

```bash
# Backup all ledgers
for node in node1 node2 node3 node4 node5; do
    docker exec bashcoin-${node} cat /data/ledger/transactions.jsonl > backup_${node}_$(date +%Y%m%d).jsonl
done

# Backup Docker volumes
docker run --rm -v bashcoin_node1-data:/data -v $(pwd):/backup alpine tar czf /backup/node1-backup.tar.gz /data
```

## Getting Help

If you're still stuck:

1. **Check logs**: `make logs` for detailed error messages
2. **Search issues**: Look for similar problems in GitHub issues
3. **Create issue**: Provide detailed information:
   - Docker version: `docker --version`
   - OS and version
   - Steps to reproduce
   - Relevant logs
   - What you've tried

## Reset Everything

When all else fails:

```bash
# Nuclear option: Complete reset
make clean
docker system prune -a
docker volume prune
make build
make up
```

This will delete all data and start fresh!

## Additional Resources

- [README.md](README.md) - Full documentation
- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture
- [QUICKSTART.md](QUICKSTART.md) - Getting started guide
- Docker documentation: https://docs.docker.com/
- Alpine Linux docs: https://alpinelinux.org/

---

**Remember**: This is a learning/demo project. If you encounter issues, it's a great opportunity to understand the system better by debugging!

