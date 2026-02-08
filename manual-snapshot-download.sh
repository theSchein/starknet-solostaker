#!/bin/bash

# Manual Juno Snapshot Download
# Run this with screen or tmux for stability on poor connections
# Usage: screen -S snapshot ./manual-snapshot-download.sh

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

# Configuration
JUNO_DIR="./data/juno"
SNAPSHOT_URL="https://juno-snapshots.nethermind.io/files/mainnet/latest"
SNAPSHOT_FILE="$JUNO_DIR/juno_mainnet.tar"

log "Manual Juno Snapshot Download"
warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Run this in screen/tmux for stability:"
info "  screen -S snapshot $0"
info "  OR"
info "  tmux new-session -s snapshot $0"
warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Check if running in screen or tmux
if [ -z "${STY:-}" ] && [ -z "${TMUX:-}" ]; then
    warn "Not running in screen or tmux!"
    warn "Connection loss will interrupt download"
    echo
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Create directory
mkdir -p "$JUNO_DIR"

# Check for existing download
if [ -f "$SNAPSHOT_FILE" ]; then
    SIZE=$(du -h "$SNAPSHOT_FILE" | cut -f1)
    log "Found existing partial download: $SIZE"
else
    log "Starting fresh download"
fi

# Download with wget (more robust than curl for large files)
log "Downloading snapshot (approximately 200GB)..."
info "Using wget for maximum stability"
echo

if command -v wget &> /dev/null; then
    # Wget with resume and retries
    wget -c \
         --tries=0 \
         --retry-connrefused \
         --timeout=30 \
         --read-timeout=300 \
         --progress=bar:force \
         -O "$SNAPSHOT_FILE" \
         "$SNAPSHOT_URL"

    RESULT=$?
else
    # Fallback to curl if wget not available
    warn "wget not found, using curl (less robust)"

    # Infinite retry loop for curl
    while true; do
        curl -L -C - \
             --connect-timeout 30 \
             --max-time 0 \
             --retry 999 \
             --retry-delay 30 \
             --retry-max-time 0 \
             --progress-bar \
             -o "$SNAPSHOT_FILE" \
             "$SNAPSHOT_URL"

        RESULT=$?

        if [ $RESULT -eq 0 ]; then
            break
        else
            warn "Download interrupted, resuming in 30 seconds..."
            sleep 30
        fi
    done
fi

if [ $RESULT -eq 0 ]; then
    log "Download completed!"
    SIZE=$(du -h "$SNAPSHOT_FILE" | cut -f1)
    info "Final size: $SIZE"

    # Verify tar file
    log "Verifying tar file integrity..."
    if tar -tf "$SNAPSHOT_FILE" > /dev/null 2>&1; then
        log "Verification successful!"

        # Extract
        log "Extracting snapshot..."
        info "This will take 10-20 minutes"

        # Clean old data
        rm -f "$JUNO_DIR"/*.sst "$JUNO_DIR"/CURRENT "$JUNO_DIR"/LOCK "$JUNO_DIR"/LOG* "$JUNO_DIR"/MANIFEST* "$JUNO_DIR"/OPTIONS*

        # Extract with progress
        pv "$SNAPSHOT_FILE" 2>/dev/null | tar -xf - -C "$JUNO_DIR" || tar -xvf "$SNAPSHOT_FILE" -C "$JUNO_DIR"

        if [ -f "$JUNO_DIR/CURRENT" ]; then
            log "Extraction complete!"

            # Clean up tar
            rm "$SNAPSHOT_FILE"
            touch "$JUNO_DIR/.snapshot_downloaded"

            echo
            log "✅ SUCCESS! Snapshot is ready"
            info "You can now start services:"
            info "  docker compose up -d"
            echo

            # If in screen/tmux, give time to see result
            if [ -n "${STY:-}" ] || [ -n "${TMUX:-}" ]; then
                info "Press any key to exit..."
                read -n 1
            fi
        else
            error "Extraction failed - no database files"
            exit 1
        fi
    else
        error "Downloaded file is corrupted!"
        error "Delete and retry: rm $SNAPSHOT_FILE"
        exit 1
    fi
else
    error "Download failed after all retries"
    exit 1
fi