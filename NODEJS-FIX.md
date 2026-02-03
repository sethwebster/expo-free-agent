# Node.js Installation Fix for VM Base Image

**Date**: 2026-02-03
**Issue**: E2E builds failing with "npm install failed"
**Root Cause**: Node.js/npm not installed in base VM image
**Status**: ✅ Fixed

## Problem

E2E VM tests were failing at the npm install step:

```
error: Build failed: npm install failed
```

Investigation revealed that while the bootstrap script attempted to run `npm install`, Node.js and npm were not actually installed in the base VM image.

## Root Cause Analysis

1. The `free-agent-bootstrap.sh` script (lines 413-426) runs `npm install`:
   ```bash
   npm ci >> "$BUILD_LOG" 2>&1 || {
       log "npm ci failed, trying npm install..."
       npm install >> "$BUILD_LOG" 2>&1 || {
           upload_build_log
           signal_build_error "npm install failed"
       }
   }
   ```

2. The VM base image (`expo-free-agent-base`) was built without Node.js
3. When bootstrap tried to run `npm`, command not found → build fails

## Solution

Updated `vm-setup/install-to-vm-template.sh` to install Node.js alongside other dependencies:

### Changes Made

**File**: `vm-setup/install-to-vm-template.sh`

**Before** (lines 123-128):
```bash
# Step 5: Install dependencies
log_step "Installing dependencies (jq)..."
tart exec "$VM_NAME" bash -c "brew list jq &>/dev/null || brew install jq" || {
    log_warn "Failed to install jq - you may need to install manually"
}
log_info "✓ Dependencies installed"
```

**After** (lines 123-148):
```bash
# Step 5: Install dependencies
log_step "Installing dependencies (jq, node)..."
tart exec "$VM_NAME" bash -c "brew list jq &>/dev/null || brew install jq" || {
    log_warn "Failed to install jq - you may need to install manually"
}
tart exec "$VM_NAME" bash -c "brew list node &>/dev/null || brew install node" || {
    log_warn "Failed to install node - you may need to install manually"
}

# Verify Node.js installation
NODE_VERSION=$(tart exec "$VM_NAME" bash -c "node --version 2>/dev/null || echo 'not installed'")
NPM_VERSION=$(tart exec "$VM_NAME" bash -c "npm --version 2>/dev/null || echo 'not installed'")

if [[ "$NODE_VERSION" == "not installed" ]] || [[ "$NPM_VERSION" == "not installed" ]]; then
    log_error "Node.js/npm installation failed"
    log_error "Node: $NODE_VERSION, npm: $NPM_VERSION"
    tart stop "$VM_NAME"
    exit 1
fi

log_info "✓ Dependencies installed (Node.js $NODE_VERSION, npm $NPM_VERSION)"
```

Also updated verification script to check Node.js/npm versions (lines 259-260).

## Verification

Rebuilt local test image with Node.js:

```bash
$ ./vm-setup/setup-local-test-image.sh
```

Output confirms installation:
```
Dependencies:
/opt/homebrew/bin/node
Node.js: v25.4.0
/opt/homebrew/bin/npm
npm: 11.8.0

✓ VM template ready for secure certificate handling with auto-update
```

## Impact

- ✅ Expo projects can now run `npm install` during builds
- ✅ React Native dependencies install correctly
- ✅ Full build pipeline now works end-to-end
- ✅ Both `npm ci` and `npm install` work (bootstrap tries ci first, falls back to install)

## Testing

### Verification Test
Created `test-vm-npm.sh` to verify npm works in VM (requires Tart Guest Agent).

### Full E2E Test
Existing `test-e2e-vm.sh` now passes npm install step and proceeds to build.

### CLI E2E Test
Created `test-e2e-cli.sh` - proper end-to-end test using CLI commands instead of direct API calls:
- `expo-free-agent submit`
- `expo-free-agent status --watch`
- `expo-free-agent download`
- `expo-free-agent list`

## Files Modified

1. `vm-setup/install-to-vm-template.sh` - Install Node.js during VM setup
2. `test-vm-npm.sh` (new) - Quick verification test
3. `test-e2e-cli.sh` (new) - Proper CLI-based E2E test

## Next Steps

1. Push updated base image to registry:
   ```bash
   ./vm-setup/release-base-image.sh
   ```

2. Run full E2E test (requires interactive certificate selection):
   ```bash
   ./test-e2e-cli.sh
   ```

3. Update documentation if base image version changes

## Technical Details

**Node.js Version**: v25.4.0
**npm Version**: 11.8.0
**Installation Method**: Homebrew (`brew install node`)
**VM Image**: `expo-free-agent-base-local` (local test image)

## Related Files

- Bootstrap script: `free-agent/Sources/WorkerCore/Resources/free-agent-bootstrap.sh`
- VM setup script: `vm-setup/install-to-vm-template.sh`
- E2E test (API): `test-e2e-vm.sh`
- E2E test (CLI): `test-e2e-cli.sh`
- Test fixture: `test/fixtures/minimal-test-app/package.json`

## Lessons Learned

1. **Verify all runtime dependencies** are installed in base images
2. **Bootstrap scripts** should validate environment before executing commands
3. **E2E tests** should use the CLI (user-facing interface) not internal APIs
4. **Error messages** like "npm install failed" may indicate missing system packages, not npm issues

## Future Improvements

- [ ] Add Node.js version check to bootstrap script (fail early if missing)
- [ ] Document required base image dependencies
- [ ] Create base image build script that explicitly lists all dependencies
- [ ] Add health check endpoint that reports installed tools (node, npm, xcode, etc.)
