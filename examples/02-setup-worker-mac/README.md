# Example 2: Set Up Worker on Spare Mac

Turn a spare Mac into a build worker that executes builds in isolated VMs.

## Hardware Requirements

**Minimum:**
- Mac with Apple Silicon (M1/M2/M3) or Intel (2015+)
- macOS 13.0+ (Ventura or later)
- 8 GB RAM
- 50 GB free disk space

**Recommended:**
- Mac Mini M2 or better
- 16 GB+ RAM
- 256 GB+ SSD
- Gigabit ethernet connection

## Step 1: Prepare the Mac

### Update macOS

```bash
# Check current version
sw_vers

# Update to latest (if needed)
# System Settings → General → Software Update
```

### Install Xcode Command Line Tools

```bash
# Install
xcode-select --install

# Verify
xcode-select -p
# Expected: /Library/Developer/CommandLineTools
```

### Install Homebrew (Optional but Recommended)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Verify
brew --version
```

## Step 2: Configure Energy Settings

Prevent Mac from sleeping during builds:

```bash
# Disable sleep while plugged in
sudo pmset -c sleep 0
sudo pmset -c displaysleep 10

# Verify settings
pmset -g
```

**Or via System Settings:**
1. System Settings → Energy Saver (or Battery)
2. Set "Turn display off after" to 10 minutes
3. Uncheck "Put hard disks to sleep"
4. Set "Prevent automatic sleeping" when power adapter is connected

## Step 3: Create Dedicated User (Optional)

For security, run worker as dedicated user:

```bash
# Create user via System Settings:
# System Settings → Users & Groups → Add User

# Or via command line:
sudo sysadminctl -addUser buildagent \
  -fullName "Build Agent" \
  -password "secure-password" \
  -admin

# Switch to new user
su - buildagent
```

## Step 4: Install Worker App

### Download and Install

```bash
# Method 1: NPM installer (recommended)
npx @sethwebster/expo-free-agent-worker@latest

# Method 2: Manual download
curl -L https://github.com/expo/expo-free-agent/releases/latest/download/FreeAgent.app.tar.gz -o FreeAgent.app.tar.gz
tar -xzf FreeAgent.app.tar.gz
sudo cp -R FreeAgent.app /Applications/
rm -rf FreeAgent.app FreeAgent.app.tar.gz
```

### Verify Installation

```bash
# Check app exists
ls -la /Applications/FreeAgent.app

# Verify code signature
codesign --verify --deep --strict /Applications/FreeAgent.app

# Check Gatekeeper approval
spctl --assess --type execute --verbose /Applications/FreeAgent.app
# Expected: accepted source=Notarized Developer ID
```

### Handle Gatekeeper Issues

If macOS blocks the app:

```bash
# Method 1: Remove quarantine (if app is trusted)
xattr -d com.apple.quarantine /Applications/FreeAgent.app

# Method 2: Approve in System Settings
# System Settings → Privacy & Security → Allow anyway

# Method 3: Run once to approve
open /Applications/FreeAgent.app
# Click "Open" in security dialog
```

## Step 5: Configure Worker

### Launch App

```bash
open /Applications/FreeAgent.app
```

A menu bar icon (⚡️) appears in the top-right.

### Connect to Controller

Click menu bar icon → **Configure**:

```
Controller URL: http://your-controller-ip:3000
API Key: [paste your controller API key]
Worker Name: mac-mini-office
```

**Finding Controller URL:**
```bash
# On controller machine
hostname -I  # Linux
ipconfig getifaddr en0  # macOS

# Or use public IP if controller is remote
```

Click **Save** and then **Connect**.

### Verify Connection

Status should show:
```
✅ Connected to controller
🔄 Polling for jobs (every 5 seconds)
💤 Idle - No builds assigned
```

## Step 6: Configure Build Environment

### Install Xcode (For iOS Builds)

```bash
# Download from App Store or developer.apple.com
# Install Xcode.app to /Applications

# Accept license
sudo xcodebuild -license accept

# Install additional components
sudo xcodebuild -runFirstLaunch

# Verify installation
xcodebuild -version
```

### Install Node.js & Bun

```bash
# Install Node.js
brew install node

# Verify
node --version
npm --version

# Install Bun
curl -fsSL https://bun.sh/install | bash

# Verify
bun --version
```

### Configure VM Resources

Click menu bar icon → **Preferences**:

```
Max VMs: 2
CPU Cores per VM: 4
Memory per VM: 8 GB
Build Timeout: 30 minutes
```

**Calculating resources:**
```
Your Mac has: 16 GB RAM, 8 CPU cores

Safe allocation:
- Max VMs: 2
- CPU per VM: 3 (leave 2 cores for macOS)
- RAM per VM: 6 GB (leave 4 GB for macOS)
```

## Step 7: Test First Build

Submit a test build from another machine:

```bash
# On your development machine
cd ~/test-expo-app
expo-build submit --platform ios
```

**On worker Mac**, monitor via menu bar:
```
⚡️ Building... (build-abc123)
   Progress: 45% - Installing dependencies
   Time: 3m 12s
