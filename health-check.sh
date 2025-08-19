#!/bin/bash

# Health check script for node endpoints with automatic failover to backups
# This script monitors node health and can trigger alerts or switch to backup endpoints

set -e

# Source environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check Nethermind health
check_nethermind() {
    echo -e "${YELLOW}Checking Nethermind...${NC}"
    
    # Check primary endpoint
    if curl -s -f "http://localhost:8545/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Nethermind is healthy${NC}"
        return 0
    else
        echo -e "${RED}✗ Nethermind primary endpoint is down${NC}"
        
        # Try backup endpoints
        for i in 1 2 3; do
            BACKUP_VAR="NETHERMIND_BACKUP_ENDPOINT_$i"
            BACKUP_URL="${!BACKUP_VAR}"
            if [ ! -z "$BACKUP_URL" ] && [ "$BACKUP_URL" != *"YOUR_"* ]; then
                echo -e "${YELLOW}  Trying backup endpoint $i: $BACKUP_URL${NC}"
                if curl -s -f -X POST "$BACKUP_URL" \
                    -H "Content-Type: application/json" \
                    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' > /dev/null 2>&1; then
                    echo -e "${GREEN}  ✓ Backup endpoint $i is available${NC}"
                    return 0
                fi
            fi
        done
        echo -e "${RED}  All Nethermind endpoints are down${NC}"
        return 1
    fi
}

# Function to check Lighthouse health
check_lighthouse() {
    echo -e "${YELLOW}Checking Lighthouse...${NC}"
    
    # Check primary endpoint
    if curl -s -f "http://localhost:5052/eth/v1/node/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Lighthouse is healthy${NC}"
        return 0
    else
        echo -e "${RED}✗ Lighthouse primary endpoint is down${NC}"
        
        # Try backup endpoints (checkpoint sync URLs)
        for i in 1 2 3; do
            BACKUP_VAR="LIGHTHOUSE_BACKUP_ENDPOINT_$i"
            BACKUP_URL="${!BACKUP_VAR}"
            if [ ! -z "$BACKUP_URL" ]; then
                echo -e "${YELLOW}  Trying backup endpoint $i: $BACKUP_URL${NC}"
                if curl -s -f "$BACKUP_URL/eth/v1/node/health" > /dev/null 2>&1; then
                    echo -e "${GREEN}  ✓ Backup endpoint $i is available${NC}"
                    return 0
                fi
            fi
        done
        echo -e "${RED}  All Lighthouse endpoints are down${NC}"
        return 1
    fi
}

# Function to check Juno health
check_juno() {
    echo -e "${YELLOW}Checking Juno...${NC}"
    
    # Check primary endpoint
    if curl -s -f "http://localhost:6060/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Juno is healthy${NC}"
        return 0
    else
        echo -e "${RED}✗ Juno primary endpoint is down${NC}"
        
        # Try backup endpoints
        for i in 1 2 3; do
            BACKUP_VAR="JUNO_BACKUP_ENDPOINT_$i"
            BACKUP_URL="${!BACKUP_VAR}"
            if [ ! -z "$BACKUP_URL" ] && [ "$BACKUP_URL" != *"YOUR_"* ]; then
                echo -e "${YELLOW}  Trying backup endpoint $i: $BACKUP_URL${NC}"
                if curl -s -f -X POST "$BACKUP_URL" \
                    -H "Content-Type: application/json" \
                    -d '{"jsonrpc":"2.0","method":"starknet_blockNumber","params":[],"id":1}' > /dev/null 2>&1; then
                    echo -e "${GREEN}  ✓ Backup endpoint $i is available${NC}"
                    return 0
                fi
            fi
        done
        echo -e "${RED}  All Juno endpoints are down${NC}"
        return 1
    fi
}

# Function to check Starknet Validator health
check_validator() {
    echo -e "${YELLOW}Checking Starknet Validator...${NC}"
    
    if curl -s -f "http://localhost:8081/metrics" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Starknet Validator is healthy${NC}"
        return 0
    else
        echo -e "${RED}✗ Starknet Validator is down${NC}"
        return 1
    fi
}

# Main health check
echo "========================================="
echo "Node Health Check - $(date)"
echo "========================================="

OVERALL_HEALTH=0

check_nethermind || OVERALL_HEALTH=1
echo ""
check_lighthouse || OVERALL_HEALTH=1
echo ""
check_juno || OVERALL_HEALTH=1
echo ""
check_validator || OVERALL_HEALTH=1

echo "========================================="
if [ $OVERALL_HEALTH -eq 0 ]; then
    echo -e "${GREEN}All services are healthy${NC}"
else
    echo -e "${RED}Some services are unhealthy or using backup endpoints${NC}"
    echo -e "${YELLOW}Consider investigating the failing nodes${NC}"
fi
echo "========================================="

exit $OVERALL_HEALTH