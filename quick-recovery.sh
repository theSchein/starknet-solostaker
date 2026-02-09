#!/bin/bash

# Quick Recovery Script for Validator
# Run this on the VALIDATOR machine, not workstation

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}           Starknet Validator Quick Recovery${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Check current situation
log "Checking current Juno status..."

if [ -f "data/juno/juno_mainnet.tar" ]; then
    SIZE=$(du -h data/juno/juno_mainnet.tar | cut -f1)
    warn "Found partial snapshot download: $SIZE"
    PARTIAL_EXISTS=true
else
    info "No partial download found"
    PARTIAL_EXISTS=false
fi

if [ -f "data/juno/CURRENT" ]; then
    warn "Found existing Juno database"
    DB_EXISTS=true
else
    info "No existing database"
    DB_EXISTS=false
fi

# Check if containers are running
if docker compose ps | grep -q "starknet-juno.*running"; then
    warn "Juno is currently running"
    JUNO_RUNNING=true
else
    info "Juno is not running"
    JUNO_RUNNING=false
fi

echo
echo "Choose recovery option:"
echo
echo "1) Clean recovery - Delete everything and start fresh (recommended)"
echo "2) Resume download - Continue partial download if exists"
echo "3) Force update - Use maintenance script force-update"
echo "4) Check status only - See current validator status"
echo "5) Exit"
echo

read -p "Enter choice (1-5): " choice

case $choice in
    1)
        log "Starting clean recovery..."
        warn "This will delete all Juno data and download fresh snapshot"
        read -p "Continue? (y/n): " confirm
        if [ "$confirm" != "y" ]; then
            exit 0
        fi

        log "Stopping services..."
        docker compose down

        log "Cleaning old data..."
        rm -rf data/juno/*

        log "Starting snapshot download in screen..."
        info "Run this in screen for stability:"
        echo
        echo -e "${YELLOW}screen -S snapshot${NC}"
        echo -e "${YELLOW}./manual-snapshot-download.sh${NC}"
        echo
        info "After download completes, run:"
        echo -e "${YELLOW}docker compose up -d${NC}"
        ;;

    2)
        if [ "$PARTIAL_EXISTS" = "true" ]; then
            log "Resuming partial download..."
            ./resume-snapshot.sh

            if [ $? -eq 0 ]; then
                log "Download completed! Restarting services..."
                docker compose restart
            else
                error "Resume failed. Try clean recovery (option 1)"
            fi
        else
            warn "No partial download to resume"
            info "Use option 1 for clean recovery"
        fi
        ;;

    3)
        log "Running force update..."
        ./maintenance.sh force-update
        ;;

    4)
        log "Checking validator status..."
        echo

        # Check Juno sync
        info "Juno sync status:"
        curl -s http://localhost:6060 -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"starknet_blockNumber","params":[],"id":1}' 2>/dev/null || echo "  Juno not responding"

        echo
        info "Container status:"
        docker compose ps

        echo
        info "Disk usage:"
        df -h data/ 2>/dev/null || df -h .

        if [ -d "data/juno" ]; then
            echo
            info "Juno data size:"
            du -sh data/juno/
        fi
        ;;

    5)
        info "Exiting..."
        exit 0
        ;;

    *)
        error "Invalid choice"
        exit 1
        ;;
esac

echo
log "Recovery action completed"
info "Monitor logs with: docker logs -f starknet-juno"
info "Check status with: ./maintenance.sh status"