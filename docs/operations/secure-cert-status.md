# Secure Certificate Handling - Implementation Status

**Last Updated:** 2026-01-26
**Overall Status:** ✅ Code Complete | 🔄 Awaiting VM Template Installation

---

## Quick Summary

All code changes for secure certificate handling are **complete and merged to main**. The system is ready to use once the VM template is prepared.

### What's Done ✅
- Controller endpoint for secure cert delivery
- Swift worker changes (env vars, no cert download)
- Build script enables code signing
- VM bootstrap scripts created
- Installation automation scripts created
- Comprehensive testing scripts created

### What's Next 🔄
- Install bootstrap scripts into VM template (manual step)
- Test bootstrap with real controller
- Clone production template
- Update BASE_IMAGE_ID in controller

---

## Implementation Status by Phase

### ✅ Phase 1: VM Template Scripts (COMPLETE)

All scripts created and ready for installation:

| Script | Status | Location | Purpose |
|--------|--------|----------|---------|
| free-agent-vm-bootstrap | ✅ Done | `/usr/local/bin/` | Randomize password, fetch certs |
| install-signing-certs | ✅ Done | `/usr/local/bin/` | Install P12 + profiles |
| vm-monitor.sh | ✅ Done | `/usr/local/bin/` | Send telemetry to controller |
| free-agent-run-job | ✅ Done | `/usr/local/bin/` | Execute Expo build |
| com.expo.free-agent.bootstrap.plist | ✅ Done | `/Library/LaunchDaemons/` | Auto-run bootstrap |

**Installation Script:** `vm-setup/install-to-vm-template.sh`
**Test Script:** `vm-setup/test-vm-bootstrap.sh`

### ✅ Phase 2: Controller Changes (COMPLETE)

**File:** `packages/controller/src/api/builds/index.ts`

New endpoint implemented:
```
GET /api/builds/:id/certs-secure
Headers: X-API-Key, X-Worker-Id, X-Build-Id
Returns: { p12, p12Password, keychainPassword, provisioningProfiles }
```

Security:
- ✅ Validates worker owns build
- ✅ Generates random keychain password per request
- ✅ Returns 403 if worker doesn't own build
- ✅ Returns 404 if certs don't exist

**Middleware:** Enhanced `requireWorkerAccess` to validate X-Build-Id header

**Telemetry Endpoint:** `POST /api/builds/:id/telemetry` for VM metrics

### ✅ Phase 3: Swift Worker Changes (COMPLETE)

**File:** `free-agent/Sources/BuildVM/TartVMManager.swift`

Changes:
- ✅ Pass env vars to VM via `--env` flags (BUILD_ID, WORKER_ID, API_KEY, CONTROLLER_URL)
- ✅ Wait for bootstrap completion via `/tmp/free-agent-ready`
- ✅ Input validation to prevent command injection
- ✅ Secure monitor credentials via temp file (no ps exposure)
- ✅ Source upload only (no certs)

**File:** `free-agent/Sources/WorkerCore/WorkerService.swift`

Changes:
- ✅ Removed `downloadSigningCertificates()` call
- ✅ Pass `nil` for `signingCertsPath`
- ✅ Pass buildId, workerId, controllerURL, apiKey to VMManager

### ✅ Phase 4: Build Script Updates (COMPLETE)

**File:** `vm-setup/free-agent-run-job`

Changes:
- ✅ Enabled code signing (removed CODE_SIGNING_ALLOWED=NO)
- ✅ Added `-allowProvisioningUpdates` flag
- ✅ Changed ExportOptions.plist:
  - method: development → ad-hoc
  - signingStyle: manual → automatic
- ✅ Added PIPESTATUS checks for correct error handling

### 🔄 Phase 5: Testing & Validation (PENDING)

**Automated Tests Created:**
- ✅ Installation script: `vm-setup/install-to-vm-template.sh`
- ✅ Test script: `vm-setup/test-vm-bootstrap.sh`

**Manual Tests Needed:**

| Test | Status | Description |
|------|--------|-------------|
| Bootstrap script | ⏳ Pending | Run test script against VM |
| Cert fetch | ⏳ Pending | Boot VM, verify controller fetch |
| End-to-end build | ⏳ Pending | Submit build with real cert |
| Security validation | ⏳ Pending | Verify SSH blocked, certs deleted |
| IPA signature | ⏳ Pending | Verify signed IPA valid |

### 🔄 Phase 6: Rollout (PENDING)

**Pre-Rollout Checklist:**
- [ ] Run installation script on base VM template
- [ ] Run test script to verify bootstrap works
- [ ] Test with real controller endpoint
- [ ] Clone production template
- [ ] Update controller BASE_IMAGE_ID
- [ ] Update worker configuration
- [ ] Test end-to-end with real cert

---

## How to Complete Installation

### Step 1: Prepare VM Template

