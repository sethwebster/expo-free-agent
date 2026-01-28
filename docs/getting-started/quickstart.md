# Free Agent Quick Start

Get your first iOS build running in 30 minutes.

## Prerequisites

- macOS 14+ on Apple Silicon
- Xcode 15+ installed
- 100GB free disk space
- Fast internet connection

## Step 1: Build the App (2 minutes)

```bash
cd /Users/sethwebster/Development/expo/expo-free-agent/free-agent
swift build -c release
```

The compiled app will be at: `.build/release/FreeAgent`

## Step 2: Create VM (60 minutes)

```bash
cd /Users/sethwebster/Development/expo/expo-free-agent/vm-setup

# Generate SSH keys
./setup-ssh.sh

# Create VM (this takes 30-60 minutes)
./create-macos-vm.sh my-builder 80
```

While the VM is installing, grab coffee. macOS installation is slow.

## Step 3: Configure VM (10 minutes)

Boot the VM using UTM or another method, then inside the VM:

```bash
# Install Xcode tools
xcode-select --install

# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Node.js and EAS
brew install node
npm install -g eas-cli

# Enable SSH
sudo systemsetup -setremotelogin on

# Create build user
sudo dscl . -create /Users/builder
sudo dscl . -create /Users/builder UserShell /bin/bash
sudo dscl . -create /Users/builder RealName "Build User"
sudo dscl . -create /Users/builder UniqueID 502
sudo dscl . -create /Users/builder PrimaryGroupID 20
sudo dscl . -create /Users/builder NFSHomeDirectory /Users/builder
sudo createhomedir -c -u builder

# Set up SSH key (paste your public key)
sudo mkdir -p /Users/builder/.ssh
sudo nano /Users/builder/.ssh/authorized_keys
# Paste contents of ~/.ssh/free_agent_ed25519.pub (from host)
sudo chown -R builder:staff /Users/builder/.ssh
sudo chmod 700 /Users/builder/.ssh
sudo chmod 600 /Users/builder/.ssh/authorized_keys

# Shut down
sudo shutdown -h now
```

## Step 4: Test SSH (30 seconds)

From your host machine:

```bash
ssh -i ~/.ssh/free_agent_ed25519 builder@192.168.64.2 "echo 'Connected!'"
```

If you see "Connected!", you're ready to build!

## Step 5: Run Free Agent (1 minute)

```bash
cd /Users/sethwebster/Development/expo/expo-free-agent/free-agent
.build/release/FreeAgent
```

A menu bar icon appears. Click it and:
1. Click "Settings"
2. Enter controller URL (placeholder for now)
3. Click "Start Worker"

## Architecture Summary

```
You → Controller → Worker → VM → Xcode → IPA
      (Node.js)  (Swift)  (macOS)  (iOS)
```

**Flow:**
1. Submit project to controller: `expo-controller submit ./my-app`
2. Controller queues build job
3. Worker polls controller, gets job
4. Worker starts VM (30-60s)
5. Worker copies source code to VM
6. Worker installs certificates in VM
7. Worker runs build in VM: `npm install && pod install && eas build`
8. Worker extracts IPA from VM
9. Worker uploads IPA to controller
10. Worker cleans up (stops VM, deletes temp files)

## Common Commands

### VM Management

```bash
# List VMs
ls -la ~/Library/Application\ Support/FreeAgent/VMs/

# Check VM disk size
du -sh ~/Library/Application\ Support/FreeAgent/VMs/*/Disk.img

# Delete VM
rm -rf ~/Library/Application\ Support/FreeAgent/VMs/my-builder/

# Create snapshot
cp ~/Library/Application\ Support/FreeAgent/VMs/my-builder/Disk.img \
   ~/Library/Application\ Support/FreeAgent/VMs/my-builder/Disk-clean.img
```

### SSH Troubleshooting

```bash
# Test SSH connection
ssh -vvv -i ~/.ssh/free_agent_ed25519 builder@192.168.64.2

# Check SSH server in VM (inside VM)
sudo systemsetup -getremotelogin

# Restart SSH server in VM (inside VM)
sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist
sudo launchctl load /System/Library/LaunchDaemons/ssh.plist
```

### Build Logs

```bash
# Worker logs (printed to console)
# Check for:
# - "VM created successfully"
# - "✓ VM started"
# - "✓ VM is ready"
# - "✓ Source code copied"
# - "✓ Certificates installed"
# - "✓ Build completed successfully"
```

## Configuration Options

Open Settings from menu bar:

