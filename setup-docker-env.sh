#!/bin/bash

# Setup Docker Environment for Starknet Validator Testing
# This script prepares the testing environment before deployment to validator hardware

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

# Check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
        error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running. Please start Docker service."
        exit 1
    fi
}

# Create directory structure
setup_directories() {
    log "Setting up directory structure..."
    
    mkdir -p data/{nethermind,lighthouse,juno,prometheus,grafana}
    
    # Set proper permissions
    chmod 755 data/{nethermind,lighthouse,juno,prometheus}
    chmod 777 data/grafana  # Grafana needs write access
    
    info "Directory structure created"
}

# Generate JWT secret if it doesn't exist
generate_jwt_secret() {
    log "Checking JWT secret..."
    
    if [[ ! -f config/jwt.hex ]]; then
        warn "JWT secret not found. Generating new one..."
        openssl rand -hex 32 > config/jwt.hex
        chmod 600 config/jwt.hex
        info "JWT secret generated at config/jwt.hex"
    else
        info "JWT secret already exists"
    fi
}

# Create .env file from template
create_env_file() {
    log "Setting up environment configuration..."
    
    if [[ ! -f .env ]]; then
        if [[ -f .env.example ]]; then
            cp .env.example .env
            info "Created .env file from template"
            warn "Please edit .env file with your validator configuration"
        else
            error ".env.example not found"
            exit 1
        fi
    else
        info ".env file already exists"
    fi
}

# Validate configuration
validate_config() {
    log "Validating configuration..."
    
    # Check required files exist
    local required_files=("docker-compose.yml" "config/juno.yaml" ".env")
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            error "Required file missing: $file"
            exit 1
        fi
    done
    
    # Check .env has required variables
    if ! grep -q "VALIDATOR_NAME" .env || ! grep -q "OPERATIONAL_ADDRESS" .env; then
        error "Missing required environment variables in .env file"
        exit 1
    fi
    
    info "Configuration validation passed"
}

# Pull Docker images
pull_images() {
    log "Pulling Docker images..."
    docker compose pull
    info "Docker images pulled successfully"
}

# Test Docker setup
test_setup() {
    log "Testing Docker setup..."
    
    # Test if containers can be created
    docker compose config > /dev/null
    
    info "Docker setup test passed"
}

# Main setup function
main() {
    log "Setting up Starknet Validator Docker testing environment..."
    
    check_docker
    setup_directories
    generate_jwt_secret
    create_env_file
    validate_config
    pull_images
    test_setup
    
    log "Setup completed successfully!"
    echo
    info "Next steps:"
    echo "1. Edit .env file with your validator configuration"
    echo "2. Start the stack: docker compose up -d"
    echo "3. Check logs: docker compose logs -f"
    echo "4. Monitor via Grafana: http://localhost:3001 (admin/admin)"
    echo "5. Test APIs:"
    echo "   - Nethermind: curl http://localhost:8545"
    echo "   - Lighthouse: curl http://localhost:5052/eth/v1/node/health"
    echo "   - Juno: curl http://localhost:6060/health"
    echo "6. Once tested, deploy to validator hardware"
}

main "$@"