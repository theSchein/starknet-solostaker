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
