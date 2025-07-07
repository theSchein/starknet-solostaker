#!/bin/bash

# Starknet Validator Initialization Script
# This script guides you through the process of setting up your validator after the infrastructure is running

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

# Check if services are running
check_services() {
    log "Checking if validator services are running..."
    
    if ! docker-compose ps | grep -q "Up"; then
        error "Validator services are not running. Please start them first:"
        echo "  docker-compose up -d"
        exit 1
    fi
    
    info "Services are running"
}

# Check sync status
check_sync_status() {
    log "Checking sync status of all clients..."
    
    # Check Nethermind sync
    info "Checking Nethermind (Ethereum execution) sync..."
    if ! curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' | grep -q "false"; then
        warn "Nethermind is still syncing. This may take several hours."
        echo "  Monitor with: docker-compose logs -f nethermind"
    else
        info "Nethermind is fully synced"
    fi
    
    # Check Lighthouse sync
    info "Checking Lighthouse (Ethereum consensus) sync..."
    if ! curl -s http://localhost:5052/eth/v1/node/syncing 2>/dev/null | grep -q '"is_syncing":false'; then
        warn "Lighthouse is still syncing. This may take several hours."
        echo "  Monitor with: docker-compose logs -f lighthouse"
    else
        info "Lighthouse is fully synced"
    fi
    
    # Check Juno sync
    info "Checking Juno (Starknet) sync..."
    local juno_block=$(curl -s http://localhost:6060 -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"starknet_blockNumber","params":[],"id":1}' 2>/dev/null | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
    if [[ -n "$juno_block" ]]; then
        info "Juno is syncing. Current block: $juno_block"
    else
        warn "Unable to get Juno sync status. Check logs: docker-compose logs -f juno"
    fi
}

# Display wallet setup instructions
show_wallet_setup() {
    log "Wallet Setup Instructions"
    echo
    echo "You need to prepare 3 wallet addresses:"
    echo
    echo "1. ${BLUE}STAKING ADDRESS${NC} (Cold Wallet)"
    echo "   - Must hold minimum 20,000 STRK tokens"
    echo "   - Should be a hardware wallet or cold storage"
    echo "   - Used only for staking transactions"
    echo
    echo "2. ${BLUE}REWARDS ADDRESS${NC} (Any Wallet)"
    echo "   - Where staking rewards will be sent"
    echo "   - Can be the same as staking address"
    echo "   - Recommended: separate address for tracking"
    echo
    echo "3. ${BLUE}OPERATIONAL ADDRESS${NC} (Hot Wallet)"
    echo "   - Used for validator attestations"
    echo "   - Must have ETH for transaction fees"
    echo "   - Should be accessible by validator software"
    echo
    echo "Recommended wallets: Braavos, Argent"
    echo
    read -p "Press Enter when you have prepared these addresses..."
}

# Collect wallet addresses
collect_addresses() {
    log "Collecting wallet addresses..."
    echo
    
    read -p "Enter your STAKING ADDRESS: " STAKING_ADDRESS
    read -p "Enter your REWARDS ADDRESS: " REWARDS_ADDRESS
    read -p "Enter your OPERATIONAL ADDRESS: " OPERATIONAL_ADDRESS
    
    # Validate addresses (basic check)
    if [[ ${#STAKING_ADDRESS} -ne 66 || ${#REWARDS_ADDRESS} -ne 66 || ${#OPERATIONAL_ADDRESS} -ne 66 ]]; then
        error "Invalid address format. Starknet addresses should be 66 characters long (0x...)"
        exit 1
    fi
    
    echo
    info "Addresses collected:"
    echo "  Staking:     $STAKING_ADDRESS"
    echo "  Rewards:     $REWARDS_ADDRESS"
    echo "  Operational: $OPERATIONAL_ADDRESS"
    echo
    
    # Save addresses to file
    cat > validator-addresses.txt << EOF
# Starknet Validator Addresses
# Generated on $(date)

STAKING_ADDRESS=$STAKING_ADDRESS
REWARDS_ADDRESS=$REWARDS_ADDRESS
OPERATIONAL_ADDRESS=$OPERATIONAL_ADDRESS

# Commission rate (basis points, e.g., 1000 = 10%)
COMMISSION_RATE=1000

# Minimum staking amount (20,000 STRK in wei)
STAKE_AMOUNT=20000000000000000000000
EOF
    
    info "Addresses saved to validator-addresses.txt"
}

# Generate staking commands
generate_staking_commands() {
    log "Generating staking commands..."
    
    source validator-addresses.txt
    
    cat > staking-commands.txt << EOF
# Starknet Validator Staking Commands
# Generated on $(date)

# Step 1: Approve STRK token transfer to staking contract
# Execute this from your STAKING ADDRESS wallet

# Using Starknet CLI:
starknet invoke \\
  --address 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d \\
  --abi erc20_abi.json \\
  --function approve \\
  --inputs 0x0000000000000000000000000000000000000000000000000000000000000000 $STAKE_AMOUNT

# Step 2: Stake tokens and register validator
# Execute this from your STAKING ADDRESS wallet

starknet invoke \\
  --address 0x0000000000000000000000000000000000000000000000000000000000000000 \\
  --abi staking_abi.json \\
  --function stake \\
  --inputs $STAKE_AMOUNT $OPERATIONAL_ADDRESS $REWARDS_ADDRESS $COMMISSION_RATE

# Alternative: Use a wallet interface like Braavos or Argent
# 1. Navigate to the staking contract
# 2. Call 'approve' function on STRK token contract
# 3. Call 'stake' function on staking contract

# Contract Addresses (verify these are current):
# STRK Token: 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
# Staking Contract: TBD (check latest Starknet documentation)

EOF
    
    info "Staking commands generated in staking-commands.txt"
    warn "IMPORTANT: Verify contract addresses with latest Starknet documentation before executing!"
}

# Configure validator
configure_validator() {
    log "Configuring validator settings..."
    
    # Update Juno configuration with validator settings
    if [[ -f config/juno.yaml ]]; then
        cp config/juno.yaml config/juno.yaml.backup
        
        # Add validator-specific configuration
        cat >> config/juno.yaml << EOF

# Validator Configuration
# Added on $(date)
validator:
  enabled: true
  operational-address: "$OPERATIONAL_ADDRESS"
  
# Enhanced logging for validator operations
log-level: "DEBUG"
EOF
        
        info "Juno configuration updated with validator settings"
        warn "You may need to add the operational address private key securely"
    else
        error "Juno configuration file not found. Run setup-docker-env.sh first."
        exit 1
    fi
}

# Display next steps
show_next_steps() {
    log "Validator initialization complete!"
    echo
    echo "${GREEN}NEXT STEPS:${NC}"
    echo
    echo "1. ${BLUE}Wait for full sync${NC}"
    echo "   - All clients must be fully synced before staking"
    echo "   - Monitor: docker-compose logs -f"
    echo "   - Check sync status: curl http://localhost:8545 -X POST -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_syncing\",\"params\":[],\"id\":1}'"
    echo
    echo "2. ${BLUE}Fund operational address${NC}"
    echo "   - Send ETH to operational address for transaction fees"
    echo "   - Recommended: 0.1 ETH to start"
    echo
    echo "3. ${BLUE}Execute staking commands${NC}"
    echo "   - Review staking-commands.txt"
    echo "   - Verify contract addresses are current"
    echo "   - Execute from staking address wallet"
    echo
    echo "4. ${BLUE}Restart validator with new configuration${NC}"
    echo "   - docker-compose restart juno"
    echo
    echo "5. ${BLUE}Monitor validator operation${NC}"
    echo "   - Watch logs: docker-compose logs -f juno"
    echo "   - Check Starknet explorer for your validator"
    echo "   - Monitor rewards in rewards address"
    echo
    echo "${YELLOW}WARNING:${NC} Only proceed to step 3 after full sync completion!"
    echo "${YELLOW}WARNING:${NC} Verify all contract addresses before executing transactions!"
    echo
    echo "Files created:"
    echo "  - validator-addresses.txt (your addresses)"
    echo "  - staking-commands.txt (commands to execute)"
    echo "  - config/juno.yaml (updated configuration)"
}

# Main function
main() {
    log "Starting Starknet Validator Initialization..."
    echo
    
    check_services
    check_sync_status
    
    echo
    read -p "Continue with validator setup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Initialization cancelled"
        exit 0
    fi
    
    show_wallet_setup
    collect_addresses
    generate_staking_commands
    configure_validator
    show_next_steps
    
    log "Validator initialization script completed!"
}

# Run main function
main "$@"