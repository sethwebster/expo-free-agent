# Base Image Verification Checklist

Complete checklist to verify the new base image (v0.1.23) with auto-update and log streaming.

## Prerequisites

- [ ] Controller running locally (`bun controller:dev` or `bun controller`)
- [ ] Controller API key available (check startup logs or `.env`)
- [ ] Image pushed to GHCR at `ghcr.io/sethwebster/expo-free-agent-base:0.1.23`

## Step 1: Image Pull Verification

### Pull the Image

```bash
# Pull specific version
/opt/homebrew/bin/tart pull ghcr.io/sethwebster/expo-free-agent-base:0.1.23

# Verify it exists
/opt/homebrew/bin/tart list | grep expo-free-agent-base
```

**Expected Output:**
```
ghcr.io/sethwebster/expo-free-agent-base:0.1.23  [size] [date]
```

- [ ] Image downloads successfully
- [ ] Image appears in `tart list`

## Step 2: VM Boot and Auto-Update

### Clone for Testing

```bash
# Clone to test instance
/opt/homebrew/bin/tart clone ghcr.io/sethwebster/expo-free-agent-base:0.1.23 test-vm-verify

# Start without env vars to test basic boot
/opt/homebrew/bin/tart run test-vm-verify &

# Wait 30 seconds for boot
sleep 30
```

- [ ] VM clones successfully
- [ ] VM boots without errors

### Check Auto-Update Log

```bash
# Check auto-update ran on boot
/opt/homebrew/bin/tart exec test-vm-verify -- cat /tmp/free-agent-auto-update.log
```

**Expected Output:**
```
[timestamp] ==========================================
[timestamp] Expo Free Agent - Auto Update
[timestamp] ==========================================
[timestamp] Current version: 0.1.23
[timestamp] Already on latest version (0.1.23), skipping update
...
```

- [ ] Auto-update log exists
- [ ] Version is 0.1.23
- [ ] No errors in auto-update log

### Verify Scripts Installed

```bash
# Check all scripts present
/opt/homebrew/bin/tart exec test-vm-verify -- ls -lh /usr/local/bin/free-agent-*
/opt/homebrew/bin/tart exec test-vm-verify -- ls -lh /usr/local/bin/vm-monitor.sh
/opt/homebrew/bin/tart exec test-vm-verify -- ls -lh /usr/local/bin/install-signing-certs
```

**Expected Output:**
```
-rwxr-xr-x  1 admin  staff   [size]  free-agent-auto-update
-rwxr-xr-x  1 admin  staff   [size]  free-agent-vm-bootstrap
-rwxr-xr-x  1 admin  staff   [size]  free-agent-run-job
-rwxr-xr-x  1 admin  staff   [size]  vm-monitor.sh
-rwxr-xr-x  1 admin  staff   [size]  install-signing-certs
```

- [ ] All scripts present
- [ ] All scripts executable

### Check Version File

```bash
/opt/homebrew/bin/tart exec test-vm-verify -- cat /usr/local/etc/free-agent-version
```

**Expected Output:**
```
0.1.23
```

- [ ] Version file exists
- [ ] Version matches 0.1.23

### Stop Test VM

```bash
/opt/homebrew/bin/tart stop test-vm-verify
```

- [ ] VM stops cleanly

## Step 3: Bootstrap Process with Env Vars

### Get Controller API Key

```bash
# From controller startup logs, or:
grep CONTROLLER_API_KEY packages/controller/.env 2>/dev/null || echo "Use: dev-insecure-key-change-in-production"
```

**Your Controller URL:** `http://localhost:3000` (or your deployed URL)
**Your API Key:** `________________` (write it here)

### Start VM with Bootstrap Env Vars

```bash
# Set your values
CONTROLLER_URL="http://localhost:3000"
API_KEY="your-api-key-here"
BUILD_ID="verify-test-$(date +%s)"
WORKER_ID="verify-worker"

# Start VM with env vars
/opt/homebrew/bin/tart run test-vm-verify \
  --env BUILD_ID=$BUILD_ID \
  --env WORKER_ID=$WORKER_ID \
  --env API_KEY=$API_KEY \
  --env CONTROLLER_URL=$CONTROLLER_URL &

# Wait for bootstrap
sleep 45
```

