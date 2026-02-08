# Starknet Validator Fix Instructions

## Issue Summary
Your validator hasn't attested in a week due to:
1. Outdated Juno database (from July 2025)
2. Snapshot download logic not triggering for existing but old data
3. Incorrect Ethereum RPC configuration
4. L1 verification disabled

## Fix Applied
The following changes have been made to fix these issues:

### 1. Enhanced Snapshot Download Logic
- Modified `docker-compose.yml` to check snapshot age (7 days)
- Added `FORCE_SNAPSHOT` environment variable for manual override
- Improved error handling and verification

### 2. Fixed Ethereum RPC Configuration
- Updated `juno.yaml` to use external Ethereum RPC endpoints
- Enabled L1 verification for proper attestation
- Added command-line override for eth-node parameter

### 3. New Reset Script
- Created `reset-juno.sh` for clean Juno restart with fresh snapshot
- Includes backup option, progress monitoring, and verification

### 4. Updated Maintenance Script
- Added `force-update` command for forced snapshot download
- Added `reset-juno` command for Juno-only reset

## Deployment Steps

### Option 1: Quick Fix (Recommended)
Deploy changes and reset Juno with fresh snapshot:

```bash
# On your dev machine
git add -A
git commit -m "Fix validator attestation issues - force fresh Juno snapshot"
git push

# On validator machine
cd /path/to/validator
git pull
./reset-juno.sh
```

### Option 2: Force Update
Use the maintenance script with force update:

```bash
# On validator machine after pulling changes
./maintenance.sh force-update
```

### Option 3: Manual Steps
If automated scripts fail:

```bash
# Stop services
docker compose down

# Remove old Juno data
rm -rf /media/dov/ethdata/juno/*

# Force fresh snapshot
export FORCE_SNAPSHOT=true
docker compose up -d juno-snapshot

# Wait for download (monitor progress)
docker logs -f starknet-juno-snapshot

# Start all services
docker compose up -d
```

## Monitoring After Fix

### 1. Check Snapshot Download
```bash
docker logs starknet-juno-snapshot
```
Should show: "Snapshot downloaded and extracted successfully!"

### 2. Check Juno Sync Status
```bash
curl -s http://localhost:6060 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"starknet_blockNumber","params":[],"id":1}'
```

### 3. Check Validator Status
```bash
docker logs starknet-validator
curl http://localhost:8081/metrics
```

### 4. Monitor via Grafana
Access http://localhost:3001 to view metrics dashboard

## Expected Timeline
1. **Snapshot Download**: 30-60 minutes (200GB download)
2. **Juno Initial Sync**: 2-4 hours to catch up to chain tip
3. **Attestation Resume**: Should begin once Juno is synced

## Verification Checklist
- [ ] Juno snapshot downloaded successfully
- [ ] Juno block number increasing
- [ ] Validator connected to Juno
- [ ] Ethereum RPC accessible
- [ ] Validator metrics showing activity
- [ ] Attestations appearing on chain

## Troubleshooting

### If snapshot download fails:
1. Check disk space: `df -h /media/dov/ethdata`
2. Check network: `curl -I https://juno-snapshots.nethermind.io`
3. Retry with: `FORCE_SNAPSHOT=true docker compose up -d juno-snapshot`

### If Juno won't sync:
1. Check Ethereum RPC: Ensure .env has valid RPC endpoints
2. Check logs: `docker logs starknet-juno | grep ERROR`
3. Verify L1 connection: Check if Ethereum RPC is accessible

### If validator won't attest:
1. Ensure Juno is fully synced
2. Check validator key and operational address in .env
3. Verify validator registration on-chain

## Support
If issues persist after following these steps:
1. Collect logs: `docker compose logs > validator_logs.txt`
2. Check disk space and system resources
3. Verify network connectivity to Ethereum and Starknet peers