# Starknet Solo Staking Validator Setup

This repository contains a complete Docker-based setup for running a Starknet solo staking validator with Nethermind (execution), Lighthouse (consensus), and Juno (Starknet) clients.

## ⚠️ **DISCLAIMER**

**This software is provided "as is" without warranty of any kind. Use at your own risk.**

- **Educational Purpose**: This setup is for educational and testing purposes
- **Not Financial Advice**: This is not investment or financial advice
- **Risk of Loss**: Staking cryptocurrencies involves risk of partial or total loss
- **Security Responsibility**: Users are responsible for securing their own systems
- **No Guarantees**: No guarantee of uptime, rewards, or functionality
- **Verify Everything**: Always verify contract addresses and transactions before execution

**By using this software, you acknowledge these risks and assume full responsibility.**

## Quick Start

### Initial Setup (Development/Testing)

1. **Prerequisites**
   ```bash
   # Ensure Docker and Docker Compose are installed
   docker --version
   docker compose version
   ```

2. **Initialize Environment**
   ```bash
   ./setup-docker-env.sh
   ```

3. **Configure Environment Variables**
   ```bash
   # Edit .env file created by setup script
   nano .env
   
   # Set your validator details:
   # VALIDATOR_NAME=your-validator-name
   # OPERATIONAL_ADDRESS=0xYOUR_OPERATIONAL_ADDRESS
   ```

4. **Start the Stack**
   ```bash
   docker compose up -d
   ```

5. **Verify Services**
   ```bash
   # Check container status
   docker compose ps
   
   # Monitor sync progress via logs
   docker compose logs -f nethermind | grep -i "sync\|block"
   docker compose logs -f lighthouse | grep -i "sync\|slot"
   docker compose logs -f juno | grep -i "sync\|block"
   ```

## Service Management

### Starting Services
```bash
# Start all services
docker compose up -d

# Start specific service
docker compose up -d nethermind
docker compose up -d lighthouse
docker compose up -d juno
```

### Stopping Services
```bash
# Stop all services
docker compose down

# Stop specific service
docker compose stop nethermind
docker compose stop lighthouse
docker compose stop juno
```

### Restarting Services
```bash
# Restart all services
docker compose restart

# Restart specific service
docker compose restart nethermind
```changes

### Checking Status
```bash
# View container status
docker compose ps

# View logs
docker compose logs -f                    # All services
docker compose logs -f nethermind         # Specific service
docker compose logs --tail=50 juno       # Last 50 lines
```

## Monitoring

### Web Interfaces
- **Grafana Dashboard**: http://localhost:3001 (admin/admin)
- **Prometheus Metrics**: http://localhost:9090

### API Endpoints
- **Nethermind JSON-RPC**: http://localhost:8545
- **Lighthouse Beacon API**: http://localhost:5052
- **Juno Starknet API**: http://localhost:6060

### Health Checks
```bash
# Monitor sync status via logs (APIs require JWT authentication)
docker compose logs nethermind --tail=20 | grep -E "Sync|Block|ForkChoice"
docker compose logs lighthouse --tail=20 | grep -E "Sync|Slot|Head"
docker compose logs juno --tail=20 | grep -E "Sync|Stored Block"

# Check container health
docker compose ps
```

## Maintenance and Updates

### Using the Maintenance Script
```bash
# Check validator status and health
./maintenance.sh status

# Update from Git repository and restart services
./maintenance.sh update

# Create backup of validator data
./maintenance.sh backup

# Show recent logs from all services
./maintenance.sh logs

# Restart all services
./maintenance.sh restart

# Emergency reset (WARNING: deletes all data)
./maintenance.sh reset
```

### Manual Updates
```bash
# Pull latest images
docker compose pull

# Recreate containers with new images
docker compose up -d --force-recreate
```

### Snapshot Feature
The setup includes automatic snapshot download for Juno to avoid weeks of initial sync:
- **Snapshot Source**: Official Nethermind snapshots (~172GB)
- **Automatic**: Downloads on first startup if no existing data
- **Progress**: Monitor with `docker compose logs -f juno-snapshot`
- **Skip**: Snapshot is skipped if `.snapshot_downloaded` marker exists

### Backup Strategy
```bash
# Create backup of data (maintenance script method)
./maintenance.sh backup

# Manual backup
sudo cp -r data data_backup_$(date +%Y%m%d_%H%M%S)

# Or use Docker volumes
docker run --rm -v starknet_staking_nethermind-data:/data -v $(pwd):/backup alpine tar czf /backup/nethermind_backup_$(date +%Y%m%d_%H%M%S).tar.gz /data
```

## Deployment to Validator Hardware

### Testing Environment → Production
```bash
# 1. Test locally first (this system)
./setup-docker-env.sh
docker compose up -d

# 2. Verify all services are working
docker compose ps
# Wait for sync to complete (monitor via logs)

# 3. On validator hardware, run deployment script
sudo ./deploy-to-validator.sh
```

