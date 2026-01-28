# VM Base Image Setup - Build Monitoring

This guide explains what to add to your Tart VM base image to enable build monitoring and health checks.

## Overview

The monitoring system has two layers:

1. **External Health Checks** - Worker verifies VM is responsive before starting build
2. **Internal Build Monitor** - Script inside VM sends heartbeats during build

This prevents builds from getting stuck when VMs freeze/crash.

## What to Add to VM Base Image

### 1. Install Build Monitor Script

Copy `vm-monitor.sh` into the VM:

```bash
# SSH into your Tart VM
tart run <vm-name> --no-graphics

# Create monitoring directory
mkdir -p /usr/local/bin

# Copy monitor script (from host)
# On host:
tart run <vm-name> --no-graphics --dir=$(pwd):/host
# Inside VM:
cp /host/vm-monitor.sh /usr/local/bin/vm-monitor.sh
chmod +x /usr/local/bin/vm-monitor.sh
```

Or add during VM provisioning:

```bash
# In your VM setup script
cat > /usr/local/bin/vm-monitor.sh << 'EOF'
#!/bin/bash
# ... paste contents of vm-monitor.sh ...
EOF

chmod +x /usr/local/bin/vm-monitor.sh
```

### 2. Install curl (if not present)

```bash
# macOS VMs usually have curl, but verify:
which curl

# If missing:
brew install curl
```

### 3. Enable SSH Access

The worker needs SSH access to:
- Verify VM is responsive
- Start the monitor script
- Check disk space
- Monitor processes

```bash
# Enable Remote Login in System Preferences
sudo systemsetup -setremotelogin on

# Verify SSH is running
sudo launchctl list | grep ssh

# Set up SSH key authentication
# On host (worker machine):
ssh-keygen -t ed25519 -f ~/.ssh/tart_vm_key -N ""

# Copy public key to VM
ssh-copy-id -i ~/.ssh/tart_vm_key user@<vm-ip>

# Or manually:
# Inside VM:
mkdir -p ~/.ssh
chmod 700 ~/.ssh
# Paste public key into ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 4. Configure Passwordless SSH

For automated health checks, SSH must work without password:

```bash
# Test from worker host:
ssh -i ~/.ssh/tart_vm_key -o BatchMode=yes user@<vm-ip> "echo alive"

# Should print "alive" without prompting for password
```

### 5. Install Build Dependencies

Ensure VM has all tools needed for builds:

```bash
# iOS builds
xcode-select --install
sudo xcodebuild -license accept

# Expo/React Native
brew install node
npm install -g eas-cli expo-cli

# Fastlane (for iOS signing)
brew install fastlane
```

### 6. Optimize for Builds

```bash
# Disable sleep
sudo pmset -a sleep 0
sudo pmset -a displaysleep 0

# Disable screen saver
defaults -currentHost write com.apple.screensaver idleTime 0

# Disable automatic updates
sudo softwareupdate --schedule off
```

### 7. Create Snapshot

Once configured, create a clean snapshot:

```bash
# Stop VM
tart stop <vm-name>

# Create snapshot
tart clone <vm-name> <vm-name>-base-snapshot

# This becomes your base image for builds
```

## Worker Configuration

Update worker to use SSH for health checks:

### Worker Config File

`~/.expo-worker/config.json`:

```json
{
  "vmName": "expo-build-vm",
  "vmUser": "builder",
  "vmSshKey": "~/.ssh/tart_vm_key",
  "vmIp": "192.168.64.2",
  "controllerUrl": "https://builds.example.com",
  "apiKey": "your-api-key"
}
```

## How It Works

### Build Flow with Monitoring

```
1. Worker receives build from controller
2. Worker performs health checks:
   - tart list | grep <vm-name>           # VM exists?
   - tart ip <vm-name>                    # VM has IP?
   - ssh <vm> "echo alive"                # VM responds?
   - ssh <vm> "df -h /"                   # VM has space?
3. Worker starts VM monitor inside VM:
   - ssh <vm> "/usr/local/bin/vm-monitor.sh <controller> <build-id> <worker-id> <api-key> &"