- [ ] VM starts with env vars
- [ ] No immediate errors

### Monitor Bootstrap Process

```bash
# Check bootstrap log
/opt/homebrew/bin/tart exec test-vm-verify -- cat /tmp/free-agent-bootstrap.log
```

**Expected Output:**
```
==========================================
Expo Free Agent - VM Bootstrap
==========================================
Phase 1: Randomizing admin password...
✓ Admin password randomized (32 bytes)
✓ SSH authorized_keys removed
...
Phase 2: Validating environment variables...
✓ BUILD_ID: verify-test-...
✓ WORKER_ID: verify-worker
✓ API_KEY: [REDACTED]
✓ CONTROLLER_URL: http://localhost:3000
Phase 3: Fetching signing certificates...
...
✓ Bootstrap complete! VM ready for builds.
==========================================
```

**Common Issues:**
- If "Certificates not found (HTTP 404)": Expected - no actual build in controller yet
- If "Worker not authorized (HTTP 403)": Check API key matches controller
- If bootstrap hangs: Check controller is accessible from VM

- [ ] Bootstrap log shows Phase 1 complete (password randomized)
- [ ] Bootstrap log shows Phase 2 complete (env vars validated)
- [ ] Phase 3 attempts cert fetch (404 is OK for this test)
- [ ] Ready signal created (check next)

### Check Ready Signal

```bash
/opt/homebrew/bin/tart exec test-vm-verify -- test -f /tmp/free-agent-ready && echo "✓ Ready!" || echo "✗ Not ready"
```

**Expected Output:**
```
✓ Ready!
```

- [ ] Ready signal exists

### Verify SSH is Blocked

```bash
# Get VM IP
VM_IP=$(/opt/homebrew/bin/tart ip test-vm-verify)
echo "VM IP: $VM_IP"

# Try SSH (should fail)
ssh -o ConnectTimeout=5 admin@$VM_IP echo "SSH works" 2>&1 || echo "✓ SSH blocked as expected"
```

**Expected Output:**
```
✓ SSH blocked as expected
```

- [ ] SSH connection is refused/fails (password randomized)

### Stop Test VM

```bash
/opt/homebrew/bin/tart stop test-vm-verify
```

- [ ] VM stops cleanly

## Step 4: Build Execution Test

### Start Controller

```bash
# In controller directory
bun controller:dev
```

**Expected Output:**
```
🚀 Expo Free Agent Controller
📍 Server:   http://localhost:3000
🔐 API Key:  dev-inse...
```

- [ ] Controller running on port 3000
- [ ] API key visible in logs

### Submit Test Build

```bash
# Create minimal test project
cd /tmp
mkdir -p test-expo-app
cd test-expo-app

# Create package.json
cat > package.json << 'EOF'
{
  "name": "test-app",
  "version": "1.0.0",
  "main": "index.js"
}
EOF

# Create index.js
echo "console.log('Hello');" > index.js

# Create tarball
tar -czf ../test-source.tar.gz .

# Submit build
cd ..
curl -X POST http://localhost:3000/api/builds/submit \
  -H "X-API-Key: your-api-key-here" \
  -F "source=@test-source.tar.gz" \
  -F "platform=ios"
```

**Expected Response:**
```json
{
  "id": "abc123...",
  "status": "pending",
  "submitted_at": 1234567890,
  "access_token": "..."
}
```

**Save these values:**
- Build ID: `________________`
- Access Token: `________________`

- [ ] Build submitted successfully
- [ ] Got build ID and access token

### Start Worker VM

