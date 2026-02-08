#!/bin/bash

# Recovery script for failed snapshot downloads
# Use this when reset-juno.sh fails with download errors

set -uo pipefail

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

# Load environment
if [[ -f .env ]]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

JUNO_DATA="${JUNO_DATA_DIR:-/media/dov/ethdata}/juno"

log "Snapshot Download Recovery Process"
warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "This script will help recover from the download failure"
warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Step 1: Stop any running download containers
log "Stopping any running download attempts..."
docker compose stop juno-snapshot 2>/dev/null || true
docker compose rm -f juno-snapshot 2>/dev/null || true

# Step 2: Check current situation
log "Checking current download status..."

if [ -f "$JUNO_DATA/juno_mainnet.tar" ]; then
    CURRENT_SIZE=$(du -h "$JUNO_DATA/juno_mainnet.tar" | cut -f1)
    info "Found partial download: $CURRENT_SIZE"

    echo
    echo "Options:"
    echo "1) Resume download from where it stopped (recommended)"
    echo "2) Delete and start fresh download"
    echo "3) Try to extract what we have (risky if incomplete)"
    echo
    read -p "Choose option (1-3): " choice

    case $choice in
        1)
            log "Resuming download..."
            ./download-snapshot.sh
            ;;
        2)
            warn "Deleting partial download and starting fresh..."
            rm -f "$JUNO_DATA/juno_mainnet.tar"
            ./download-snapshot.sh
            ;;
        3)
            warn "Attempting extraction of partial file..."
            tar -xf "$JUNO_DATA/juno_mainnet.tar" -C "$JUNO_DATA" 2>&1 | tail -20
            if [ -f "$JUNO_DATA/CURRENT" ]; then
                info "Extraction succeeded, but data may be incomplete"
            else
                error "Extraction failed - file is too incomplete"
                exit 1
            fi
            ;;
        *)
            error "Invalid choice"
            exit 1
            ;;
    esac
else
    info "No partial download found, starting fresh..."
    ./download-snapshot.sh
fi

# Step 3: If download succeeded, start services
if [ -f "$JUNO_DATA/.snapshot_downloaded" ] || [ -f "$JUNO_DATA/CURRENT" ]; then
    log "Snapshot ready, starting services..."

    # Start Juno
    docker compose up -d juno

    # Wait a bit for Juno to initialize
    sleep 10

    # Start validator
    docker compose up -d starknet-validator

    # Start monitoring
    docker compose up -d prometheus grafana

    log "Services started!"
    info "Monitor progress with: docker logs -f starknet-juno"
else
    error "Snapshot not ready. Please run ./download-snapshot.sh manually"
    exit 1
fi