#!/bin/bash

# Starknet Validator Key Generation Script
# This script helps generate and configure validator keys for Starknet staking

set -e

echo "=== Starknet Validator Key Generation ==="
echo
echo "This script will help you:"
echo "1. Generate a new operational wallet for validator attestations"
echo "2. Configure the validator key in juno.yaml"
echo "3. Set up secure file permissions"
echo

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

echo "🔑 Generating new validator wallet..."
echo

# Generate new account
starknet new_account --wallet validator_wallet

echo
echo "📋 Please save the following information securely:"
echo "   - Private key (needed for validator.key file)"
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

# Save private key
echo "$PRIVATE_KEY" > config/validator.key
chmod 600 config/validator.key

echo "✅ Validator key saved to config/validator.key"

# Update juno.yaml
sed -i "s/# operational-address: \"0x...\"/operational-address: \"$OPERATIONAL_ADDRESS\"/" config/juno.yaml

echo "✅ Updated juno.yaml with operational address"

# Update file permissions
chmod 600 config/juno.yaml

echo
echo "🎉 Validator key generation complete!"
echo
echo "Next steps:"
echo "1. Fund your operational address with ETH for gas fees"
echo "2. Stake 20,000 STRK tokens using the staking interface"
echo "3. Restart the validator: docker compose down && docker compose up -d"
echo
echo "Your operational address: $OPERATIONAL_ADDRESS"
echo "Remember to keep your private key secure and never share it!"