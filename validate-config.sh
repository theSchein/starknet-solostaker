#!/bin/bash

# Configuration validation script - tests without downloading data

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== Starknet Validator Configuration Validation ===${NC}"
echo

# Track errors
ERRORS=0

# Test 1: Docker Compose syntax
echo -n "1. Docker Compose syntax: "
if docker compose config > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Valid${NC}"
else
    echo -e "${RED}✗ Invalid${NC}"
    ((ERRORS++))
fi

# Test 2: Required files exist
echo -n "2. Required files: "
MISSING_FILES=""
for file in docker-compose.yml config/juno.yaml maintenance.sh reset-juno.sh; do
    if [ ! -f "$file" ]; then
        MISSING_FILES="$MISSING_FILES $file"
    fi
done
if [ -z "$MISSING_FILES" ]; then
    echo -e "${GREEN}✓ All present${NC}"
else
    echo -e "${RED}✗ Missing:$MISSING_FILES${NC}"
    ((ERRORS++))
fi

# Test 3: Script syntax
echo -n "3. Script syntax check: "
SCRIPT_ERRORS=""
for script in maintenance.sh reset-juno.sh; do
    if ! bash -n "$script" 2>/dev/null; then
        SCRIPT_ERRORS="$SCRIPT_ERRORS $script"
    fi
done
if [ -z "$SCRIPT_ERRORS" ]; then
    echo -e "${GREEN}✓ Valid${NC}"
else
    echo -e "${RED}✗ Syntax errors in:$SCRIPT_ERRORS${NC}"
    ((ERRORS++))
fi

# Test 4: Environment variables
echo -n "4. Environment setup: "
if [ -f .env ]; then
    source .env 2>/dev/null
    MISSING_VARS=""
    for var in OPERATIONAL_ADDRESS VALIDATOR_PRIVATE_KEY ETHEREUM_RPC_PRIMARY JUNO_DATA_DIR; do
        if [ -z "${!var:-}" ]; then
            MISSING_VARS="$MISSING_VARS $var"
        fi
    done
    if [ -z "$MISSING_VARS" ]; then
        echo -e "${GREEN}✓ Configured${NC}"
    else
        echo -e "${YELLOW}⚠ Missing vars:$MISSING_VARS${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No .env file (will use defaults)${NC}"
fi

# Test 5: Services defined
echo -n "5. Required services: "
SERVICES=$(docker compose config --services 2>/dev/null)
REQUIRED_SERVICES="juno-snapshot juno starknet-validator prometheus grafana"
MISSING_SERVICES=""
for service in $REQUIRED_SERVICES; do
    if ! echo "$SERVICES" | grep -q "^$service$"; then
        MISSING_SERVICES="$MISSING_SERVICES $service"
    fi
done
if [ -z "$MISSING_SERVICES" ]; then
    echo -e "${GREEN}✓ All defined${NC}"
else
    echo -e "${RED}✗ Missing:$MISSING_SERVICES${NC}"
    ((ERRORS++))
fi

# Test 6: Snapshot logic
echo -n "6. Snapshot download logic: "
if grep -q "FORCE_SNAPSHOT" docker-compose.yml && grep -q "SEVEN_DAYS_AGO" docker-compose.yml; then
    echo -e "${GREEN}✓ Enhanced logic present${NC}"
else
    echo -e "${RED}✗ Old logic detected${NC}"
    ((ERRORS++))
fi

# Test 7: Juno config
echo -n "7. Juno configuration: "
if grep -q "disable-l1-verification: false" config/juno.yaml; then
    echo -e "${GREEN}✓ L1 verification enabled${NC}"
else
    echo -e "${YELLOW}⚠ L1 verification disabled${NC}"
fi

# Test 8: Maintenance commands
echo -n "8. Maintenance commands: "
if ./maintenance.sh help 2>/dev/null | grep -q "force-update" && ./maintenance.sh help 2>/dev/null | grep -q "reset-juno"; then
    echo -e "${GREEN}✓ New commands present${NC}"
else
    echo -e "${RED}✗ Missing new commands${NC}"
    ((ERRORS++))
fi

echo
echo -e "${BLUE}=== Summary ===${NC}"
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All validation checks passed!${NC}"
    echo -e "${GREEN}Ready to deploy to validator machine.${NC}"
    exit 0
else
    echo -e "${RED}✗ Found $ERRORS validation error(s)${NC}"
    echo -e "${YELLOW}Please review the errors above before deploying.${NC}"
    exit 1
fi