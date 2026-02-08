# Juno Snapshot Download Recovery Guide

## Current Situation
You have a partial 18GB download in `data/juno/juno_mainnet.tar` that failed with a network error.

## Solution Options

### Option 1: Quick Resume (Recommended)
Resume the existing 18GB download:

```bash
# This will continue from 18GB, not restart
./resume-snapshot.sh
```

This script:
- Automatically retries up to 10 times
- Resumes from where it stopped
- Handles connection interruptions
- Extracts automatically when complete

### Option 2: Stable Download with Screen/Tmux
For unreliable connections, use the manual script with screen:

```bash
# Start a screen session
screen -S snapshot

# Run the manual download (inside screen)
./manual-snapshot-download.sh

# Detach with Ctrl+A, D
# Reattach with: screen -r snapshot
```

Benefits:
- Survives SSH disconnections
- Uses wget (more robust than curl)
- Infinite retries
- Better progress monitoring

### Option 3: Download on Another Machine
If your validator has poor connectivity:

```bash
# On a machine with good internet:
wget -c https://juno-snapshots.nethermind.io/files/mainnet/latest \
     -O juno_mainnet.tar

# Transfer to validator:
rsync -avP juno_mainnet.tar validator:~/starknet_staking/data/juno/

# On validator, extract:
cd ~/starknet_staking/data/juno
tar -xf juno_mainnet.tar
rm juno_mainnet.tar
```

## After Successful Download

1. The snapshot will be extracted automatically
2. Start services:
   ```bash
   docker compose up -d
   ```

3. Monitor sync progress:
   ```bash
   docker logs -f starknet-juno
   ```

## Troubleshooting

### "Stream not closed cleanly" Error
This is a network interruption. Simply run `./resume-snapshot.sh` to continue.

### Download Keeps Failing
1. Check disk space: `df -h data/`
2. Try manual download with screen: `./manual-snapshot-download.sh`
3. Install wget for better stability: `sudo apt-get install wget`

### Very Slow Download
The snapshot is ~200GB. Expected times:
- 100 Mbps connection: ~4-5 hours
- 50 Mbps connection: ~9-10 hours
- 25 Mbps connection: ~18-20 hours

Consider downloading on a faster connection and transferring.

## Important Notes

- Your existing docker-compose.yml already has the correct logic to avoid re-downloading
- The download will RESUME from where it stopped (18GB in your case)
- Once extracted, the system won't download again unless forced or >7 days old
- The partial download in `data/juno/` is the correct location