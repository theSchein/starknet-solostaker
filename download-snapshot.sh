#!/bin/bash

# Robust Juno Snapshot Download Script
# Handles interruptions, retries, and alternative download methods

set -uo pipefail  # Don't use -e to allow retries

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

# Load environment
if [[ -f .env ]]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Configuration
JUNO_DATA="${JUNO_DATA_DIR:-/media/dov/ethdata}/juno"
SNAPSHOT_URL="https://juno-snapshots.nethermind.io/files/mainnet/latest"
MAX_RETRIES=10
RETRY_DELAY=30

# Ensure data directory exists
mkdir -p "$JUNO_DATA"

log "Starting robust snapshot download process"

# Method 1: Direct curl with resume capability
download_with_curl() {
    local url=$1
    local output=$2
    local attempt=1

    while [ $attempt -le $MAX_RETRIES ]; do
        log "Download attempt $attempt of $MAX_RETRIES"

        # Show current file size if it exists
        if [ -f "$output" ]; then
            local current_size=$(du -h "$output" | cut -f1)
            info "Resuming download, current size: $current_size"
        fi

        # Curl with resume, timeout, and retry options
        if curl -L \
                -C - \
                --connect-timeout 30 \
                --max-time 7200 \
                --retry 3 \
                --retry-delay 10 \
                --progress-bar \
                -o "$output" \
                "$url"; then
            log "Download completed successfully!"
            return 0
        else
            local exit_code=$?
            error "Download failed with exit code $exit_code"

            # Check if partial download exists
            if [ -f "$output" ]; then
                local size=$(du -h "$output" | cut -f1)
                info "Partial download exists: $size"
            fi

            if [ $attempt -lt $MAX_RETRIES ]; then
                warn "Retrying in $RETRY_DELAY seconds..."
                sleep $RETRY_DELAY
            fi
        fi

        attempt=$((attempt + 1))
    done

    return 1
}

# Method 2: Using wget as alternative
download_with_wget() {
    local url=$1
    local output=$2

    log "Attempting download with wget..."

    wget -c \
         --timeout=30 \
         --tries=5 \
         --retry-connrefused \
         --progress=bar \
         -O "$output" \
         "$url"
}

# Method 3: Using aria2c for robust parallel downloading
download_with_aria2() {
    local url=$1
    local output=$2

    # Check if aria2c is available
    if ! command -v aria2c &> /dev/null; then
        warn "aria2c not found, install with: apt-get install aria2"
        return 1
    fi

    log "Attempting download with aria2c (parallel connections)..."

    aria2c -x 4 \
           -s 4 \
           -c \
           --file-allocation=none \
           --log-level=warn \
           --max-tries=10 \
           --retry-wait=30 \
           --timeout=30 \
           --max-file-not-found=5 \
           --max-connection-per-server=4 \
           -d "$(dirname "$output")" \
           -o "$(basename "$output")" \
           "$url"
}

# Main download logic
SNAPSHOT_FILE="$JUNO_DATA/juno_mainnet.tar"

log "Downloading Juno snapshot to: $SNAPSHOT_FILE"
info "This is approximately 200GB and may take 30-120 minutes"

# Try primary method (curl)
if download_with_curl "$SNAPSHOT_URL" "$SNAPSHOT_FILE"; then
    log "Download successful with curl"
elif command -v wget &> /dev/null && download_with_wget "$SNAPSHOT_URL" "$SNAPSHOT_FILE"; then
    log "Download successful with wget"
elif download_with_aria2 "$SNAPSHOT_URL" "$SNAPSHOT_FILE"; then
    log "Download successful with aria2c"
else
    error "All download methods failed!"
    error "Troubleshooting steps:"
    error "1. Check internet connection: ping -c 3 juno-snapshots.nethermind.io"
    error "2. Check disk space: df -h $JUNO_DATA"
    error "3. Try manual download: wget -c $SNAPSHOT_URL -O $SNAPSHOT_FILE"
    error "4. Install aria2 for better reliability: sudo apt-get install aria2"
    exit 1
fi

# Verify download
log "Verifying downloaded file..."

if [ ! -f "$SNAPSHOT_FILE" ]; then
    error "Download file not found!"
    exit 1
fi

FILE_SIZE=$(du -h "$SNAPSHOT_FILE" | cut -f1)
log "Downloaded file size: $FILE_SIZE"

# Check if it's a valid tar file
info "Checking tar file integrity..."
if tar -tf "$SNAPSHOT_FILE" > /dev/null 2>&1; then
    log "Tar file verification passed!"
else
    error "Downloaded file is corrupted or incomplete!"
    error "The file may be partially downloaded. You can try running this script again to resume."
    exit 1
fi

# Extract the snapshot
log "Extracting snapshot..."
info "This may take 10-20 minutes..."

# Clean old database files first
rm -f "$JUNO_DATA"/*.sst "$JUNO_DATA"/CURRENT "$JUNO_DATA"/LOCK "$JUNO_DATA"/LOG* "$JUNO_DATA"/MANIFEST* "$JUNO_DATA"/OPTIONS*

# Extract with progress
if command -v pv &> /dev/null; then
    pv "$SNAPSHOT_FILE" | tar -xf - -C "$JUNO_DATA"
else
    tar -xvf "$SNAPSHOT_FILE" -C "$JUNO_DATA" | \
    while read line; do
        printf "\rExtracting files... %s" "$line"
    done
    echo
fi

# Verify extraction
if [ -f "$JUNO_DATA/CURRENT" ]; then
    SST_COUNT=$(ls "$JUNO_DATA"/*.sst 2>/dev/null | wc -l)
    if [ $SST_COUNT -gt 100 ]; then
        log "Extraction successful! Found $SST_COUNT database files"

        # Clean up tar file
        log "Removing temporary download file..."
        rm -f "$SNAPSHOT_FILE"

        # Mark as downloaded
        touch "$JUNO_DATA/.snapshot_downloaded"

        log "✅ Snapshot ready! You can now start Juno."
        info "Run: docker compose up -d juno"
    else
        error "Extraction incomplete - insufficient database files found"
        exit 1
    fi
else
    error "Extraction failed - CURRENT file not found"
    exit 1
fi

log "Snapshot download and extraction completed successfully!"