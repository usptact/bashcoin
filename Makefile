# BashCoin Makefile
# Convenient commands for managing the BashCoin distributed ledger

.PHONY: help build up down logs clean restart status transaction balance sync stats

# Default target
help:
	@echo "BashCoin - Distributed Ledger System"
	@echo ""
	@echo "Available commands:"
	@echo "  make build       - Build all Docker images"
	@echo "  make up          - Start all containers"
	@echo "  make down        - Stop all containers"
	@echo "  make restart     - Restart all containers"
	@echo "  make logs        - Show logs from all containers"
	@echo "  make status      - Show container status"
	@echo "  make clean       - Stop and remove all containers and volumes"
	@echo "  make transaction - Send a test transaction (node1 -> node2, 50 coins)"
	@echo "  make balance     - Show balance for node1"
	@echo "  make sync        - Synchronize ledger on node1"
	@echo "  make stats       - Show statistics for node1"
	@echo "  make shell-node1 - Open shell in node1"
	@echo "  make shell-node2 - Open shell in node2"
	@echo "  make rebuild     - Rebuild everything from scratch"
	@echo "  make join-demo   - Start node6 as a runtime joiner and fund it"
	@echo ""

# Build Docker images
build:
	docker-compose build

# Start all containers
up:
	docker-compose up -d
	@echo "Waiting for nodes to initialize..."
	@sleep 15
	@echo "BashCoin is ready!"
	@echo "Try: make transaction"

# Stop all containers
down:
	docker-compose down

# Show logs
logs:
	docker-compose logs -f

# Show logs for specific node
logs-node1:
	docker-compose logs -f node1

logs-node2:
	docker-compose logs -f node2

logs-ntp:
	docker-compose logs -f ntp-server

# Show container status
status:
	docker-compose ps

# Clean everything (including volumes)
clean:
	docker-compose down -v
	@echo "All containers and volumes removed"

# Restart all containers
restart: down up

# Rebuild from scratch
rebuild: clean
	docker-compose build --no-cache
	docker-compose up -d
	@echo "Waiting for nodes to initialize..."
	@sleep 15
	@echo "BashCoin rebuilt and ready!"

# Send a test transaction
transaction:
	@echo "Sending 50 coins from node1 to node2..."
	docker exec -it bashcoin-node1 /scripts/create-transaction.sh node2 50

# Show balance
balance:
	@echo "Checking balance on node1..."
	docker exec -it bashcoin-node1 /scripts/consensus.sh balance

# Synchronize ledger
sync:
	@echo "Synchronizing ledger on node1..."
	docker exec -it bashcoin-node1 /scripts/sync-ledger.sh

# Show statistics
stats:
	@echo "Statistics for node1:"
	docker exec -it bashcoin-node1 /scripts/consensus.sh stats

# Open shell in node1
shell-node1:
	docker exec -it bashcoin-node1 bash

# Open shell in node2
shell-node2:
	docker exec -it bashcoin-node2 bash

# Open shell in node3
shell-node3:
	docker exec -it bashcoin-node3 bash

# Open shell in node4
shell-node4:
	docker exec -it bashcoin-node4 bash

# Open shell in node5
shell-node5:
	docker exec -it bashcoin-node5 bash

# View ledger
ledger:
	@echo "Ledger contents (node1):"
	docker exec -it bashcoin-node1 sh -c "cat /data/ledger/transactions.jsonl | jq ."

# Test scenario: Multiple transactions
test-multi:
	@echo "Running multiple transaction test..."
	docker exec -it bashcoin-node1 /scripts/create-transaction.sh node2 10
	@sleep 2
	docker exec -it bashcoin-node1 /scripts/create-transaction.sh node3 20
	@sleep 2
	docker exec -it bashcoin-node1 /scripts/create-transaction.sh node4 30
	@sleep 2
	@echo "Checking balances..."
	docker exec -it bashcoin-node1 /scripts/consensus.sh balance

# Test scenario: Node failure and recovery
test-failure:
	@echo "Testing node failure and recovery..."
	@echo "1. Stopping node3..."
	docker-compose stop node3
	@sleep 2
	@echo "2. Sending transaction while node3 is down..."
	docker exec -it bashcoin-node1 /scripts/create-transaction.sh node2 25
	@sleep 2
	@echo "3. Restarting node3..."
	docker-compose start node3
	@sleep 10
	@echo "4. Syncing node3..."
	docker exec -it bashcoin-node3 /scripts/sync-ledger.sh
	@echo "5. Checking balance on node3..."
	docker exec -it bashcoin-node3 /scripts/consensus.sh balance

# Runtime join demo: start node6 (a non-seed joiner) and show it being discovered
join-demo:
	@echo "Starting node6 as a runtime joiner (not a seed)..."
	docker-compose --profile join-demo up -d --build node6
	@echo "Waiting for node6 to announce and the network to discover it..."
	@sleep 15
	@echo ""
	@echo "Membership as seen by node1 (should include node6):"
	docker exec bashcoin-node1 /scripts/consensus.sh stats
	@echo ""
	@echo "Funding node6 with 100 coins from node1..."
	docker exec bashcoin-node1 /scripts/create-transaction.sh node6 100
	@sleep 3
	@echo ""
	@echo "node6 balance (expect 100):"
	docker exec bashcoin-node6 /scripts/consensus.sh balance

# Quick demo
demo:
	@echo "==================================="
	@echo "BashCoin Demo"
	@echo "==================================="
	@echo ""
	@echo "1. Initial balances:"
	@make balance
	@echo ""
	@echo "2. Sending 100 coins from node1 to node2..."
	docker exec bashcoin-node1 /scripts/create-transaction.sh node2 100
	@sleep 3
	@echo ""
	@echo "3. New balances:"
	@make balance
	@echo ""
	@echo "4. Verifying on node2..."
	docker exec bashcoin-node2 /scripts/consensus.sh balance
	@echo ""
	@echo "Demo complete!"

