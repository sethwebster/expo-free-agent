# Local VM Testing Workflow

Quick guide for testing bootstrap script changes without pushing to registry.

## Problem

When developing bootstrap scripts, you don't want to:
- Push to `ghcr.io` registry for every test
- Wait for image upload/download
- Pollute registry with test versions

## Solution

Use `expo-free-agent-base-local` - a local VM image that gets rebuilt with your latest scripts.

## Workflow

### Initial Setup

```bash
# One-time: Create local test image
./vm-setup/setup-local-test-image.sh
```

This:
1. Clones `ghcr.io/sethwebster/expo-free-agent-base:latest`
2. Installs your current `vm-setup/*.sh` scripts
3. Creates `expo-free-agent-base-local`

### Development Cycle

```bash
# 1. Edit bootstrap scripts
vim vm-setup/free-agent-stub.sh

# 2. Rebuild local image with updated scripts
./vm-setup/setup-local-test-image.sh

# 3. Test with E2E tests
./test-e2e-vm.sh
```

The test automatically uses `expo-free-agent-base-local` if it exists.

### Publishing to Registry

When ready to release:

```bash
# Update version and push to registry
./vm-setup/release-base-image.sh 0.1.32
```

This:
1. Updates `vm-setup/VERSION`
2. Creates new image with updated scripts
3. Pushes to `ghcr.io/sethwebster/expo-free-agent-base:0.1.32`
4. Tags as `:latest`
5. Updates code references

## Image Priority

E2E tests check in this order:
1. **Local image:** `expo-free-agent-base-local` (your test image)
2. **Registry image:** `ghcr.io/sethwebster/expo-free-agent-base:latest`

## Files Installed in VM

```
/usr/local/bin/
├── free-agent-stub.sh          # Security stub (runs first)
├── install-signing-certs       # Certificate installer
├── free-agent-run-job          # Build executor
└── vm-monitor.sh               # VM health monitor

/Library/LaunchDaemons/
├── com.expo.free-agent.bootstrap.plist
└── com.expo.virtiofs-automount.plist

/usr/local/etc/
└── free-agent-version          # Version file
```

## What Gets Tested

**Local Image Tests:**
- Your exact changes to bootstrap scripts
- Latest security hardening
- New certificate handling logic
- VM lifecycle improvements

**Registry Image Tests:**
- Published/released version
- What other developers will use
- What production workers use

## Clean Up

```bash
# Delete local test image
tart delete expo-free-agent-base-local

# Rebuild from scratch
./vm-setup/setup-local-test-image.sh
```

## Troubleshooting

### "Base image not found"

```bash
# Pull from registry first
tart pull ghcr.io/sethwebster/expo-free-agent-base:latest

# Then create local image
./vm-setup/setup-local-test-image.sh
```

### "Script installation failed"

Check that all required files exist:
```bash
ls -lh vm-setup/{free-agent-stub.sh,install-signing-certs,vm-monitor.sh,com.expo.free-agent.bootstrap.plist}
```

### Test uses wrong image

```bash
# Check which image will be used
tart list | grep expo-free-agent-base

# Force use of local image
tart delete ghcr.io/sethwebster/expo-free-agent-base@latest

# Force use of registry image
tart delete expo-free-agent-base-local
```

## Example Development Session

```bash
# Morning: Start work on new bootstrap feature
./vm-setup/setup-local-test-image.sh
vim vm-setup/free-agent-stub.sh

# Test iteration 1
./vm-setup/setup-local-test-image.sh
./test-e2e-vm.sh  # Fails - fix bug

# Test iteration 2
vim vm-setup/free-agent-stub.sh
./vm-setup/setup-local-test-image.sh
./test-e2e-vm.sh  # Passes

# Evening: Release to registry
./vm-setup/release-base-image.sh 0.1.32
git add vm-setup/VERSION
git commit -m "feat: improve bootstrap security"
git push
```

## See Also

- `vm-setup/setup-local-test-image.sh` - Create/update local image
- `vm-setup/release-base-image.sh` - Publish to registry
- `vm-setup/install-to-vm-template.sh` - Low-level script installer
- `docs/E2E-TESTING.md` - Full testing guide
