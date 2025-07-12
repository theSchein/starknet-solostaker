#!/bin/bash

# Starknet Validator Key Setup Script
# This script helps generate and configure validator keys for Starknet staking

set -e

echo "=== Starknet Validator Key Setup ==="
echo
echo "Choose your setup method:"
echo "1. Generate new validator keys (requires starknet CLI)"
echo "2. Configure existing keys from .env file"
echo "3. Exit"
echo

read -p "Enter your choice (1-3): " choice

case $choice in
    1)
        # Generate new keys
        echo
        echo "🔑 Generating new validator wallet..."
        
        # Check if starknet CLI is installed
        if ! command -v starknet &> /dev/null; then
            echo "❌ Starknet CLI not found. Please install it first:"
            echo "   pip install starknet-py"
            exit 1
        fi
        
        # Check if config directory exists
        if [ ! -d "config" ]; then
            echo "❌ Config directory not found. Please run this script from the starknet_staking directory."
            exit 1
        fi
        
        # Generate new account
        starknet new_account --wallet validator_wallet
        
        echo
        echo "📋 Please save the following information securely:"
        echo "   - Private key (needed for validator configuration)"
        echo "   - Public address (needed for staking)"
        echo
        
        read -p "Enter your operational address (0x...): " OPERATIONAL_ADDRESS
        read -s -p "Enter your private key (0x...): " PRIVATE_KEY
        echo
        
        # Validate inputs
        if [[ ! $OPERATIONAL_ADDRESS =~ ^0x[a-fA-F0-9]{64}$ ]]; then
            echo "❌ Invalid operational address format"
            exit 1
        fi
        
        if [[ ! $PRIVATE_KEY =~ ^0x[a-fA-F0-9]{64}$ ]]; then
            echo "❌ Invalid private key format"
            exit 1
        fi
        
        # Update .env file
        if [ -f .env ]; then
            sed -i "s/OPERATIONAL_ADDRESS=.*/OPERATIONAL_ADDRESS=$OPERATIONAL_ADDRESS/" .env
            sed -i "s/VALIDATOR_PRIVATE_KEY=.*/VALIDATOR_PRIVATE_KEY=$PRIVATE_KEY/" .env
        else
            echo "OPERATIONAL_ADDRESS=$OPERATIONAL_ADDRESS" > .env
            echo "VALIDATOR_PRIVATE_KEY=$PRIVATE_KEY" >> .env
        fi
        
        echo "✅ Updated .env file with new keys"
        ;;
        
    2)
        # Use existing keys from .env
        echo
        echo "📋 Using existing keys from .env file..."
        
        # Load environment variables
        if [ ! -f .env ]; then
            echo "❌ .env file not found. Please create it first with:"
            echo "   cp .env.example .env"
            echo "   nano .env"
            exit 1
        fi
        
        export $(grep -v '^#' .env | xargs)
        
        # Check required variables
        if [ -z "$OPERATIONAL_ADDRESS" ] || [ -z "$VALIDATOR_PRIVATE_KEY" ]; then
            echo "❌ OPERATIONAL_ADDRESS and VALIDATOR_PRIVATE_KEY must be set in .env file"
            exit 1
        fi
        
        OPERATIONAL_ADDRESS=$OPERATIONAL_ADDRESS
        PRIVATE_KEY=$VALIDATOR_PRIVATE_KEY
        echo "✅ Loaded keys from .env file"
        ;;
        
    3)
        echo "Exiting..."
        exit 0
        ;;
        
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

# Create config directory if it doesn't exist
mkdir -p config

# Generate the JSON config file
cat > config/validator-config.json << EOF
{
  "provider": {
    "http": "http://juno:6060/v0_8",
    "ws": "ws://juno:6061/v0_8"
  },
  "signer": {
    "operationalAddress": "${OPERATIONAL_ADDRESS}",
    "remoteUrl": null,
    "privateKey": "${PRIVATE_KEY}"
  },
  "metrics": {
    "enabled": true,
    "host": "0.0.0.0",
    "port": 8080
  },
  "logLevel": "info"
}
EOF

# Secure the file permissions
chmod 600 config/validator-config.json

echo "✅ Generated secure config/validator-config.json"
echo "✅ Set secure file permissions (600)"

echo
echo "🎉 Validator key setup complete!"
echo
echo "Next steps:"
echo "1. Fund your operational address with ETH for gas fees"
echo "2. Stake 20,000 STRK tokens using the staking interface"
echo "3. Start the validator: docker compose up -d starknet-validator"
echo
echo "Your operational address: $OPERATIONAL_ADDRESS"
echo "Remember to keep your private key secure and never share it!"