```bash
# 1. Ensure you have a base Tart VM (e.g., expo-agent-base)
tart list

# 2. Stop the VM if running
tart stop expo-agent-base

# 3. Run installation script
cd /Users/sethwebster/Development/expo/expo-free-agent
./vm-setup/install-to-vm-template.sh expo-agent-base
```

This script:
- Verifies dependencies
- Copies all scripts to `/usr/local/bin/`
- Installs LaunchDaemon
- Configures permissions
- Verifies installation

### Step 2: Test Bootstrap

```bash
# Test bootstrap with mock controller
./vm-setup/test-vm-bootstrap.sh expo-agent-base http://localhost:3000
```

This tests:
- ✅ Bootstrap script runs on boot
- ✅ Password randomized (SSH blocked)
- ✅ Ready signal created
- ✅ LaunchDaemon working
- ✅ Dependencies installed

Expected output:
```
[PASS] ✓ ALL TESTS PASSED
VM template 'expo-agent-base' is ready for production use
```

### Step 3: Clone Production Template

```bash
# Clone to production name
tart clone expo-agent-base expo-free-agent-tahoe-26.2-xcode-expo-54-secure

# Verify
tart list | grep secure
```

### Step 4: Update Controller

```bash
# Edit packages/controller/.env
cd packages/controller
echo "BASE_IMAGE_ID=expo-free-agent-tahoe-26.2-xcode-expo-54-secure" >> .env

# Restart controller
bun run dev
```

### Step 5: Test End-to-End

```bash
# Submit test build with real signing cert
cd cli
bun src/index.ts submit /path/to/test-app \
  --certs /path/to/certs.zip \
  --cert-password your-p12-password

# Monitor build
bun src/index.ts status <build-id>
bun src/index.ts logs <build-id>

# Verify IPA signature
codesign -vv /path/to/downloaded.ipa
```

---

## Security Model

### Before (Insecure)
❌ Host downloads certs (plaintext on disk)
❌ Host SCPs certs to VM
❌ Host can SSH into VM (password: 'admin')
❌ Hardcoded keychain password

### After (Secure)
✅ Host never sees certs
✅ Host cannot SSH (password randomized)
✅ Random keychain password per-build
✅ Certs deleted immediately after install
✅ VM bootstrap authenticated via API key

---

## File Inventory

### New Files (11)
1. `vm-setup/free-agent-vm-bootstrap` - VM bootstrap script
2. `vm-setup/install-signing-certs` - Cert installation helper
3. `vm-setup/vm-monitor.sh` - Telemetry agent
4. `vm-setup/com.expo.free-agent.bootstrap.plist` - LaunchDaemon
5. `vm-setup/install-to-vm-template.sh` - **Installation automation**
6. `vm-setup/test-vm-bootstrap.sh` - **Testing automation**
7. `vm-setup/BOOTSTRAP-README.md` - Documentation
8. `plans/secure-cert-handling-tracker.md` - Implementation tracker
9. `SECURE_CERT_STATUS.md` - **This file**

### Modified Files (5)
1. `packages/controller/src/api/builds/index.ts` - Added `/certs-secure` + telemetry endpoints
2. `packages/controller/src/middleware/auth.ts` - Enhanced worker access validation
3. `packages/controller/src/domain/Config.ts` - Added BASE_IMAGE_ID config
4. `free-agent/Sources/BuildVM/TartVMManager.swift` - Pass env vars, secure bootstrap
5. `vm-setup/free-agent-run-job` - Enabled code signing

---

## Verification Commands

```bash
# Verify all code changes merged
git log --oneline -10
# Should show:
# - bb711c6 Add secure VM telemetry system
# - 3c9054b Add npx installer and BASE_IMAGE_ID configuration
# - 6abd934 Fix all critical security blockers
# - 0fcf90a Implement secure certificate handling

# Verify scripts exist
ls -lh vm-setup/free-agent* vm-setup/install* vm-setup/vm-monitor.sh

# Verify controller endpoint
cd packages/controller
grep -n "certs-secure" src/api/builds/index.ts

# Verify Swift changes
grep -n "waitForBootstrapComplete" ../free-agent/Sources/BuildVM/TartVMManager.swift
```

---

## Next Action

**You are here:** ✅ Code complete, awaiting VM template installation

**Next step:** Run installation script
```bash
./vm-setup/install-to-vm-template.sh <your-vm-name>
```

Once VM template is ready, all workers will automatically use secure certificate handling on their next build. No worker reconfiguration needed - the baseImageId is provided by the controller dynamically.

---

## Questions?

See comprehensive documentation:
- `vm-setup/BOOTSTRAP-README.md` - Detailed technical documentation
- `plans/secure-cert-handling-tracker.md` - Full implementation plan
- `vm-setup/install-to-vm-template.sh --help` - Installation help
- `vm-setup/test-vm-bootstrap.sh --help` - Testing help
