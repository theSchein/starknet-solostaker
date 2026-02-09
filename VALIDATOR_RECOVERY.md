# Validator Recovery Instructions

## Problem
Your validator on the remote machine has:
- Corrupted Juno database
- Failed snapshot download (partial/corrupted)
- Juno not syncing

## Solution

### Step 1: Deploy Latest Code to Validator

From this workstation:
```bash
# Push any uncommitted changes
git push

# Deploy to validator (if you have deploy script)
./deploy-to-validator.sh

# OR manually SSH and pull
ssh validator "cd /path/to/starknet_staking && git pull"
```

### Step 2: Connect to Validator

```bash
ssh validator
cd /path/to/starknet_staking
```

### Step 3: Choose Recovery Method

## Method A: Clean Recovery (Recommended)
Use this if Juno is completely broken:

```bash
# 1. Stop all services
docker compose down

# 2. Clean all old Juno data
rm -rf data/juno/*

# 3. Start screen session for stable download
screen -S snapshot

# 4. Run manual download script (inside screen)
./manual-snapshot-download.sh
# This will download ~200GB with automatic retries
# Press Ctrl+A, then D to detach
# Reattach anytime with: screen -r snapshot

# 5. Wait for completion (30-120 minutes)
# The script will automatically extract and verify

# 6. Start all services
docker compose up -d

# 7. Monitor startup
docker logs -f starknet-juno
```

## Method B: Resume Partial Download
Use this if you have a partial juno_mainnet.tar file:

```bash
# 1. Check if partial download exists
ls -lh data/juno/juno_mainnet.tar

# 2. If file exists, resume download
./resume-snapshot.sh
# This continues from where it stopped
# Automatically retries on failures

# 3. After completion, restart services
docker compose restart

# 4. Monitor
docker logs -f starknet-juno
```

## Method C: Quick Reset Using Maintenance Script
Simplest but less control:

```bash
# Force fresh snapshot and reset Juno
./maintenance.sh reset-juno

# OR with force update
./maintenance.sh force-update
```

### Step 4: Verify Recovery

Check Juno is syncing:
```bash
# Get current block
curl -s http://localhost:6060 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"starknet_blockNumber","params":[],"id":1}'

# Check overall status
./maintenance.sh status

# Monitor validator
docker logs --tail 50 starknet-validator

# Watch sync progress
watch -n 10 'docker logs --tail 5 starknet-juno | grep block'
```

### Step 5: Monitor Grafana

Open in browser: `http://[validator-ip]:3001`
- Username: admin
- Password: admin

## Troubleshooting

### If download keeps failing:
```bash
# Install wget if not present
sudo apt-get update && sudo apt-get install -y wget screen

# Try direct wget with resume
cd data/juno
wget -c --tries=0 --retry-connrefused \
     https://juno-snapshots.nethermind.io/files/mainnet/latest \
     -O juno_mainnet.tar
```

### If Juno won't start after snapshot:
```bash
# Check logs for errors
docker logs starknet-juno | grep ERROR

# Verify Ethereum RPC is working
curl -s $ETHEREUM_RPC_PRIMARY \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Check disk space
df -h data/

# Check file permissions
ls -la data/juno/
```

### If validator won't connect to Juno:
```bash
# Ensure Juno is fully synced first
# Validator needs Juno to be within a few blocks of chain tip

# Check connection
docker exec starknet-validator curl -s http://juno:6060/health

# Restart validator after Juno syncs
docker restart starknet-validator
```

## Expected Timeline

1. **Snapshot Download**: 30-120 minutes (200GB)
2. **Extraction**: 10-15 minutes
3. **Juno Initial Sync**: 2-4 hours to catch up
4. **Validator Attestations Resume**: Once Juno is synced

Total recovery time: 3-6 hours

## Prevention

After recovery, set up weekly snapshot refresh:
```bash
# Add to crontab on validator
crontab -e

# Add this line (runs Sundays at 3 AM)
0 3 * * 0 cd /path/to/starknet_staking && FORCE_SNAPSHOT=true docker compose up juno-snapshot
```

## Quick Commands Reference

```bash
# Stop everything
docker compose down

# Clean Juno
rm -rf data/juno/*

# Download snapshot
screen -S snapshot ./manual-snapshot-download.sh

# Start services
docker compose up -d

# Check status
./maintenance.sh status

# Monitor logs
docker logs -f starknet-juno
```