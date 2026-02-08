#!/bin/bash

# Starknet Validator Juno Reset Script
# Forces a fresh Juno snapshot download and restarts the validator

set -euo pipefail

# Colors for output
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

# Load environment variables
if [[ -f .env ]]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Check if running on validator machine
if [[ ! -d "${JUNO_DATA_DIR:-./data}/juno" ]]; then
    error "Juno data directory not found at ${JUNO_DATA_DIR:-./data}/juno"
    error "Make sure you're running this on the validator machine with correct environment"
    exit 1
fi

warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
warn "⚠️  JUNO RESET AND FRESH SNAPSHOT DOWNLOAD"
warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
warn ""
warn "This script will:"
warn "  1. Stop all validator services"
warn "  2. Backup current Juno data (optional)"
warn "  3. Delete existing Juno database"
warn "  4. Force download of fresh snapshot (30-60 minutes)"
warn "  5. Restart all services"
warn ""
warn "Your validator will be OFFLINE during this process!"
warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Confirm action
read -p "Do you want to proceed? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    log "Reset cancelled by user"
    exit 0
fi

# Optional backup
read -p "Do you want to backup current Juno data first? (yes/no): " -r
if [[ $REPLY =~ ^[Yy]es$ ]]; then
    log "Creating backup of current Juno data..."
    BACKUP_DIR="backups/juno_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    info "Backing up to $BACKUP_DIR (this may take a while)..."
    cp -r "${JUNO_DATA_DIR:-./data}/juno" "$BACKUP_DIR/" || {
        warn "Backup failed, but continuing with reset"
    }
fi

# Step 1: Stop all services
log "Stopping all validator services..."
docker compose down

# Step 2: Check current Juno data size
if [[ -d "${JUNO_DATA_DIR:-./data}/juno" ]]; then
    CURRENT_SIZE=$(du -sh "${JUNO_DATA_DIR:-./data}/juno" | cut -f1)
    info "Current Juno data size: $CURRENT_SIZE"
fi

# Step 3: Remove old Juno data
log "Removing old Juno database..."
rm -rf "${JUNO_DATA_DIR:-./data}/juno"/*
rm -f "${JUNO_DATA_DIR:-./data}/juno"/.snapshot_downloaded

# Step 4: Create fresh directory
mkdir -p "${JUNO_DATA_DIR:-./data}/juno"

# Step 5: Force fresh snapshot download
log "Starting services with forced snapshot download..."
info "This will download approximately 200GB of data and may take 30-60 minutes"

# Export force snapshot flag
export FORCE_SNAPSHOT=true

# Start services
docker compose up -d juno-snapshot

# Monitor snapshot download
log "Monitoring snapshot download progress..."
while true; do
    if docker logs starknet-juno-snapshot 2>&1 | grep -q "Snapshot downloaded and extracted successfully"; then
        log "Snapshot download completed successfully!"
        break
    elif docker logs starknet-juno-snapshot 2>&1 | grep -q "ERROR"; then
        error "Snapshot download failed! Check logs with: docker logs starknet-juno-snapshot"
        exit 1
    elif docker logs starknet-juno-snapshot 2>&1 | grep -q "Using existing snapshot"; then
        warn "Snapshot service detected existing data (this shouldn't happen after cleanup)"
        break
    fi

    # Show download progress
    if [[ -f "${JUNO_DATA_DIR:-./data}/juno/juno_mainnet.tar" ]]; then
        TAR_SIZE=$(du -sh "${JUNO_DATA_DIR:-./data}/juno/juno_mainnet.tar" 2>/dev/null | cut -f1 || echo "0")
        echo -ne "\rDownload progress: $TAR_SIZE downloaded..."
    fi

    sleep 10
done

echo  # New line after progress indicator

# Step 6: Start all services
log "Starting all validator services..."
docker compose up -d

# Wait for services to stabilize
sleep 30

# Step 7: Check service status
log "Checking service status..."
docker compose ps

# Step 8: Check Juno sync status
info "Checking Juno sync status..."
JUNO_BLOCK=$(curl -s http://localhost:6060 -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"starknet_blockNumber","params":[],"id":1}' 2>/dev/null \
    | grep -o '"result":"[^"]*"' | cut -d'"' -f4 || echo "")

if [[ -n "$JUNO_BLOCK" ]]; then
    log "Juno is syncing! Current block: $JUNO_BLOCK"
else
    warn "Could not get Juno block number. It may still be starting up."
    warn "Check logs with: docker logs starknet-juno"
fi

# Step 9: Check validator status
info "Checking validator status..."
if curl -s http://localhost:8081/metrics >/dev/null 2>&1; then
    log "Validator metrics endpoint is accessible"
else
    warn "Validator metrics endpoint not responding yet"
    warn "Check logs with: docker logs starknet-validator"
fi

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Reset completed successfully!"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info ""
info "Next steps:"
info "  1. Monitor sync progress: watch 'docker logs --tail=50 starknet-juno'"
info "  2. Check validator logs: docker logs starknet-validator"
info "  3. Monitor metrics: http://localhost:3001 (Grafana)"
info ""
info "The validator will start attesting once Juno is fully synced."
info "This may take several hours depending on how far behind the chain is."