### Production Service Management
```bash
# On validator hardware after deployment
sudo systemctl status starknet-validator
sudo systemctl start starknet-validator
sudo systemctl stop starknet-validator
sudo systemctl restart starknet-validator

# View logs
sudo journalctl -u starknet-validator -f
```

## Starknet Validator Setup

### Prerequisites
- **Minimum 20,000 STRK tokens** for mainnet staking
- **Three wallet addresses**:
  - **Staking Address**: Cold wallet holding STRK tokens
  - **Rewards Address**: Where staking rewards are sent
  - **Operational Address**: Hot wallet for attestations (needs ETH for gas)

### Step 1: Prepare Wallets
```bash
# Create/import wallets using Braavos or Argent
# Fund operational address with ETH/STRK for transaction fees
# Ensure staking address has 20,000+ STRK tokens
```

### Step 2: Configure Environment
```bash
# Copy .env.example to .env and edit with your details
cp .env.example .env
nano .env

# Set your validator name and operational address:
# VALIDATOR_NAME=your-validator-name
# OPERATIONAL_ADDRESS=0xYOUR_OPERATIONAL_ADDRESS
```

### Step 3: Start and Sync Clients
```bash
# Start the validator stack (includes automatic snapshot download)
docker compose up -d

# Monitor snapshot download progress (first time only)
docker compose logs -f juno-snapshot

# Monitor sync progress after snapshot
docker compose logs -f nethermind    # Ethereum execution sync
docker compose logs -f lighthouse   # Ethereum consensus sync  
docker compose logs -f juno         # Starknet sync

# The Juno client will automatically download a snapshot (~172GB) 
# on first run to avoid weeks of block-by-block sync
# Monitor sync status via Grafana dashboard at http://localhost:3001
```

### Step 4: Generate Validator Keys
```bash
# Generate a new operational wallet for validator attestations
# This will be your hot wallet - keep it secure but accessible to Juno

# Export private key from Braavos/Argent wallet

# Save the private key securely
echo "0xYOUR_PRIVATE_KEY" > config/validator.key
chmod 600 config/validator.key

# Update juno.yaml with your operational address
# Uncomment and set: operational-address: "0xYOUR_OPERATIONAL_ADDRESS"
```

### Step 5: Stake STRK Tokens
```bash
# Stake 20,000 STRK tokens to become a validator
# This must be done via Starknet staking interface or wallet

# Required information:
# - Staking Address: Your cold wallet with 20,000+ STRK
# - Operational Address: Hot wallet for attestations (from Step 3)
# - Rewards Address: Where you want rewards sent
# - Commission Rate: Your validator fee (e.g., 10% = 1000 basis points)

# Via Starknet Staking Interface:
# 1. Go to official Starknet staking portal
# 2. Connect wallet containing 20,000+ STRK
# 3. Fill in validator details:
#    - Operational Address: 0xYOUR_OPERATIONAL_ADDRESS
#    - Rewards Address: 0xYOUR_REWARDS_ADDRESS  
#    - Commission: 1000 (10%)
# 4. Submit staking transaction
# 5. Wait for confirmation and validator assignment

# Check your validator status: https://voyager.online/staking
```

### Step 6: Configure Validator
```bash
# After staking is confirmed, update juno.yaml:
# 1. Uncomment operational-address line
# 2. Set your operational address from Step 3
# 3. Ensure validator.key file exists in config/

# Update docker compose.yml to mount validator key
# Add to juno volumes section:
# - ./config/validator.key:/var/lib/juno/validator.key:ro
```

### Step 7: Start Validation
```bash
# Restart services with validator configuration
docker compose down
docker compose up -d

# Monitor validator logs for attestations
docker compose logs -f juno | grep -i "attest\|valid\|epoch"

# Check validator status
# - Voyager: https://voyager.online/staking
# - Monitor rewards in your rewards address
# - Check validator performance metrics in Grafana
```

## Security Considerations

### ⚠️ **CRITICAL SECURITY WARNINGS**

1. **Never share private keys or seed phrases**
2. **Always verify contract addresses before executing transactions**
3. **Use hardware wallets for staking addresses**
4. **Run validator on dedicated, hardened hardware**
5. **Regularly update all software components**

### File Permissions
```bash
# Ensure sensitive files are properly secured
chmod 600 config/jwt.hex
chmod 600 config/validator-keys/*  # If using keystore files
chmod 700 ~/.starknet/              # Starknet CLI keystore
```

### Network Security (Production)
```bash
# Firewall rules for validator hardware
sudo ufw enable
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow only necessary P2P ports
sudo ufw allow 30303/tcp    # Nethermind P2P
sudo ufw allow 9000/tcp     # Lighthouse P2P

# Block all API access from external networks
sudo ufw deny 8545/tcp      # Nethermind JSON-RPC
sudo ufw deny 5052/tcp      # Lighthouse Beacon API  
sudo ufw deny 6060/tcp      # Juno Starknet API
sudo ufw deny 3001/tcp      # Grafana
sudo ufw deny 9090/tcp      # Prometheus

# Allow SSH only from trusted IPs (replace with your IP)
sudo ufw allow from $YOUR_IP_ADDRESS to any port 22
```

