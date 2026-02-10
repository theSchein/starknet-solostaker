#!/bin/bash

# Resume partial Juno snapshot download
# Use this when docker-compose download fails

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

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Correct location for Juno data (local, not external SSD)
JUNO_DIR="./data/juno"
SNAPSHOT_FILE="$JUNO_DIR/juno_mainnet.tar.zst"
SNAPSHOT_TAR="$JUNO_DIR/juno_mainnet.tar"
# Using mainnet-newdb for compressed database format compatibility
SNAPSHOT_URL="https://juno-snapshots.nethermind.io/files/mainnet-newdb/latest"

log "Resuming Juno snapshot download"
echo

# Check current status
if [ -f "$SNAPSHOT_FILE" ]; then
    CURRENT_SIZE=$(du -h "$SNAPSHOT_FILE" | cut -f1)
    info "Found partial download: $CURRENT_SIZE"
    info "Location: $SNAPSHOT_FILE"
    echo
else
    error "No partial download found at $SNAPSHOT_FILE"
    info "Starting fresh download..."
fi

# Create directory if needed
mkdir -p "$JUNO_DIR"

# Check for zstd
if ! command -v zstd &> /dev/null; then
    info "zstd not found, installing..."
    sudo apt-get update && sudo apt-get install -y zstd
fi

# Resume download with better retry logic
log "Resuming download (this will continue from $CURRENT_SIZE)..."
info "This may take 30-60 minutes for the full ~334GB (compressed)"
echo

# Try download with retries
MAX_ATTEMPTS=10
ATTEMPT=1
SUCCESS=false

while [ $ATTEMPT -le $MAX_ATTEMPTS ] && [ "$SUCCESS" = "false" ]; do
    if [ $ATTEMPT -gt 1 ]; then
        info "Retry attempt $ATTEMPT of $MAX_ATTEMPTS..."
    fi

    # Use curl with resume capability
    if curl -L -C - \
         --connect-timeout 30 \
         --max-time 7200 \
         --retry 3 \
         --retry-delay 10 \
         --progress-bar \
         -o "$SNAPSHOT_FILE" \
         "$SNAPSHOT_URL"; then
        SUCCESS=true
    else
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 18 ] || [ $EXIT_CODE -eq 56 ]; then
            # Partial download or connection reset - can resume
            warn "Download interrupted (exit code $EXIT_CODE), will retry..."
            sleep 30
        else
            error "Download failed with exit code $EXIT_CODE"
            break
        fi
    fi
    ATTEMPT=$((ATTEMPT + 1))
done

if [ "$SUCCESS" = "true" ]; then
    log "Download completed successfully!"

    FINAL_SIZE=$(du -h "$SNAPSHOT_FILE" | cut -f1)
    info "Final size: $FINAL_SIZE"

    # Check disk space
    AVAILABLE_SPACE=$(df "$JUNO_DIR" | tail -1 | awk '{print $4}')
    log "Available disk space: $((AVAILABLE_SPACE / 1024 / 1024))GB"

    # Verify file size
    FILE_SIZE=$(stat -c%s "$SNAPSHOT_FILE" 2>/dev/null || stat -f%z "$SNAPSHOT_FILE" 2>/dev/null || echo 0)
    log "Downloaded file size: $((FILE_SIZE / 1024 / 1024 / 1024))GB"

    if [ "$FILE_SIZE" -lt 1000000000 ]; then
        error "Downloaded file too small, likely incomplete"
        exit 1
    fi

    # Stream decompress and extract to save disk space
    log "Decompressing and extracting snapshot..."
    info "Streaming extraction to save disk space (15-30 minutes)"

    # Clean old data first
    rm -f "$JUNO_DIR"/*.sst "$JUNO_DIR"/CURRENT "$JUNO_DIR"/LOCK "$JUNO_DIR"/LOG* "$JUNO_DIR"/MANIFEST* "$JUNO_DIR"/OPTIONS*

    cd "$JUNO_DIR"
    if zstd -dc "$SNAPSHOT_FILE" | tar -xf - ; then
        log "Extraction successful!"

        if [ -f "CURRENT" ]; then
            log "Extraction successful!"
            rm "$SNAPSHOT_FILE"
            touch .snapshot_downloaded

            echo
            log "✅ Snapshot ready! You can now start services:"
            info "Run: docker compose up -d"
        else
            error "Extraction failed - no database files found"
        fi
    else
        error "Downloaded file is corrupted!"
        error "You may need to delete and restart: rm $SNAPSHOT_FILE"
    fi
else
    error "Download failed!"
    error "The download will resume from where it stopped next time you run this script"
fi