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
    
    if ! command -v docker-compose &> /dev/null; then
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
    mkdir -p config/grafana/provisioning/{dashboards,datasources}
    
    # Set proper permissions
    chmod 755 data/{nethermind,lighthouse,juno,prometheus}
    chmod 777 data/grafana  # Grafana needs write access
    
    info "Directory structure created"
}

# Generate JWT secret
generate_jwt_secret() {
    log "Generating JWT secret for client authentication..."
    
    if [[ ! -f config/jwt.hex ]]; then
        openssl rand -hex 32 > config/jwt.hex
        chmod 600 config/jwt.hex
    fi
    
    info "JWT secret generated at config/jwt.hex"
}

# Create Nethermind configuration
create_nethermind_config() {
    log "Creating Nethermind configuration..."
    
    cat > config/nethermind.cfg << EOF
[JsonRpc]
Enabled=true
Host=0.0.0.0
Port=8545
WebSocketsPort=8546
JwtSecretFile=/nethermind/jwt.hex

[Network]
P2PPort=30303
DiscoveryPort=30303

[Logging]
LogLevel=Info

[Sync]
FastSync=true
PivotNumber=0
PivotHash=0x0000000000000000000000000000000000000000000000000000000000000000

[EthStats]
Enabled=false

[Metrics]
Enabled=true
PushGatewayUrl=http://prometheus:9090
EOF
    
    info "Nethermind configuration created"
}

# Create Juno configuration
create_juno_config() {
    log "Creating Juno configuration..."
    
    cat > config/juno.yaml << EOF
network: "mainnet"
eth-node: "ws://nethermind:8546"
db-path: "/var/lib/juno"
http: true
http-port: 6060
http-host: "0.0.0.0"
log-level: "INFO"
colour: true
pending-poll-interval: "1s"
rpc-max-block-scan: 100000
EOF
    
    info "Juno configuration created"
}

# Create Prometheus configuration
create_prometheus_config() {
    log "Creating Prometheus configuration..."
    
    cat > config/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'nethermind'
    static_configs:
      - targets: ['nethermind:8545']
    metrics_path: '/metrics'
    scrape_interval: 30s

  - job_name: 'lighthouse'
    static_configs:
      - targets: ['lighthouse:5052']
    metrics_path: '/metrics'
    scrape_interval: 30s

  - job_name: 'juno'
    static_configs:
      - targets: ['juno:6060']
    metrics_path: '/metrics'
    scrape_interval: 30s
EOF
    
    info "Prometheus configuration created"
}

# Create Grafana datasource
create_grafana_datasource() {
    log "Creating Grafana datasource configuration..."
    
    cat > config/grafana/provisioning/datasources/prometheus.yml << EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
EOF
    
    info "Grafana datasource configuration created"
}

# Create systemd service for production deployment
create_systemd_service() {
    log "Creating systemd service template for production deployment..."
    
    cat > starknet-validator.service << EOF
[Unit]
Description=Starknet Validator Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/starknet-validator
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
    
    info "Systemd service template created: starknet-validator.service"
}

# Create deployment script
create_deployment_script() {
    log "Creating deployment script for validator hardware..."
    
    cat > deploy-to-validator.sh << 'EOF'
#!/bin/bash

# Deploy tested Docker configuration to validator hardware
# This script should be run on the validator hardware

set -euo pipefail

VALIDATOR_DIR="/opt/starknet-validator"
SERVICE_NAME="starknet-validator"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root on validator hardware"
    exit 1
fi

# Create validator directory
mkdir -p "$VALIDATOR_DIR"

# Copy configuration files
cp -r config data docker-compose.yml "$VALIDATOR_DIR/"

# Copy systemd service
cp starknet-validator.service /etc/systemd/system/

# Set proper ownership
chown -R root:root "$VALIDATOR_DIR"
chmod 755 "$VALIDATOR_DIR"

# Enable and start service
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

echo "Starknet validator deployed successfully!"
echo "Check status with: systemctl status $SERVICE_NAME"
EOF
    
    chmod +x deploy-to-validator.sh
    info "Deployment script created: deploy-to-validator.sh"
}

# Main setup function
main() {
    log "Setting up Starknet Validator Docker testing environment..."
    
    check_docker
    setup_directories
    generate_jwt_secret
    create_nethermind_config
    create_juno_config
    create_prometheus_config
    create_grafana_datasource
    create_systemd_service
    create_deployment_script
    
    log "Setup completed successfully!"
    echo
    info "Next steps:"
    echo "1. Start the stack: docker-compose up -d"
    echo "2. Check logs: docker-compose logs -f"
    echo "3. Monitor via Grafana: http://localhost:3000 (admin/admin)"
    echo "4. Test APIs:"
    echo "   - Nethermind: curl http://localhost:8545"
    echo "   - Lighthouse: curl http://localhost:5052/eth/v1/node/health"
    echo "   - Juno: curl http://localhost:6060/health"
    echo "5. Once tested, deploy to validator: ./deploy-to-validator.sh"
}

main "$@"