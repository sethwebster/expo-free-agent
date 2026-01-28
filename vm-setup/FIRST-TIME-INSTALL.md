# First-Time Installation to Base VM Image

Step-by-step instructions to install VM agent scripts into your base Tart image for the first time.

## Prerequisites

- Base VM image running (e.g., `expo-free-agent-tahoe-26.2-xcode-expo-54`)
- VM has SSH access configured
- Homebrew installed in VM
- jq installed in VM (`brew install jq`)

## Option 1: Public Installer (Recommended)

This is the easiest method and allows you to update VMs in the wild without rebuilding the base image.

### Step 1: Start Your Base VM

```bash
tart run expo-free-agent-tahoe-26.2-xcode-expo-54
```

### Step 2: Get VM IP

In another terminal:

```bash
tart ip expo-free-agent-tahoe-26.2-xcode-expo-54
# Example output: 192.168.64.2
```

### Step 3: SSH Into VM

```bash
ssh admin@192.168.64.2
# Enter password when prompted
```

### Step 4: Run Public Installer

Inside the VM, run:

```bash
curl -fsSL https://raw.githubusercontent.com/sethwebster/expo-free-agent/main/vm-setup/install.sh | bash
```

Or with a specific version:

```bash
curl -fsSL https://raw.githubusercontent.com/sethwebster/expo-free-agent/main/vm-setup/install.sh | VERSION=v0.1.22 bash
```

**What this does:**
- Downloads vm-scripts.tar.gz from GitHub releases
- Installs all scripts to /usr/local/bin/
- Sets up LaunchDaemon for auto-update/bootstrap
- Verifies installation

### Step 5: Verify Installation

Still inside the VM:

```bash
# Check scripts are installed
ls -lh /usr/local/bin/free-agent*
ls -lh /usr/local/bin/vm-monitor.sh
ls -lh /usr/local/bin/install-signing-certs

# Check version
cat /usr/local/etc/free-agent-version

# Check LaunchDaemon
ls -lh /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist
```

### Step 6: Shutdown and Save

```bash
# Inside VM
sudo shutdown -h now
```

Wait for shutdown, then save the image:

```bash
# On host
tart stop expo-free-agent-tahoe-26.2-xcode-expo-54

# Clone to new name (optional but recommended)
tart clone expo-free-agent-tahoe-26.2-xcode-expo-54 expo-free-agent-tahoe-26.2-xcode-expo-54-v0.1.22
```

### Step 7: Test Bootstrap

```bash
# Start VM with test env vars
tart run expo-free-agent-tahoe-26.2-xcode-expo-54-v0.1.22 \
  --env BUILD_ID=test-123 \
  --env WORKER_ID=test-worker \
  --env API_KEY=test-key \
  --env CONTROLLER_URL=http://localhost:3000 &

# Wait for VM to boot
sleep 20

# Check bootstrap log
tart exec expo-free-agent-tahoe-26.2-xcode-expo-54-v0.1.22 -- tail -50 /tmp/free-agent-bootstrap.log

# Check for ready signal
tart exec expo-free-agent-tahoe-26.2-xcode-expo-54-v0.1.22 -- test -f /tmp/free-agent-ready && echo "✓ Bootstrap complete!"

# Cleanup
tart stop expo-free-agent-tahoe-26.2-xcode-expo-54-v0.1.22
```

## Option 2: Manual Installation (For Offline or Custom Builds)

Use the `install-to-vm-template.sh` script from the host machine:

```bash
# Make sure VM is stopped
tart stop expo-free-agent-tahoe-26.2-xcode-expo-54

# Run installer
cd vm-setup
./install-to-vm-template.sh expo-free-agent-tahoe-26.2-xcode-expo-54
```

This script will:
1. Start the VM
2. Copy all scripts via `tart exec`
3. Install scripts to /usr/local/bin/
4. Set up LaunchDaemon
5. Verify installation
6. Stop the VM

## Updating VMs in the Wild

The beauty of the public installer is you can update any running VM without rebuilding the base image:

### Update a Running Worker VM

```bash
# SSH into any worker VM
ssh admin@<vm-ip>

# Run installer to update scripts
curl -fsSL https://raw.githubusercontent.com/sethwebster/expo-free-agent/main/vm-setup/install.sh | bash

# Reboot to activate new version
sudo reboot
```

### Update via Tart (Without SSH)

```bash
# For a stopped VM
tart run vm-name &
sleep 10
tart exec vm-name -- bash -c "curl -fsSL https://raw.githubusercontent.com/sethwebster/expo-free-agent/main/vm-setup/install.sh | bash"
tart stop vm-name
```

## Auto-Update System

Once installed, VMs will automatically check for updates on boot:

1. VM boots → LaunchDaemon runs `/usr/local/bin/free-agent-auto-update`
2. Auto-update downloads `vm-scripts.tar.gz` from latest release
3. Compares version with `/usr/local/etc/free-agent-version`
4. Updates scripts if newer version available
5. Execs bootstrap script

**This means:**
- Workers always run latest scripts after reboot
- No need to rebuild base images for script updates
- Safe: Falls back to existing version if update fails

## Pushing Updated Base Image

After installation, push the updated base image to GHCR:

```bash
# Set auth
export TART_REGISTRY_USERNAME=sethwebster
export TART_REGISTRY_PASSWORD="$(gh auth token)"

# Push with version tag AND :latest
/opt/homebrew/bin/tart push expo-free-agent-tahoe-26.2-xcode-expo-54-v0.1.22 \
  ghcr.io/sethwebster/expo-free-agent-base:0.1.22 \
  ghcr.io/sethwebster/expo-free-agent-base:latest
```

## Troubleshooting

### Installer fails with 404

```
ERROR: Failed to download scripts from https://github.com/.../vm-scripts.tar.gz
```

**Solution:** Make sure vm-scripts.tar.gz is uploaded to the GitHub release:

```bash
# Package scripts
cd vm-setup
./package-vm-scripts.sh

# Upload to release
gh release upload v0.1.22 vm-scripts.tar.gz
```

### LaunchDaemon doesn't run on boot

Check if it's loaded:

```bash
sudo launchctl list | grep free-agent
```

If not loaded:

```bash
sudo launchctl load /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist
```

### Scripts not updating

Check auto-update log:

```bash
cat /tmp/free-agent-auto-update.log
```

Check version:

```bash
cat /usr/local/etc/free-agent-version
```

Force update:

```bash
sudo rm /usr/local/etc/free-agent-version
sudo reboot
```

### Bootstrap fails

Check bootstrap log:

```bash
cat /tmp/free-agent-bootstrap.log
```

Common issues:
- Missing env vars: Make sure BUILD_ID, WORKER_ID, API_KEY, CONTROLLER_URL are passed via `tart run --env`
- Certificate fetch fails: Check controller is accessible from VM
- jq not installed: `brew install jq` inside VM

## Summary

**Quickstart:**
```bash
# Inside your base VM:
curl -fsSL https://raw.githubusercontent.com/sethwebster/expo-free-agent/main/vm-setup/install.sh | bash

# Then shutdown and save
sudo shutdown -h now
```

**Update any VM:**
```bash
# Same command works for updates:
curl -fsSL https://raw.githubusercontent.com/sethwebster/expo-free-agent/main/vm-setup/install.sh | bash
```

The installer is idempotent and safe to run multiple times.
