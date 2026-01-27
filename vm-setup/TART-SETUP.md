# Tart VM Setup Guide

This guide explains how to prepare the `expo-free-agent-tahoe-26.2-xcode-expo-54` template VM for use with Free Agent.

## Prerequisites

- macOS with Apple Silicon (Tart requires ARM)
- [Tart](https://tart.run) installed: `brew install cirruslabs/cli/tart`
- Existing Tart VM image: `expo-free-agent-tahoe-26.2-xcode-expo-54`

## Verify Template Exists

```bash
tart list
```

You should see `expo-free-agent-tahoe-26.2-xcode-expo-54` in the list.

## One-Time Setup (Baking the Template)

### 1. Boot the Template VM with Graphics

```bash
tart run expo-free-agent-tahoe-26.2-xcode-expo-54
```

### 2. Inside the VM, Verify/Configure Settings

#### A. Create Build User (if not already done)

The template should already have a user (typically `admin`). Verify:

```bash
whoami
# Should print: admin (or whatever user you chose)
```

#### B. Enable Remote Login (SSH)

Go to **System Settings → General → Sharing**
- Enable "Remote Login"
- Allow access for your build user

Or via command line:

```bash
sudo systemsetup -setremotelogin on
sudo dseditgroup -o edit -a admin -t user com.apple.access_ssh
```

#### C. Enable Auto-Login (Critical for Headless)

Go to **System Settings → Users & Groups → Login Options**
- Set "Automatic login" to your build user

This ensures headless boots land in a user session.

Or via command line:

```bash
sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser admin
```

#### D. Disable FileVault (if enabled)

FileVault can break headless SSH access.

Go to **System Settings → Privacy & Security → FileVault**
- Turn Off FileVault (if enabled)

#### E. Verify Xcode is Ready

```bash
# Accept license
sudo xcodebuild -license accept

# Run first-launch setup
sudo xcodebuild -runFirstLaunch

# Verify it works
xcodebuild -version
xcodebuild -showsdks
```

#### F. Verify Node/npm

```bash
node -v
npm -v
npx --yes expo --version
```

If missing, install:

```bash
# Install Node via Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install node
```

#### G. Install CocoaPods

```bash
sudo gem install cocoapods
pod --version
```

### 3. Install Free Agent Runner Script

Copy the runner script to the VM:

```bash
# From host (outside VM), get the script
cat vm-setup/free-agent-run-job

# Inside VM:
sudo mkdir -p /usr/local/bin
sudo nano /usr/local/bin/free-agent-run-job
# Paste the script contents

# Make executable
sudo chmod +x /usr/local/bin/free-agent-run-job

# Test it exists
ls -la /usr/local/bin/free-agent-run-job
```

Or use SCP to copy:

```bash
# From host:
VM_IP=$(tart ip expo-free-agent-tahoe-26.2-xcode-expo-54)
scp -o StrictHostKeyChecking=no vm-setup/free-agent-run-job admin@$VM_IP:/tmp/
ssh admin@$VM_IP "sudo mv /tmp/free-agent-run-job /usr/local/bin/ && sudo chmod +x /usr/local/bin/free-agent-run-job"
```

### 4. Test Runner Script

Inside the VM:

```bash
/usr/local/bin/free-agent-run-job --help
# Should show usage
```

### 5. Create Working Directories

```bash
mkdir -p ~/free-agent/in ~/free-agent/out ~/free-agent/work
```

### 6. Optional: Set SSH Key for Passwordless Auth

On the host:

```bash
# Generate key if you don't have one
ssh-keygen -t ed25519 -f ~/.ssh/free_agent_ed25519 -N ""

# Copy public key to VM
VM_IP=$(tart ip expo-free-agent-tahoe-26.2-xcode-expo-54)
ssh-copy-id -i ~/.ssh/free_agent_ed25519.pub admin@$VM_IP
```

### 7. Shutdown Cleanly

```bash
sudo shutdown -h now
```

### 8. Verify Template is Ready

From host:

```bash
# Clone a test VM
tart clone expo-free-agent-tahoe-26.2-xcode-expo-54 test-vm

# Run headless
screen -d -m tart run test-vm --no-graphics

# Wait for IP
sleep 10
tart ip test-vm

# SSH in
IP=$(tart ip test-vm)
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@$IP 'xcodebuild -version'

# Should print Xcode version

# Verify runner script
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@$IP '/usr/local/bin/free-agent-run-job --help'

# Cleanup
tart delete -f test-vm
```

If all commands succeed, your template is ready!

## Template Checklist

Before using the template for builds, verify:

- [ ] Build user exists (e.g., `admin`)
- [ ] Remote Login enabled
- [ ] Auto-login configured for build user
- [ ] FileVault disabled (or configured for headless)
- [ ] Xcode installed and first-run completed
- [ ] `xcodebuild -license` accepted
- [ ] Node.js and npm installed
- [ ] CocoaPods installed
- [ ] `/usr/local/bin/free-agent-run-job` exists and is executable
- [ ] Headless boot works (tested with screen + tart run --no-graphics)
- [ ] SSH works without password

## Troubleshooting

### VM doesn't get an IP

**Problem:** `tart ip <vm>` returns empty or errors

**Solution:**
- Wait longer (can take 30-60s for first boot)
- Check VM is running: `tart list`
- Verify auto-login is configured
- Try rebooting the template and re-saving

### SSH times out

**Problem:** SSH connection refused or times out

**Solution:**
- Verify Remote Login is enabled
- Check firewall settings (System Settings → Network → Firewall)
- Verify auto-login user matches SSH user
- Test with graphics: `tart run <vm>` (no --no-graphics) to see desktop

### xcodebuild fails with license prompt

**Problem:** Build fails with "You have not agreed to the Xcode license"

**Solution:**
```bash
# Inside VM:
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

Then shutdown and re-save template.

### CocoaPods not found

**Problem:** `pod install` command not found

**Solution:**
```bash
# Inside VM:
sudo gem install cocoapods
```

### Headless boot shows login screen

**Problem:** VM boots to login screen in headless mode

**Solution:**
- Verify auto-login is configured for the build user
- Check FileVault is disabled
- Ensure the auto-login user exists and has a password set

## Next Steps

Once the template is ready:

1. Update `TartVMManager.swift` if you used a different user than `admin`
2. Test a real build with the Free Agent worker
3. Monitor the first few builds to catch any issues early
