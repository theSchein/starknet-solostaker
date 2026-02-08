# Validator Deployment Procedure

## Current Situation
- Validator is running with old Juno data (July 2025)
- Services are active but not attesting
- Need to deploy fixes and refresh Juno data

## Step-by-Step Deployment Procedure

### Step 1: On Dev Machine (This machine)
```bash
# Commit the fixes
git add -A
git commit -m "Fix validator attestation - force fresh Juno snapshot"
git push
```

### Step 2: On Validator Machine - Initial Backup
```bash
# SSH to validator
cd /path/to/starknet_staking

# Create safety backup of current state
./maintenance.sh backup
# OR if you want to skip the lengthy data backup:
mkdir -p backups
cp -r config backups/config_$(date +%Y%m%d_%H%M%S)
cp .env backups/.env_$(date +%Y%m%d_%H%M%S)
```

### Step 3: Pull Latest Code
```bash
# Pull the fixes from repository
git pull

# Verify the changes arrived
grep "FORCE_SNAPSHOT" docker-compose.yml  # Should see new logic
grep "disable-l1-verification" config/juno.yaml  # Should see "false"
```

### Step 4: Stop Current Services
```bash
# Check current status first
docker compose ps
docker logs --tail=20 starknet-juno

# Stop all services gracefully
docker compose down
```

### Step 5: Clean Old Juno Data
```bash
# Remove the old July 2025 Juno database
rm -rf /media/dov/ethdata/juno/*
rm -f /media/dov/ethdata/juno/.snapshot_downloaded

# Verify cleanup
ls -la /media/dov/ethdata/juno/
# Should be empty
```

### Step 6: Pull New Docker Images
```bash
# Pull latest images (especially important for Juno)
docker compose pull
```

### Step 7: Start Services with Fresh Snapshot
```bash
# Method A: Use the reset script (Recommended)
./reset-juno.sh

# OR Method B: Manual with force flag
export FORCE_SNAPSHOT=true
docker compose up -d juno-snapshot

# Monitor snapshot download progress
docker logs -f starknet-juno-snapshot
# Wait for: "Snapshot downloaded and extracted successfully!"
# This will take 30-60 minutes for ~200GB

# Once snapshot is ready, start all services
docker compose up -d
```

### Step 8: Verify Services Are Running
```bash
# Check all containers are up
docker compose ps

# Check Juno is syncing
docker logs --tail=50 starknet-juno
curl -s http://localhost:6060 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"starknet_blockNumber","params":[],"id":1}'

# Check validator is connected
docker logs --tail=50 starknet-validator

# Check metrics endpoint
curl http://localhost:8081/metrics | grep starknet
```

### Step 9: Monitor Sync Progress
```bash
# Watch Juno sync progress
watch -n 30 'docker logs --tail=5 starknet-juno | grep -i block'

# Check Grafana dashboard
# Open browser to http://[validator-ip]:3001
```

## Alternative: Minimal Downtime Approach

If you want to minimize downtime, you can download the snapshot first:

```bash
# 1. Pull latest code
git pull

# 2. Download snapshot while services still running
docker run --rm -v /media/dov/ethdata/juno-new:/var/lib/juno \
  curlimages/curl:latest sh -c \
  "curl -o /var/lib/juno/juno_mainnet.tar https://juno-snapshots.nethermind.io/files/mainnet/latest && \
   tar -xf /var/lib/juno/juno_mainnet.tar -C /var/lib/juno && \
   rm /var/lib/juno/juno_mainnet.tar"

# 3. Quick switch
docker compose down
mv /media/dov/ethdata/juno /media/dov/ethdata/juno-old
mv /media/dov/ethdata/juno-new /media/dov/ethdata/juno
docker compose up -d
```

## Expected Timeline

1. **Code deployment**: 2-5 minutes
2. **Snapshot download**: 30-60 minutes (depends on bandwidth)
3. **Juno initial sync**: 2-4 hours to catch up
4. **Attestation resume**: Once Juno is synced

## Rollback Plan (If needed)

If something goes wrong:

```bash
# Stop services
docker compose down

# Restore configs
cp backups/config_[timestamp]/* config/
cp backups/.env_[timestamp] .env

# Restore old Juno data (if backed up)
rm -rf /media/dov/ethdata/juno/*
# restore from backup if available

# Start with old version
git checkout HEAD~1
docker compose up -d
```

## Success Indicators

✅ Juno block number increasing steadily
✅ No ERROR messages in validator logs
✅ Metrics showing attestation attempts
✅ Validator appearing as active on chain

## Troubleshooting

### If snapshot download fails:
- Check disk space: `df -h /media/dov/ethdata`
- Check network: `curl -I https://juno-snapshots.nethermind.io`
- Retry: `FORCE_SNAPSHOT=true docker compose up juno-snapshot`

### If Juno won't start:
- Check logs: `docker logs starknet-juno`
- Verify Ethereum RPC in .env is valid
- Check permissions: `ls -la /media/dov/ethdata/juno`

### If validator won't connect:
- Ensure Juno is synced: Check block number
- Verify keys in .env match on-chain registration
- Check firewall allows required ports