```bash
# Using the image
CONTROLLER_URL="http://localhost:3000"
API_KEY="your-api-key-here"
BUILD_ID="<build-id-from-above>"
WORKER_ID="verify-worker"

/opt/homebrew/bin/tart run test-vm-verify \
  --env BUILD_ID=$BUILD_ID \
  --env WORKER_ID=$WORKER_ID \
  --env API_KEY=$API_KEY \
  --env CONTROLLER_URL=$CONTROLLER_URL &
```

- [ ] VM starts with build env vars

### Monitor Build Logs in Real-Time

In a **new terminal**, watch the build logs stream:

```bash
# Using CLI
npx @sethwebster/expo-free-agent@latest logs <build-id> --follow

# Or using curl
BUILD_ID="<your-build-id>"
while true; do
  curl -s http://localhost:3000/api/builds/$BUILD_ID/logs \
    -H "X-API-Key: your-api-key" | jq -r '.logs[] | "\(.timestamp) [\(.level)] \(.message)"'
  sleep 2
done
```

**Expected Output (streaming):**
```
[INFO] === Free Agent Build Runner ===
[INFO] Starting at: ...
[INFO] Node: v20.x.x
[INFO] Xcode: Xcode 15.x
[INFO] Extracting source...
[INFO] ✓ Source extracted
[INFO] Installing dependencies...
...
```

- [ ] Logs appear in real-time
- [ ] Log levels show (info/warn/error)
- [ ] Build progresses through stages

### Check VM Monitor

```bash
# Check monitor is running
/opt/homebrew/bin/tart exec test-vm-verify -- ps aux | grep vm-monitor
```

**Expected Output:**
```
admin  [pid]  ... /usr/local/bin/vm-monitor.sh /tmp/monitor-creds-...
```

- [ ] VM monitor process running

### Verify Controller Receives Logs

Check controller terminal for log POST requests:

**Expected Output:**
```
POST /api/builds/<build-id>/logs 200 [time]
POST /api/builds/<build-id>/logs 200 [time]
...
```

- [ ] Controller receiving log POST requests
- [ ] All requests return 200 status

### Check Build Status

```bash
BUILD_ID="<your-build-id>"
curl http://localhost:3000/api/builds/$BUILD_ID/status \
  -H "X-API-Key: your-api-key" | jq
```

**Expected Output:**
```json
{
  "id": "...",
  "status": "building",
  "platform": "ios",
  "submitted_at": ...,
  "started_at": ...,
  "worker_id": "verify-worker"
}
```

- [ ] Build status shows "building"
- [ ] Worker ID assigned
- [ ] Timestamps populated

### Wait for Completion

Monitor until build completes (or fails - expected for minimal test app):

```bash
# Keep checking status
while true; do
  STATUS=$(curl -s http://localhost:3000/api/builds/$BUILD_ID/status \
    -H "X-API-Key: your-api-key" | jq -r '.status')
  echo "Status: $STATUS"
  [[ "$STATUS" == "completed" || "$STATUS" == "failed" ]] && break
  sleep 10
done
```

- [ ] Build completes or fails (expected to fail for test app)
- [ ] Final status is "completed" or "failed"

### Review Final Logs

```bash
curl http://localhost:3000/api/builds/$BUILD_ID/logs \
  -H "X-API-Key: your-api-key" | jq -r '.logs[] | "[\(.level)] \(.message)"' | tail -20
```

**Expected Output:**
```
[INFO] ✓ Source extracted
[INFO] Installing dependencies...
[ERROR] Build failed: ...
```

- [ ] Complete log history available
- [ ] Logs show entire build process

## Step 5: Auto-Update Test

Test that VMs actually auto-update when scripts change.

### Simulate Script Update

```bash
# On host, update VERSION file
cd vm-setup
echo "0.1.24-test" > VERSION

# Package scripts
./package-vm-scripts.sh

# Create test release (or upload to existing)
gh release create v0.1.24-test vm-scripts.tar.gz --prerelease \
  --title "Test Auto-Update" \
  --notes "Testing auto-update mechanism"
```

- [ ] Test release created with v0.1.24-test

### Restart VM and Check Update