### Controller
- **URL:** Controller server endpoint (default: http://localhost:3000)
- **Poll Interval:** How often to check for jobs (default: 30s)

### Resource Limits
- **Max CPU:** Percentage of host CPU for VM (default: 50%)
- **Max Memory:** RAM allocation per VM (default: 8GB)
- **Max Concurrent Builds:** Number of simultaneous VMs (default: 1)

### VM Settings
- **Disk Size:** Storage per VM (default: 80GB)
- **Reuse VMs:** Keep VM between builds (default: OFF)
- **Cleanup After Build:** Delete VM disk when done (default: ON)

### Worker Preferences
- **Auto-start Worker:** Start on app launch (default: OFF)
- **Build Only When Idle:** Pause when user active (default: OFF)
- **Build Timeout:** Max build duration (default: 240 min)

## Typical Build

```
[14:23:01] Starting build job: abc123
[14:23:02] ✓ Downloaded build package (45MB)
[14:23:03] ✓ Downloaded certificates
[14:23:04] Creating VM...
[14:23:05] ✓ VM created successfully
[14:23:06] Starting VM...
[14:23:42] ✓ VM started
[14:23:43] Waiting for VM to be ready...
[14:23:51] ✓ VM is ready
[14:23:51] Copying source code to VM...
[14:23:58] ✓ Source code copied
[14:23:59] Installing certificates...
[14:24:04] ✓ Certificates installed
[14:24:05] Starting Expo build process...
[14:24:06] Installing npm dependencies...
[14:26:14] ✓ npm install complete
[14:26:15] Installing CocoaPods dependencies...
[14:29:42] ✓ pod install complete
[14:29:43] Running EAS build...
[14:43:21] ✓ Build completed successfully
[14:43:22] Extracting build artifact...
[14:43:28] ✓ Extracted IPA: /tmp/build-abc123.ipa (87 MB)
[14:43:29] ✓ Results uploaded
[14:43:30] Stopping VM...
[14:43:35] ✓ VM stopped
[14:43:36] ✓ Build job completed: abc123

Total time: 20 minutes 35 seconds
```

## What's Next?

### Controller Server (Not Yet Built)

The controller manages the build queue. You'll need:

```javascript
// Pseudo-code
POST /api/workers/register          // Worker announces availability
GET  /api/workers/:id/poll          // Worker checks for jobs
GET  /api/builds/:id/package        // Worker downloads source
GET  /api/builds/:id/certs          // Worker downloads certificates
POST /api/workers/upload            // Worker uploads IPA + logs
```

See `/ARCHITECTURE.md` for full API spec.

### CLI Submit Tool (Not Yet Built)

Submit builds from terminal:

```bash
expo-controller submit ./my-app \
  --cert ./certs/dist.p12 \
  --cert-password "password123" \
  --profile ./profiles/adhoc.mobileprovision \
  --platform ios
```

## Troubleshooting

### "VM creation failed: invalid hardware model"

The VM hasn't been created yet. Run:
```bash
cd vm-setup
./create-macos-vm.sh
```

### "SSH connection timeout"

The VM is not booted or SSH server isn't running. Boot the VM and check:
```bash
# Inside VM
sudo systemsetup -getremotelogin
# Should show: Remote Login: On
```

### "Certificate installation failed"

Check P12 password is correct. Test manually:
```bash
# On host
security import cert.p12 -k ~/Library/Keychains/login.keychain
# Enter password when prompted
```

### "IPA not found"

The build failed. Check logs for Xcode errors. Common issues:
- Missing code signing identity
- Invalid provisioning profile
- Compilation errors in project
- Network timeout during dependency download

### "Build timed out"

Default timeout is 4 hours. If hitting this:
- Increase timeout in Settings
- Check for hung processes in VM
- Ensure VM has enough resources (CPU, RAM)

## Performance Tips

### Speed Up Builds

1. **Reuse VMs** (Settings → Reuse VMs: ON)
   - Saves 30-60s boot time
   - Trade-off: Requires 80GB persistent disk

2. **Increase Resources** (Settings → Max CPU: 80%, Max Memory: 16GB)
   - Faster Xcode compilation
   - Trade-off: Less resources for host

3. **Pre-install Dependencies** (future)
   - Bake Homebrew, CocoaPods, npm packages into VM image
   - Saves 2-5 minutes per build

### Monitor Performance

```bash
# CPU usage
top -o cpu

# Memory usage
vm_stat

# Disk usage
df -h

# Network usage
nettop
```

## Support

- Implementation details: `/VM_IMPLEMENTATION.md`
- Setup guide: `/vm-setup/README.md`
- Architecture: `/ARCHITECTURE.md`
- Status: `/free-agent/IMPLEMENTATION_STATUS.md`

## License

See LICENSE file.