4. Worker starts build
5. Monitor sends heartbeat every 30s
6. If heartbeat stops for 2 minutes → controller marks build as failed
7. Worker stops monitor when build completes
```

### Heartbeat Payload

```json
{
  "progress": 45
}
```

Progress is optional - can be calculated from:
- Xcode build output
- Fastlane progress
- Custom build scripts

## Testing

### Test SSH Access

```bash
# From worker host
ssh -i ~/.ssh/tart_vm_key user@192.168.64.2 "echo alive"
```

Expected: `alive`

### Test Monitor Script

```bash
# Start VM
tart run <vm-name> --no-graphics

# SSH into VM
ssh -i ~/.ssh/tart_vm_key user@192.168.64.2

# Inside VM, test monitor
/usr/local/bin/vm-monitor.sh \
  http://localhost:3000 \
  test-build-123 \
  test-worker-456 \
  test-api-key \
  10  # 10 second interval for testing
```

Expected:
```
[VM Monitor] Starting for build test-build-123
[VM Monitor] Sending heartbeats every 10s to http://localhost:3000
[VM Monitor] Heartbeat sent (progress: 0%)
[VM Monitor] Heartbeat sent (progress: 5%)
...
```

### Test Health Checks

```bash
# Check VM is running
tart list

# Check VM IP
tart ip <vm-name>

# Check SSH
timeout 5 ssh -i ~/.ssh/tart_vm_key user@$(tart ip <vm-name>) "echo alive"

# Check disk
timeout 5 ssh -i ~/.ssh/tart_vm_key user@$(tart ip <vm-name>) "df -h /"
```

## Security Notes

### SSH Key Security

```bash
# Key should be worker-specific, not your personal key
chmod 600 ~/.ssh/tart_vm_key

# Use restricted authorized_keys in VM:
# ~/.ssh/authorized_keys:
command="/usr/local/bin/vm-monitor.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAA...
```

### API Key Security

- Never hardcode API keys in VM image
- Pass as parameter when starting monitor
- Rotate keys quarterly

### Network Isolation

- VMs should only access controller, not internet
- Use firewall rules to restrict outbound connections
- Block access to AWS metadata endpoint (169.254.169.254)

## Troubleshooting

### Monitor not sending heartbeats

```bash
# Check if monitor is running in VM
ssh user@<vm-ip> "ps aux | grep vm-monitor"

# Check if curl works
ssh user@<vm-ip> "curl -v <controller-url>/health"

# Check network connectivity
ssh user@<vm-ip> "ping -c 1 <controller-host>"
```

### SSH connection fails

```bash
# Check SSH is running in VM
ssh user@<vm-ip> "sudo launchctl list | grep ssh"

# Check firewall
ssh user@<vm-ip> "sudo pfctl -sr | grep ssh"

# Check authorized_keys permissions
ssh user@<vm-ip> "ls -la ~/.ssh/authorized_keys"
```

### Build times out despite monitor running

- Check controller logs for heartbeat receipts
- Verify API key matches between worker and controller
- Check worker_id in heartbeat matches assigned worker

### VM freezes during build

This is what monitoring detects! Controller will:
1. Notice missing heartbeats (2 min timeout)
2. Mark build as failed
3. Mark worker as idle
4. Allow worker to restart VM and pick up next build

## Advanced: Real Progress Tracking

For accurate progress instead of estimates, parse build output:

```bash
#!/bin/bash
# advanced-monitor.sh

# Monitor Xcode build log
tail -f /tmp/build.log | while read line; do
  # Parse progress from Xcode output
  if echo "$line" | grep -q "Building target"; then
    # Calculate progress based on target count
    progress=...
    send_heartbeat "$progress"
  fi
done
```

Or use Fastlane lanes:

```ruby
# Fastfile
lane :build do
  increment_version_number
  send_heartbeat(10)

  match(type: "appstore")
  send_heartbeat(30)

  gym
  send_heartbeat(90)

  send_heartbeat(100)
end
```

## Next Steps

1. Configure VM base image with monitor script
2. Set up SSH key authentication
3. Update worker to run health checks
4. Test with real build
5. Monitor controller logs for heartbeats
6. Tune timeout values based on average build times