```bash
# Stop VM
/opt/homebrew/bin/tart stop test-vm-verify

# Update the installer URL env var (optional, or edit install.sh temporarily)
# Restart with latest version
/opt/homebrew/bin/tart run test-vm-verify &

sleep 30

# Check auto-update log
/opt/homebrew/bin/tart exec test-vm-verify -- cat /tmp/free-agent-auto-update.log | tail -20
```

**Expected Output:**
```
Current version: 0.1.23
New version: 0.1.24-test
Installing updated scripts...
✓ All scripts installed
✓ Version file updated: 0.1.24-test
Auto-update complete! (0.1.23 -> 0.1.24-test)
```

- [ ] Auto-update detects new version
- [ ] Scripts update successfully
- [ ] Version file reflects new version

### Verify Updated Scripts

```bash
/opt/homebrew/bin/tart exec test-vm-verify -- cat /usr/local/etc/free-agent-version
```

**Expected Output:**
```
0.1.24-test
```

- [ ] Version file shows 0.1.24-test

### Cleanup Test Release

```bash
# Delete test release
gh release delete v0.1.24-test --yes

# Reset VERSION file
cd vm-setup
echo "0.1.23" > VERSION
```

- [ ] Test release cleaned up

## Step 6: Cleanup

### Stop and Remove Test VM

```bash
/opt/homebrew/bin/tart stop test-vm-verify
/opt/homebrew/bin/tart delete test-vm-verify
```

- [ ] Test VM removed

### Optional: Clean Test Build

```bash
# Clean up test build from controller
rm -rf /tmp/test-expo-app /tmp/test-source.tar.gz
```

- [ ] Test files cleaned up

## Verification Complete! ✓

All checks passed means your base image is working correctly with:

✅ Auto-update system (pulls latest scripts from releases)
✅ Build log streaming (real-time logs to controller)
✅ Bootstrap with env vars (certs fetch, password randomization)
✅ VM monitor (heartbeats to controller)
✅ Secure execution (SSH blocked after bootstrap)

## Common Issues and Solutions

### Bootstrap Fails: "Missing environment variables"

**Problem:** VM not receiving env vars
**Solution:** Ensure you're using `tart run --env KEY=VALUE` syntax

### Bootstrap Fails: "Failed to fetch certificates (HTTP 403)"

**Problem:** API key mismatch
**Solution:** Verify `API_KEY` env var matches controller's `CONTROLLER_API_KEY`

### Bootstrap Fails: "Failed to fetch certificates (HTTP 404)"

**Problem:** No certs uploaded for this build (expected for test builds)
**Solution:** For real builds, submit with `--cert` and `--profile` flags in CLI

### Auto-Update Fails: "Download failed"

**Problem:** vm-scripts.tar.gz not uploaded to release
**Solution:** Run `./package-vm-scripts.sh && gh release upload vX.Y.Z vm-scripts.tar.gz`

### Logs Not Streaming

**Problem:** Worker can't reach controller
**Solution:**
- Check `CONTROLLER_URL` is accessible from VM
- Test: `/opt/homebrew/bin/tart exec test-vm-verify -- curl -I $CONTROLLER_URL`
- For localhost, use host IP (not 127.0.0.1): `http://192.168.1.x:3000`

### SSH Still Works After Bootstrap

**Problem:** Bootstrap didn't run or failed
**Solution:** Check `/tmp/free-agent-bootstrap.log` for errors

### Scripts Not Updating

**Problem:** Auto-update not detecting new version
**Solution:**
- Check version in `vm-setup/VERSION` matches release tag
- Verify `vm-scripts.tar.gz` uploaded to release
- Check `/tmp/free-agent-auto-update.log` for errors

## Next Steps

After verification passes:

1. **Update Documentation:** Confirm SETUP_LOCAL.md and SETUP_REMOTE.md reference v0.1.23
2. **Worker Deployment:** Deploy workers with new base image
3. **Monitor Production:** Watch for auto-updates in production VMs
4. **Iterate Fast:** Push script updates via releases without rebuilding base image
