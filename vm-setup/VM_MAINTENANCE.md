# VM Maintenance Procedures

**IMPORTANT:** `vm-setup/VERSION` is the single source of truth for base image version. All releases are tagged from this file. Always reference VERSION when pulling or verifying base images.

---

## Daily/Regular Maintenance

### Keep Local Base Image Updated

**CRITICAL:** Always keep your local `expo-free-agent-base` VM up to date with the latest registry version.

**Single Source of Truth:** `vm-setup/VERSION` - This file defines the current release version. All releases are tagged from this file.

#### Check Current Version

```bash
# Check current release version (single source of truth)
cat vm-setup/VERSION

# Check what's installed locally
tart list | grep expo-free-agent-base
```

#### Update Local Base Image

```bash
# Get current version from single source of truth
CURRENT_VERSION=$(cat vm-setup/VERSION)
echo "Current version: $CURRENT_VERSION"

# Pull specific version and latest
tart pull ghcr.io/sethwebster/expo-free-agent-base:$CURRENT_VERSION
tart pull ghcr.io/sethwebster/expo-free-agent-base:latest

# Verify it pulled correctly
tart list | grep expo-free-agent-base
```

**When to update:**
- After releasing a new base image version
- Before starting development work
- If builds are failing with unexpected errors
- When bootstrap scripts are updated

#### Update Template References

After pulling a new base image, update template VM if needed:

```bash
# If you have a local template, recreate it
tart delete expo-free-agent-tahoe-26.2-xcode-expo-54  # or your template name
tart clone ghcr.io/sethwebster/expo-free-agent-base:latest expo-free-agent-tahoe-26.2-xcode-expo-54
```

### Cleanup Old VMs

**Local VMs to keep:**
- `expo-free-agent-tahoe-*` - Templates
- `expo-free-agent-base:*` - Base images

**Safe to delete:**
- `fa-*` - Ephemeral build VMs (delete when stopped)
- `test-*` - Test VMs
- `job-*` - Old job VMs
- Any VM not prefixed with `expo-free-agent`

#### Cleanup Script

```bash
# Delete all stopped build VMs (fa-*)
for vm in $(tart list | grep "^local" | awk '{print $2}' | grep "^fa-"); do
  tart delete "$vm"
  echo "Deleted: $vm"
done

# Delete test VMs
for vm in $(tart list | grep "^local" | awk '{print $2}' | grep "^test-"); do
  tart delete "$vm"
  echo "Deleted: $vm"
done
```

### Verify Base Image Health

After updating, verify the base image works:

```bash
# Quick verification
cd vm-setup
./test-vm-bootstrap.sh ghcr.io/sethwebster/expo-free-agent-base:latest
```

Or manually:

```bash
# Start VM
tart run ghcr.io/sethwebster/expo-free-agent-base:latest --no-graphics &
sleep 10

# Get IP
VM_IP=$(tart ip ghcr.io/sethwebster/expo-free-agent-base:latest)

# Check scripts installed
tart exec ghcr.io/sethwebster/expo-free-agent-base:latest ls -lh /usr/local/bin/free-agent*

# Verify version
tart exec ghcr.io/sethwebster/expo-free-agent-base:latest cat /usr/local/etc/free-agent-version

# Cleanup
tart stop ghcr.io/sethwebster/expo-free-agent-base:latest
```

## Storage Management

### Check Disk Usage

```bash
# See total VM storage
du -sh ~/.tart

# List VMs by size
tart list
```

### Reclaim Space

```bash
# Delete old OCI image versions (keep last 2)
# Manual review recommended - check which versions are actually in use

# Delete specific old version
tart delete ghcr.io/sethwebster/expo-free-agent-base:0.1.23

# Tart auto-prunes when pulling if space is low
# Disable with: export TART_NO_AUTO_PRUNE=1
```

## Troubleshooting

### Base Image Won't Pull

```bash
# Check registry authentication
gh auth status

# Re-authenticate
gh auth login

# Set credentials for tart
export TART_REGISTRY_USERNAME=sethwebster
export TART_REGISTRY_PASSWORD="$(gh auth token)"

# Retry pull
tart pull ghcr.io/sethwebster/expo-free-agent-base:latest
```

### VMs Won't Start

```bash
# Check system limits
ulimit -a

# Check running VMs
ps aux | grep tart

# Force stop stuck VMs
killall -9 tart

# Check for locked VMs
ls -la ~/.tart/vms/
```

### Disk Full

```bash
# Find large VMs
du -sh ~/.tart/vms/*

# Delete all stopped ephemeral VMs
for vm in $(tart list | grep "^local" | grep "stopped" | awk '{print $2}' | grep -E "^(fa-|test-|job-)"); do
  tart delete "$vm"
done

# Last resort: delete old base image versions
# Keep only latest and current VERSION
```

## Weekly Checklist

- [ ] Check `vm-setup/VERSION` for current release version
- [ ] Pull base image matching VERSION file
- [ ] Verify local VM version matches `vm-setup/VERSION`
- [ ] Delete stopped ephemeral VMs (fa-*, test-*, job-*)
- [ ] Verify local template VM exists
- [ ] Check disk space (~/.tart should be <500GB)

## After Base Image Release

**Remember:** `vm-setup/VERSION` is the single source of truth for release versions.

1. **Check current version:**
   ```bash
   CURRENT_VERSION=$(cat vm-setup/VERSION)
   echo "Release version: $CURRENT_VERSION"
   ```

2. **Update local copy:**
   ```bash
   tart pull ghcr.io/sethwebster/expo-free-agent-base:$CURRENT_VERSION
   tart pull ghcr.io/sethwebster/expo-free-agent-base:latest
   ```

3. **Verify version in VM matches VERSION file:**
   ```bash
   tart run ghcr.io/sethwebster/expo-free-agent-base:latest --no-graphics &
   sleep 10
   tart exec ghcr.io/sethwebster/expo-free-agent-base:latest cat /usr/local/etc/free-agent-version
   # Should match vm-setup/VERSION
   tart stop ghcr.io/sethwebster/expo-free-agent-base:latest
   ```

4. **Update any local templates:**
   ```bash
   # If you maintain a local template, recreate from new base
   CURRENT_VERSION=$(cat vm-setup/VERSION)
   tart delete my-local-template
   tart clone ghcr.io/sethwebster/expo-free-agent-base:$CURRENT_VERSION my-local-template
   ```

5. **Test with real build:**
   - Submit a test build
   - Verify VM uses new base image version
   - Check bootstrap completes successfully
   - Confirm build succeeds

## Emergency Recovery

### Lost All VMs

```bash
# Pull base image
tart pull ghcr.io/sethwebster/expo-free-agent-base:latest

# Create working template
tart clone ghcr.io/sethwebster/expo-free-agent-base:latest expo-free-agent-tahoe-26.2-xcode-expo-54

# Restart worker
cd /Users/sethwebster/Development/expo/expo-free-agent/free-agent
swift run FreeAgent
```

### Base Image Corrupted

```bash
# Delete corrupted version
tart delete ghcr.io/sethwebster/expo-free-agent-base:latest

# Re-pull from registry
tart pull ghcr.io/sethwebster/expo-free-agent-base:latest

# Verify integrity
tart run ghcr.io/sethwebster/expo-free-agent-base:latest --no-graphics &
tart exec ghcr.io/sethwebster/expo-free-agent-base:latest cat /usr/local/etc/free-agent-version
tart stop ghcr.io/sethwebster/expo-free-agent-base:latest
```