### Production Hardening
```bash
# 1. Bind APIs to localhost only (already configured in docker compose.yml)
# 2. Use reverse proxy with authentication for monitoring
# 3. Implement log rotation
# 4. Set up automated security updates
# 5. Use dedicated user account with minimal privileges
```

### Private Key Management
```bash
# NEVER store private keys in plain text
# Use one of these secure methods:

# Option 1: Hardware wallet (recommended)
# - Keep operational key on hardware wallet
# - Use hardware wallet for all transactions

# Option 2: Encrypted keystore
# - Use starknet CLI to create encrypted keystore
# - Store keystore file with strong password

# Option 3: Environment variables (less secure)
# - Use only for development/testing
# - Never commit to version control
```

### Docker Security
```bash
# Run containers as non-root user
# Limit container capabilities
# Use read-only filesystems where possible
# Regularly scan images for vulnerabilities

# Check for updates
docker compose pull
docker system prune -f
```

### Backup Strategy
```bash
# Regular backups of critical data
0 2 * * * /usr/local/bin/backup-validator.sh  # Daily at 2 AM

# backup-validator.sh content:
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
docker run --rm -v /opt/starknet-validator:/data -v /backup:/backup alpine tar czf /backup/validator_backup_$DATE.tar.gz /data
find /backup -name "validator_backup_*.tar.gz" -mtime +7 -delete
```

## Troubleshooting

### Common Issues
```bash
# Container won't start
docker compose logs [service-name]

# Port conflicts
netstat -tlnp | grep [port]
# Update docker compose.yml ports

# Sync issues
# Check network connectivity
# Verify JWT token matches between clients
# Check available disk space

# Performance issues
# Monitor resource usage: docker stats
# Check system resources: htop, df -h
```

### Emergency Procedures
```bash
# Quick restart
docker compose restart

# Full reset (will lose sync data)
docker compose down
sudo rm -rf data/*
docker compose up -d

# Restore from backup
docker compose down
sudo tar xzf /backup/validator_backup_[timestamp].tar.gz -C /
docker compose up -d
```

## Contributing

This project welcomes community contributions! Here's how to help:

### Reporting Issues
- **Security Issues**: Report privately via email (never public issues)
- **Bug Reports**: Include logs, system info, and reproduction steps
- **Feature Requests**: Describe use case and proposed solution

### Contributing Code
- Fork the repository and create feature branches
- Test thoroughly on testnet before submitting
- Follow existing code style and documentation standards
- Add appropriate security warnings for new features

### Community Guidelines
- Be respectful and helpful to other users
- Share knowledge and help troubleshoot issues
- Verify information before sharing contract addresses
- Never share private keys or sensitive information

## Support Resources

- **Starknet Documentation**: https://docs.starknet.io/architecture/staking/
- **Nethermind Docs**: https://docs.nethermind.io/
- **Lighthouse Book**: https://lighthouse-book.sigmaprime.io/
- **Juno Documentation**: https://juno.nethermind.io/
- **Docker Documentation**: https://docs.docker.com/

## Configuration Files

### Important Files
- `docker-compose.yml`: Service definitions with snapshot support
- `.env.example`: Environment configuration template
- `config/jwt.hex`: JWT secret for client authentication
- `config/juno.yaml`: Juno Starknet client configuration
- `data/`: Blockchain data storage
- `starknet-validator.service`: Systemd service for production
- `maintenance.sh`: Automated maintenance and update utilities

### Directory Structure
```
starknet_solostaker/
├── docker-compose.yml                # Main service definitions with snapshot support
├── .env.example                      # Environment configuration template
├── setup-docker-env.sh              # Development environment setup
├── deploy-to-validator.sh            # Production deployment script
├── maintenance.sh                    # Maintenance and update utilities
├── generate-validator-key.sh         # Validator key generation helper
├── validator-init.sh                 # Validator initialization guide
├── install.sh                        # System installation script
├── starknet-validator.service        # Systemd service file
├── config/
│   ├── jwt.hex                       # JWT secret for client authentication
│   ├── juno.yaml                     # Juno Starknet client configuration
│   ├── prometheus.yml               # Prometheus monitoring configuration
│   └── grafana/                     # Grafana dashboards and datasources
├── data/
│   ├── nethermind/                  # Ethereum execution client data
│   ├── lighthouse/                  # Ethereum consensus client data
│   ├── juno/                        # Starknet client data (with snapshot support)
│   ├── prometheus/                  # Metrics storage
│   └── grafana/                     # Dashboard configuration
└── README.md                        # This file
```