```

**Check logs:**
Menu bar → **View Logs** → See real-time build output

## Step 8: Configure Auto-Start

### Add to Login Items

1. System Settings → General → Login Items
2. Click **+**
3. Select `/Applications/FreeAgent.app`
4. Enable "Hide" to start in menu bar

### Verify Auto-Start

```bash
# Restart Mac
sudo reboot

# After restart, check menu bar for ⚡️ icon
# Should auto-connect to controller
```

## Step 9: Monitor Worker Health

### Check Worker Status

```bash
# Via controller web UI
open http://your-controller-ip:3000

# Navigate to "Workers" tab
# Should see your worker with status: Online
```

### View Build History

Menu bar → **Build History**:
```
build-abc123  iOS  Success  12m 34s  2024-01-28 10:15
build-def456  iOS  Failed   5m 12s   2024-01-28 09:30
```

### Monitor Resource Usage

```bash
# CPU usage
top -l 1 | grep "CPU usage"

# Memory usage
vm_stat | perl -ne '/page size of (\d+)/ and $size=$1; /Pages\s+([^:]+)[^\d]+(\d+)/ and printf("%-16s % 16.2f MB\n", "$1:", $2 * $size / 1048576);'

# Disk space
df -h /

# Network usage (if needed)
nettop -l 1 -P
```

## Step 10: Optimize for Production

### Enable Firewall

```bash
# Enable firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on

# Allow FreeAgent.app
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /Applications/FreeAgent.app

# Verify
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
```

### Disable Unnecessary Services

```bash
# Disable Spotlight indexing (optional, for performance)
sudo mdutil -i off /

# Disable Time Machine (if not needed)
sudo tmutil disable

# Disable Screen Saver
defaults -currentHost write com.apple.screensaver idleTime 0
```

### Configure Log Rotation

```bash
# Limit log size
# Menu bar → Preferences → Logs
# Set: Max log size: 50 MB
# Set: Keep logs for: 7 days
```

### Set Up Monitoring Alerts

Configure notifications:
```bash
# Menu bar → Preferences → Notifications
# Enable: Build completed
# Enable: Build failed
# Enable: Worker disconnected
# Disable: Build started (too noisy)
```

## Troubleshooting

### Worker Not Connecting

**Check network:**
```bash
# Ping controller
ping your-controller-ip

# Test controller health endpoint
curl http://your-controller-ip:3000/health
```

**Check API key:**
```bash
# Verify API key matches controller
# Menu bar → Configure → API Key
# Compare with controller output
```

**Check logs:**
```bash
# Menu bar → View Logs
# Look for connection errors
```

### VM Creation Fails

**Error:** `Failed to create VM: Operation not permitted`

**Solution:**
```bash
# Grant FreeAgent.app full disk access
# System Settings → Privacy & Security → Full Disk Access
# Add FreeAgent.app
```

### Builds Timing Out

**Issue:** Builds exceed 30-minute timeout

**Solutions:**
```bash
# Increase timeout
# Menu bar → Preferences → Build Timeout: 60 minutes

# Or optimize build:
# - Use build cache
# - Pre-install dependencies in base VM image
# - Exclude unnecessary files in .gitignore
```

### High Memory Usage

**Issue:** Mac becomes slow during builds

**Solutions:**
```bash
# Reduce concurrent VMs
# Menu bar → Preferences → Max VMs: 1

# Reduce memory per VM
# Menu bar → Preferences → Memory per VM: 4 GB

# Close other applications during builds
```

## Maintenance

### Weekly Tasks

```bash
# 1. Check disk space
df -h

# 2. Clear old build caches
# Menu bar → Maintenance → Clear Build Caches

# 3. Update Xcode if available
# App Store → Updates

# 4. Check for worker updates
# Menu bar → Check for Updates
```

### Monthly Tasks

```bash
# 1. Update macOS
# System Settings → General → Software Update

# 2. Review build success rate
# Menu bar → Statistics

# 3. Optimize VM base image
# Menu bar → Maintenance → Rebuild Base Image

# 4. Check worker uptime
uptime
```

## Advanced: Multiple Workers

To run multiple workers on the same Mac:

```bash
# Not recommended - use separate Macs instead
# Each worker needs dedicated resources
# Better: Use one worker with multiple VM slots
```

## Cost Analysis

**Hardware:**
- Mac Mini M2 (8GB): $599
- Mac Mini M2 (16GB): $799
- Mac Mini M2 Pro (32GB): $1,299

**Operational:**
- Power: ~$2-5/month (24/7 operation)
- Internet: Existing connection (minimal traffic)
- Maintenance: 1-2 hours/month

**Break-even analysis:**
```
Cloud build service: $50/month for 500 builds
Mac Mini M2 setup: $599 + $5/month power

Break-even: 12 months
After 1 year: Save $540/year
```

## Next Steps

- **Set Up Multiple Workers:** Repeat for additional Macs
- **Configure Worker Pools:** Assign workers to specific projects
- **Enable Metrics:** Track build times and utilization
- **Set Up Alerts:** Get notified of worker issues

## Resources

- [Worker Configuration](../../docs/operations/worker-setup.md)
- [VM Setup Guide](../../docs/operations/vm-setup.md)
- [Troubleshooting](../../docs/operations/troubleshooting.md)

---

**Time to complete:** ~45 minutes
**Skill level:** Intermediate
**Ongoing time:** ~10 minutes/month (maintenance)
