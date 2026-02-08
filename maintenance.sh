#!/bin/bash

# Starknet Validator Maintenance Script
# Provides utilities for updates, backups, and health checks

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

# Show help
show_help() {
    echo "Starknet Validator Maintenance Script"
    echo
    echo "Usage: $0 [COMMAND]"
    echo
    echo "Commands:"
    echo "  status        - Check validator status and health"
    echo "  update        - Update from Git repository and restart services"
    echo "  force-update  - Update with forced fresh snapshot download"
    echo "  backup        - Create backup of validator data"
    echo "  restore       - Restore from backup"
    echo "  logs          - Show recent logs from all services"
    echo "  start         - Start all services"
    echo "  stop          - Stop all services"
    echo "  restart       - Restart all services"
    echo "  reset         - Reset and resync (WARNING: deletes all data)"
    echo "  reset-juno    - Reset only Juno with fresh snapshot"
    echo "  help          - Show this help message"
    echo
    echo "Examples:"
    echo "  $0 status"
    echo "  $0 update"
    echo "  $0 force-update"
    echo "  $0 backup"
    echo "  $0 logs"
}

# Check validator status
check_status() {
    log "Checking validator status..."
    echo
    
    # Container status
    info "Container Status:"
    docker compose ps
    echo
    
    # Sync status
    info "Sync Status:"
    
    # Ethereum RPC Status (if configured)
    if [[ -n "${ETHEREUM_RPC_PRIMARY:-}" ]]; then
        echo -n "  Ethereum RPC (Primary): "
        if curl -s "${ETHEREUM_RPC_PRIMARY}" -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | grep -q "result"; then
            echo -e "${GREEN}CONNECTED${NC}"
        else
            echo -e "${RED}DISCONNECTED${NC}"
        fi
    fi
    
    if [[ -n "${ETHEREUM_RPC_BACKUP:-}" ]]; then
        echo -n "  Ethereum RPC (Backup): "
        if curl -s "${ETHEREUM_RPC_BACKUP}" -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | grep -q "result"; then
            echo -e "${GREEN}CONNECTED${NC}"
        else
            echo -e "${RED}DISCONNECTED${NC}"
        fi
    fi
    
    # Juno
    echo -n "  Juno (Starknet): "
    local juno_block=$(curl -s http://localhost:6060 -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"starknet_blockNumber","params":[],"id":1}' 2>/dev/null | grep -o '"result":"[^"]*"' | cut -d'"' -f4 || echo "")
    if [[ -n "$juno_block" ]]; then
        echo -e "${GREEN}SYNCING${NC} (Block: $juno_block)"
    else
        echo -e "${RED}ERROR${NC}"
    fi
    
    echo
    
    # Disk usage
    info "Disk Usage:"
    df -h | grep -E "(Filesystem|/dev/)"
    echo
    
    # Data directory sizes
    info "Data Directory Sizes:"
    if [[ -d data ]]; then
        du -sh data/* 2>/dev/null | sort -hr
    else
        echo "  No data directory found"
    fi
    
    echo
    
    # Resource usage
    info "Resource Usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" | head -10
}

# Update from Git repository and Docker images
update_images() {
    log "Updating validator from Git repository..."

    # JUNO v0.15.18 MIGRATION WARNING
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}⚠️  IMPORTANT: Juno v0.15.18 Database Migration Notice${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}This update includes Juno's new storage-optimized database layout.${NC}"
    echo -e "${YELLOW}Expected changes:${NC}"
    echo -e "${YELLOW}  • Migration time: ~3 hours (validator will be offline)${NC}"
    echo -e "${YELLOW}  • Storage reduction: 500GB → 200GB (60% reduction)${NC}"
    echo -e "${YELLOW}  • This change is IRREVERSIBLE${NC}"
    echo -e "${YELLOW}  • Will become mandatory in Juno v0.16.0${NC}"
    echo ""
    echo -e "${YELLOW}The migration will start automatically when Juno restarts.${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    read -p "Do you want to proceed with the update? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        log "Update cancelled by user"
        exit 0
    fi

    # Check if we're in a git repository
    if [ ! -d ".git" ]; then
        warn "Not a Git repository. Updating Docker images only..."
        update_docker_only
        return
    fi

    # Create lightweight backup of sensitive files only (no data folder)
    if [[ "${ENABLE_AUTO_BACKUP:-true}" == "true" ]]; then
        warn "Creating backup of sensitive files..."
        create_config_backup "pre-update"
    else
        info "Auto-backup disabled via ENABLE_AUTO_BACKUP=false"
    fi
    
    # Pull latest changes from Git
    info "Pulling latest changes from repository..."
    if ! git pull origin main 2>/dev/null; then
        if ! git pull origin master 2>/dev/null; then
            warn "Could not pull from remote. Continuing with Docker update only..."
        fi
    fi
    
    # Restore sensitive files from backup
    info "Restoring sensitive configuration files..."
    restore_sensitive_files
    
    # Pull latest Docker images
    info "Pulling latest Docker images..."
    docker compose pull
    
    # Stop services
    info "Stopping services..."
    docker compose down
    
    # Start with updated configuration and images
    info "Starting services with updated configuration..."
    docker compose up -d
    
    # Wait for services to start
    sleep 10
    
    # Check status
    info "Checking service status after update..."
    docker compose ps
    
    log "Update completed successfully!"
    info "Monitor logs with: ./maintenance.sh logs"
}

# Update Docker images only (fallback)
update_docker_only() {
    log "Updating Docker images only..."
    
    # Create backup before update
    if [[ "${ENABLE_AUTO_BACKUP:-true}" == "true" ]]; then
        warn "Creating backup before update..."
        create_backup "pre-update"
    else
        info "Auto-backup disabled via ENABLE_AUTO_BACKUP=false"
    fi
    
    # Pull latest images
    info "Pulling latest Docker images..."
    docker compose pull
    
    # Stop services
    info "Stopping services..."
    docker compose down
    
    # Start with new images
    info "Starting services with updated images..."
    docker compose up -d
    
    # Wait for services to start
    sleep 10
    
    # Check status
    info "Checking service status after update..."
    docker compose ps
    
    log "Docker update completed successfully!"
}

# Restore sensitive files from backup
restore_sensitive_files() {
    local backup_dir="backups"
    local latest_backup=$(ls -t "$backup_dir"/validator_config_backup_pre-update_*.tar.gz 2>/dev/null | head -1)
    
    if [[ -z "$latest_backup" ]]; then
        warn "No pre-update config backup found. Skipping sensitive file restoration."
        return
    fi
    
    # Create temporary directory for extraction
    local temp_dir=$(mktemp -d)
    
    # Extract backup to temp directory
    tar -xzf "$latest_backup" -C "$temp_dir" 2>/dev/null || true
    
    # Restore JWT token if missing
    if [[ -f "$temp_dir/config/jwt.hex" ]] && [[ ! -f "config/jwt.hex" ]]; then
        info "Restoring JWT token..."
        cp "$temp_dir/config/jwt.hex" config/
        chmod 600 config/jwt.hex
    fi
    
    # Restore validator key if missing
    if [[ -f "$temp_dir/config/validator.key" ]] && [[ ! -f "config/validator.key" ]]; then
        info "Restoring validator key..."
        cp "$temp_dir/config/validator.key" config/
        chmod 600 config/validator.key
    fi
    
    # Restore operational address in juno.yaml
    if [[ -f "$temp_dir/config/juno.yaml" ]]; then
        local operational_address=$(grep "operational-address:" "$temp_dir/config/juno.yaml" | grep -v "^#" | cut -d'"' -f2 2>/dev/null || true)
        if [[ -n "$operational_address" ]] && [[ "$operational_address" != "0x..." ]]; then
            info "Restoring operational address in juno.yaml..."
            sed -i "s/# operational-address: \"0x...\"/operational-address: \"$operational_address\"/" config/juno.yaml
        fi
    fi
    
    # Clean up temp directory
    rm -rf "$temp_dir"
    
    info "Sensitive files restored successfully"
}

# Create lightweight backup of config files only (no data folder)
create_config_backup() {
    local backup_name="${1:-manual}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="backups"
    local backup_file="${backup_dir}/validator_config_backup_${backup_name}_${timestamp}.tar.gz"
    
    log "Creating config backup: $backup_file"
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Create backup of config files only (no data folder)
    info "Creating config backup archive..."
    tar -czf "$backup_file" \
        --exclude='*.log' \
        --exclude='backups' \
        config/ docker compose.yml *.txt *.sh 2>/dev/null || true
    
    # Show backup info
    local backup_size=$(du -h "$backup_file" | cut -f1)
    info "Config backup created: $backup_file ($backup_size)"
    
    # Clean old config backups (keep last 10)
    info "Cleaning old config backups..."
    ls -t "$backup_dir"/validator_config_backup_*.tar.gz | tail -n +11 | xargs -r rm -f
    
    log "Config backup completed successfully!"
}

# Create backup
create_backup() {
    local backup_name="${1:-manual}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="backups"
    local backup_file="${backup_dir}/validator_backup_${backup_name}_${timestamp}.tar.gz"
    
    log "Creating backup: $backup_file"
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Stop services for consistent backup
    info "Stopping services for backup..."
    docker compose down
    
    # Create backup
    info "Creating backup archive..."
    tar -czf "$backup_file" \
        --exclude='*.log' \
        --exclude='backups' \
        data/ config/ docker compose.yml *.txt 2>/dev/null || true
    
    # Restart services
    info "Restarting services..."
    docker compose up -d
    
    # Show backup info
    local backup_size=$(du -h "$backup_file" | cut -f1)
    info "Backup created: $backup_file ($backup_size)"
    
    # Clean old backups (keep last 5)
    info "Cleaning old backups..."
    ls -t "$backup_dir"/validator_backup_*.tar.gz | tail -n +6 | xargs -r rm -f
    
    log "Backup completed successfully!"
}

# Restore from backup
restore_backup() {
    local backup_dir="backups"
    
    if [[ ! -d "$backup_dir" ]]; then
        error "No backups directory found"
        exit 1
    fi
    
    # List available backups
    info "Available backups:"
    ls -la "$backup_dir"/validator_backup_*.tar.gz 2>/dev/null || {
        error "No backups found"
        exit 1
    }
    
    echo
    read -p "Enter backup filename to restore: " backup_file
    
    if [[ ! -f "$backup_dir/$backup_file" ]]; then
        error "Backup file not found: $backup_dir/$backup_file"
        exit 1
    fi
    
    warn "This will overwrite current data. Are you sure?"
    read -p "Type 'yes' to confirm: " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        info "Restore cancelled"
        exit 0
    fi
    
    log "Restoring from backup: $backup_file"
    
    # Stop services
    info "Stopping services..."
    docker compose down
    
    # Remove current data
    info "Removing current data..."
    rm -rf data/ config/
    
    # Extract backup
    info "Extracting backup..."
    tar -xzf "$backup_dir/$backup_file"
    
    # Restart services
    info "Starting services..."
    docker compose up -d
    
    log "Restore completed successfully!"
}

# Show logs
show_logs() {
    local service="${1:-}"
    local lines="${2:-50}"
    
    if [[ -n "$service" ]]; then
        info "Showing logs for $service (last $lines lines):"
        docker compose logs --tail="$lines" "$service"
    else
        info "Showing logs for all services (last $lines lines):"
        docker compose logs --tail="$lines"
    fi
}

# Start services
start_services() {
    log "Starting all services..."
    
    # Load environment variables
    if [[ -f .env ]]; then
        export $(cat .env | grep -v '^#' | xargs)
    fi
    
    docker compose up -d
    
    # Wait for services to start
    sleep 10
    
    info "Service status after start:"
    docker compose ps
}

# Stop services
stop_services() {
    log "Stopping all services..."
    docker compose down
    info "All services stopped"
}

# Restart services
restart_services() {
    log "Restarting all services..."
    docker compose restart
    
    # Wait for services to start
    sleep 10
    
    info "Service status after restart:"
    docker compose ps
}

# Force update with fresh snapshot
force_update() {
    log "Starting force update with fresh snapshot download..."

    warn "This will force download a fresh Juno snapshot (200GB+)"
    warn "The validator will be offline for 30-60 minutes"
    echo
    read -p "Do you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        log "Force update cancelled by user"
        exit 0
    fi

    # Set force snapshot flag
    export FORCE_SNAPSHOT=true

    # Proceed with normal update
    update_images
}

# Reset only Juno with fresh snapshot
reset_juno_only() {
    log "Resetting Juno with fresh snapshot..."

    # Check if reset-juno.sh exists
    if [[ -f "./reset-juno.sh" ]]; then
        ./reset-juno.sh
    else
        warn "reset-juno.sh script not found!"
        warn "Running inline reset..."

        # Stop services
        info "Stopping services..."
        docker compose down

        # Remove Juno data
        info "Removing Juno data..."
        rm -rf "${JUNO_DATA_DIR:-./data}/juno"/*
        rm -f "${JUNO_DATA_DIR:-./data}/juno"/.snapshot_downloaded

        # Force snapshot download
        export FORCE_SNAPSHOT=true

        # Start services
        info "Starting services with forced snapshot..."
        docker compose up -d

        log "Juno reset initiated. Monitor with: docker logs -f starknet-juno-snapshot"
    fi
}

# Reset and resync
reset_validator() {
    warn "This will delete ALL validator data and start fresh sync!"
    warn "This operation cannot be undone!"
    echo
    read -p "Type 'RESET' to confirm: " confirmation

    if [[ "$confirmation" != "RESET" ]]; then
        info "Reset cancelled"
        exit 0
    fi

    log "Resetting validator..."

    # Stop services
    info "Stopping services..."
    docker compose down

    # Remove data
    info "Removing all data..."
    rm -rf data/

    # Recreate directories
    info "Recreating directories..."
    mkdir -p data/{juno,prometheus,grafana}
    chmod 755 data/{juno,prometheus}
    chmod 777 data/grafana

    # Start services
    info "Starting services..."
    docker compose up -d

    log "Reset completed. Services will start syncing from scratch."
}

# Main function
main() {
    local command="${1:-help}"

    case "$command" in
        "status")
            check_status
            ;;
        "update")
            update_images
            ;;
        "force-update")
            force_update
            ;;
        "backup")
            create_backup
            ;;
        "restore")
            restore_backup
            ;;
        "logs")
            show_logs "${2:-}" "${3:-50}"
            ;;
        "start")
            start_services
            ;;
        "stop")
            stop_services
            ;;
        "restart")
            restart_services
            ;;
        "reset")
            reset_validator
            ;;
        "reset-juno")
            reset_juno_only
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# Run main function
main "$@"