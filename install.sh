#!/bin/bash

# Starknet Solo Staking Validator Installation Script
# This script installs and configures Nethermind, Lighthouse, and Juno clients
# for running a Starknet validator on Ubuntu

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="/opt/starknet-validator"
LOG_DIR="/var/log/starknet-validator"
CONFIG_DIR="/etc/starknet-validator"
USER="starknet"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
}

# Check system requirements
check_system_requirements() {
    log "Checking system requirements..."
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot determine OS version"
        exit 1
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        error "This script is designed for Ubuntu. Detected: $ID"
        exit 1
    fi
    
    # Check Ubuntu version (minimum 20.04)
    version_id=$(echo "$VERSION_ID" | cut -d. -f1)
    if [[ $version_id -lt 20 ]]; then
        error "Ubuntu 20.04 or higher required. Detected: $VERSION_ID"
        exit 1
    fi
    
    # Check available disk space (minimum 500GB)
    available_space=$(df / | tail -1 | awk '{print $4}')
    available_gb=$((available_space / 1024 / 1024))
    if [[ $available_gb -lt 500 ]]; then
        error "Insufficient disk space. Required: 500GB, Available: ${available_gb}GB"
        exit 1
    fi
    
    # Check RAM (minimum 16GB)
    total_ram=$(free -g | awk 'NR==2{print $2}')
    if [[ $total_ram -lt 16 ]]; then
        error "Insufficient RAM. Required: 16GB, Available: ${total_ram}GB"
        exit 1
    fi
    
    # Check CPU cores (minimum 4)
    cpu_cores=$(nproc)
    if [[ $cpu_cores -lt 4 ]]; then
        error "Insufficient CPU cores. Required: 4, Available: $cpu_cores"
        exit 1
    fi
    
    log "System requirements check passed"
}

# Update system packages
update_system() {
    log "Updating system packages..."
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y curl wget unzip git build-essential software-properties-common
    
    # Install Docker
    if ! command -v docker &> /dev/null; then
        log "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        systemctl enable docker
        systemctl start docker
        rm get-docker.sh
    fi
    
    # Install Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log "Installing Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
}

# Create system user and directories
setup_user_and_directories() {
    log "Setting up user and directories..."
    
    # Create system user
    if ! id "$USER" &>/dev/null; then
        useradd -r -m -s /bin/bash "$USER"
        usermod -aG docker "$USER"
    fi
    
    # Create directories
    mkdir -p "$DATA_DIR" "$LOG_DIR" "$CONFIG_DIR"
    mkdir -p "$DATA_DIR/nethermind" "$DATA_DIR/lighthouse" "$DATA_DIR/juno"
    
    # Set permissions
    chown -R "$USER:$USER" "$DATA_DIR" "$LOG_DIR" "$CONFIG_DIR"
    chmod 750 "$DATA_DIR" "$LOG_DIR" "$CONFIG_DIR"
}

# Generate JWT secret for client authentication
generate_jwt_secret() {
    log "Generating JWT secret..."
    
    JWT_SECRET_FILE="$CONFIG_DIR/jwt.hex"
    if [[ ! -f "$JWT_SECRET_FILE" ]]; then
        openssl rand -hex 32 > "$JWT_SECRET_FILE"
        chown "$USER:$USER" "$JWT_SECRET_FILE"
        chmod 600 "$JWT_SECRET_FILE"
    fi
    
    info "JWT secret generated at: $JWT_SECRET_FILE"
}

# Install Rust and Cargo (required for Lighthouse)
install_rust() {
    log "Installing Rust..."
    
    if ! command -v rustc &> /dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
    
    # Install for starknet user as well
    sudo -u "$USER" bash -c 'curl --proto="=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
}

# Install Go (required for Juno)
install_go() {
    log "Installing Go..."
    
    if ! command -v go &> /dev/null; then
        GO_VERSION="1.23.4"
        wget "https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz"
        tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
        rm "go${GO_VERSION}.linux-amd64.tar.gz"
        
        # Add to PATH
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/environment
        export PATH=$PATH:/usr/local/go/bin
    fi
}

# Install system dependencies
install_dependencies() {
    log "Installing system dependencies..."
    
    # Install required packages
    apt-get install -y \
        pkg-config \
        libssl-dev \
        libclang-dev \
        libjemalloc-dev \
        cmake \
        protobuf-compiler \
        ca-certificates \
        gnupg \
        lsb-release
    
    install_rust
    install_go
}

# Main installation function
main() {
    log "Starting Starknet Solo Staking Validator installation..."
    
    check_root
    check_system_requirements
    update_system
    setup_user_and_directories
    generate_jwt_secret
    install_dependencies
    
    log "Base installation completed successfully!"
    log "Next steps:"
    info "1. Run './install-nethermind.sh' to install Nethermind execution client"
    info "2. Run './install-lighthouse.sh' to install Lighthouse consensus client"  
    info "3. Run './install-juno.sh' to install Juno Starknet client"
    info "4. Run './setup-services.sh' to configure systemd services"
    info "5. Configure your validator keys and addresses"
}

# Run main function
main "$@"