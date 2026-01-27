# Free Agent VM Setup Guide

Complete setup guide for creating macOS VMs to build iOS apps.

## Prerequisites

- macOS 14+ (Sonoma) on Apple Silicon
- Xcode 15+
- ~100GB free disk space
- Administrator access

## Quick Start

### 1. Generate SSH Keys

```bash
cd vm-setup
./setup-ssh.sh
```

This creates `~/.ssh/free_agent_ed25519` key pair for VM communication.

### 2. Create VM Image

```bash
./create-macos-vm.sh my-builder 80
```

Arguments:
- `my-builder`: VM name (default: free-agent-builder)
- `80`: Disk size in GB (default: 80)

This will:
- Download macOS IPSW (~13GB)
- Create VM with hardware model and disk
- Install macOS (30-60 minutes)

**Note:** The script creates the VM but doesn't install Xcode automatically. You'll need to boot the VM once and set it up manually.

### 3. Boot VM and Install Dependencies

After the VM is created, you need to boot it once to install Xcode and configure SSH:

#### Option A: Using UTM (Recommended for first-time setup)

1. Download [UTM](https://mac.getutm.app/)
2. Import the VM:
   - Open UTM
   - File → Import → Select VM directory at `~/Library/Application Support/FreeAgent/VMs/my-builder`
3. Boot the VM
4. Complete macOS setup (create user account, etc.)

#### Option B: Using Swift Script (Advanced)

Create a simple boot script to start the VM headless. (Implementation left as exercise - requires VZVirtualMachine instance)

### 4. Inside the VM

Once the VM is booted, open Terminal and run:

```bash
# Install Xcode Command Line Tools
xcode-select --install

# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Node.js and EAS CLI
brew install node
npm install -g eas-cli

# Enable SSH server
sudo systemsetup -setremotelogin on

# Create build user
sudo dscl . -create /Users/builder
sudo dscl . -create /Users/builder UserShell /bin/bash
sudo dscl . -create /Users/builder RealName "Build User"
sudo dscl . -create /Users/builder UniqueID 502
sudo dscl . -create /Users/builder PrimaryGroupID 20
sudo dscl . -create /Users/builder NFSHomeDirectory /Users/builder
sudo createhomedir -c -u builder

# Set up SSH key
sudo mkdir -p /Users/builder/.ssh
sudo nano /Users/builder/.ssh/authorized_keys
# Paste the public key from ~/.ssh/free_agent_ed25519.pub (on host)
sudo chown -R builder:staff /Users/builder/.ssh
sudo chmod 700 /Users/builder/.ssh
sudo chmod 600 /Users/builder/.ssh/authorized_keys
```

### 5. Test SSH Connection

From the host machine:

```bash
ssh -i ~/.ssh/free_agent_ed25519 builder@192.168.64.2
```

If this works, the VM is ready!

### 6. Shut Down VM

```bash
sudo shutdown -h now
```

### 7. (Optional) Create Clean Snapshot

```bash
cp ~/Library/Application\ Support/FreeAgent/VMs/my-builder/Disk.img \
   ~/Library/Application\ Support/FreeAgent/VMs/my-builder/Disk-clean.img
```

This allows you to revert to a clean state.

## Architecture

```
┌─────────────────────────────────────────────┐
│ Host macOS (Free Agent App)                │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │ WorkerService                        │  │
│  │ - Polls controller for jobs          │  │
│  │ - Downloads source code + certs      │  │
│  │ - Spawns VM via VMManager            │  │
│  │ - Uploads results                    │  │
│  └──────────┬───────────────────────────┘  │
│             │                               │
│  ┌──────────▼───────────────────────────┐  │
│  │ VMManager                            │  │
│  │ - Creates VZVirtualMachine           │  │
│  │ - Starts VM (30-60s boot)            │  │
│  │ - Coordinates build execution        │  │
│  └──────────┬───────────────────────────┘  │
│             │                               │
│  ┌──────────▼───────────────────────────┐  │
│  │ XcodeBuildExecutor                   │  │
│  │ - SSH into VM (builder@192.168.64.2) │  │
│  │ - Executes: npm install, pod install │  │
│  │ - Runs: eas build --local --platform │  │
│  │   ios                                │  │
│  │ - Streams logs back to host          │  │
│  └──────────┬───────────────────────────┘  │
│             │                               │
│  ┌──────────▼───────────────────────────┐  │
│  │ CertificateManager                   │  │
│  │ - Copies P12 to VM via SCP           │  │
│  │ - Creates keychain                   │  │
│  │ - Imports cert: security import      │  │
│  │ - Unlocks for codesign               │  │
│  └──────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
              │
              │ SSH (port 22)
              ▼
┌─────────────────────────────────────────────┐
│ VM macOS (Headless)                         │
│                                             │
│  /Users/builder/project/  (source code)    │
│  /Users/builder/Library/Keychains/          │
│    build.keychain-db      (signing cert)    │
│                                             │
│  DerivedData/             (build output)    │
│    └── *.ipa                                │
│                                             │
│  NAT Network: 192.168.64.2                  │
│  (Host can access, VM can reach internet)   │
└─────────────────────────────────────────────┘
```

## Typical Build Flow

1. **Controller assigns job** to worker
2. **WorkerService** downloads:
   - Source code zip
   - P12 certificate + password
   - Provisioning profiles
3. **VMManager** creates & starts VM (30-60s)
4. **XcodeBuildExecutor** waits for SSH (up to 120s)
5. **CertificateManager** installs certs
6. **XcodeBuildExecutor** copies source via SCP
7. **XcodeBuildExecutor** runs build commands:
   ```bash
   cd /Users/builder/project
   npm install                    # ~2 min
   cd ios && pod install && cd .. # ~3 min
   eas build --local --platform ios --non-interactive  # ~10-15 min
   ```
8. **VMManager** extracts IPA via SCP
9. **WorkerService** uploads IPA + logs to controller
10. **VMManager** stops and cleans up VM

**Total time:** ~20-30 minutes per build

## Performance Optimization

### Warm VMs (Future)

Instead of starting a fresh VM each time:
- Keep pool of N booted VMs
- Assign job to warm VM (instant)
- Reset VM after M builds

Trade-off:
- **Pro:** 30-60s faster per build
- **Con:** Uses 8GB RAM per warm VM

### Pre-installed Dependencies (Future)

Bake common dependencies into VM image:
- Homebrew packages
- CocoaPods gems
- npm global packages
- Common Swift Package Manager dependencies

Reduces `npm install` + `pod install` time significantly.

### Build Caching (Future)

Cache DerivedData between builds:
- First build: ~15 min
- Subsequent builds: ~5 min (incremental)

Requires persistent VM disks.

## Troubleshooting

### VM won't boot

```bash
# Check VM files exist
ls -lh ~/Library/Application\ Support/FreeAgent/VMs/my-builder/

# Required files:
# - HardwareModel
# - MachineIdentifier
# - Disk.img
# - AuxStorage
```

### SSH connection refused

```bash
# Boot VM and check SSH is running
sudo systemsetup -getremotelogin

# Should show: Remote Login: On
```

### Build times out

Default timeout: 4 hours (configurable in Settings)

Check logs for:
- Network issues (npm/CocoaPods downloads)
- Code signing errors
- Xcode build failures

### IPA not found

```bash
# Inside VM, check:
find ~/Library/Developer/Xcode/DerivedData -name "*.ipa"

# If empty, build failed. Check logs.
```

## VM Disk Management

Each VM uses ~80GB by default:
- macOS: ~15GB
- Xcode: ~20GB
- Build cache: ~10GB
- Buffer: ~35GB

**Reuse VMs** to save disk space:
- Settings → VM Settings → Reuse VMs: ON
- Cleans builds between jobs, keeps OS intact

**Ephemeral VMs** (default):
- Fresh VM every build
- Slower but guaranteed clean state
- Good for debugging

## Security

### SSH Key Security

Private key: `~/.ssh/free_agent_ed25519`
- Readable only by current user (chmod 600)
- Never share or commit to git
- Regenerate if compromised:
  ```bash
  rm ~/.ssh/free_agent_ed25519*
  ./setup-ssh.sh
  # Re-add public key to VM
  ```

### Certificate Handling

P12 certificates are:
- Downloaded from controller to host temp dir
- Copied to VM via SCP
- Imported to ephemeral keychain
- Deleted after build completes

**Never stored permanently on disk.**

### Network Isolation

VMs use NAT networking:
- VM can reach internet (for npm, CocoaPods)
- VM cannot reach other VMs
- Host can SSH to VM
- External machines cannot reach VM

## Cost Estimates

### Hardware Requirements

- **Minimum:** M1 MacBook Air, 16GB RAM
  - 1 concurrent build
  - 30-40 min per build
  - ~2 builds/hour

- **Recommended:** M2 Mac Mini, 32GB RAM
  - 2 concurrent builds
  - 20-30 min per build
  - ~4 builds/hour

- **Optimal:** M2 Ultra Mac Studio, 64GB RAM
  - 4 concurrent builds
  - 15-25 min per build
  - ~10 builds/hour

### Disk Usage

- **Per VM:** 80GB
- **Reuse mode:** 80GB total (1 VM)
- **Ephemeral mode:** 80GB per concurrent build

### Network Bandwidth

- **Per build:**
  - Download: ~500MB (source + dependencies)
  - Upload: ~100MB (IPA)
  - Total: ~600MB

- **100 builds/day:** ~60GB bandwidth

## Next Steps

1. **Controller Server:** Implement job queue (Node.js + SQLite)
2. **CLI Tool:** `expo-controller submit` to upload projects
3. **Dashboard:** View build status, logs, statistics
4. **Xcode Installation:** Automate Xcode download inside VM
5. **VM Pooling:** Keep warm VMs ready
6. **Build Caching:** Persist DerivedData between builds

## Support

See `/free-agent/IMPLEMENTATION_STATUS.md` for implementation details.
See `/free-agent/ARCHITECTURE.md` for system design.
