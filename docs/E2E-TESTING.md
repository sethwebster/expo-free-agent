# End-to-End Testing Guide

Comprehensive guide for running E2E tests with real and mocked components.

---

## Test Levels

### 1. Mock Worker Test (`test-e2e.sh`)

**What it tests:**
- ✅ Controller API endpoints
- ✅ Build queue management
- ✅ Worker registration/polling
- ✅ Token rotation
- ✅ Database transactions
- ✅ File upload/download
- ✅ Race condition prevention

**What it mocks:**
- ❌ VM creation/lifecycle
- ❌ Bootstrap script execution
- ❌ Real build execution
- ❌ Certificate handling
- ❌ Tart integration

**Runtime:** ~1 minute

**Prerequisites:**
- Elixir/PostgreSQL
- Bun runtime

**Usage:**
```bash
./test-e2e.sh
```

---

### 2. Full VM Test (`test-e2e-vm.sh`)

**What it tests:**
- ✅ **Real Tart VM creation/deletion**
- ✅ **Bootstrap script execution inside VM**
- ✅ **OTP → VM token authentication**
- ✅ **Certificate fetching (iOS)**
- ✅ **Certificate installation in VM keychain**
- ✅ **Real build execution (xcodebuild/gradle)**
- ✅ **Artifact upload from VM**
- ✅ **VM cleanup after completion**
- ✅ All items from Mock Worker Test

**What it validates:**
- VM isolation (each build in ephemeral VM)
- Bootstrap script phases (auth, cert fetch, build)
- Real certificate handling
- Actual Xcode/Gradle execution
- Log streaming from VM
- Progress updates during build

**Runtime:** 15-30 minutes (real builds)

**Prerequisites:**
- All Mock Worker prerequisites
- Tart installed: `brew install cirruslabs/cli/tart`
- Base VM image: `tart pull ghcr.io/sethwebster/expo-free-agent-base:latest`
  - Image is pre-configured with bootstrap scripts
  - No additional setup required

**Usage:**
```bash
./test-e2e-vm.sh
```

---

## VM Setup

### Development Workflow (Recommended)

For testing local changes to bootstrap scripts, create a local test image:

```bash
# First time setup
./vm-setup/setup-local-test-image.sh

# After making changes to vm-setup/*.sh scripts
./vm-setup/setup-local-test-image.sh  # Update local image
./test-e2e-vm.sh                       # Test with updated scripts
```

This creates `expo-free-agent-base-local` with your latest scripts. The E2E test automatically detects and uses this local image.

**Benefits:**
- ✅ No need to push to registry for testing
- ✅ Fast iteration on bootstrap scripts
- ✅ Test exactly what you changed

---

### Production Workflow

For testing against the published base image:

```bash
# Pull from GitHub Container Registry
tart pull ghcr.io/sethwebster/expo-free-agent-base:latest
```

The image includes:
- macOS Sequoia 15.2
- Xcode 16.2
- Build tools (Node, Bun, CocoaPods)
- Bootstrap scripts and LaunchDaemon
- Certificate handling infrastructure

If both local and registry images exist, tests prefer the local image.

---

### How It Works

The test automatically:
1. Checks for `expo-free-agent-base-local` (your local test image)
2. Falls back to `ghcr.io/sethwebster/expo-free-agent-base:latest` (registry)
3. Clones the selected image for each test run
4. Mounts bootstrap script
5. VM auto-runs bootstrap on boot
6. Build executes inside isolated VM
7. VM destroyed after completion

---

## Test Certificates

For iOS testing, you can use real certificates or generate test certificates.

### Generate Test Certificates

```bash
./test/generate-test-certs.sh .test-certs
```

This creates:
- `cert.p12` - PKCS#12 bundle
- `test.mobileprovision` - Dummy provisioning profile
- `credentials.json` - JSON for API upload

**Note:** Self-signed certificates won't produce installable IPAs, but validate the certificate handling flow.

### Use Real Certificates

For production-like testing, export real certificates from Xcode:

1. Open Xcode → Preferences → Accounts
2. Select team → Manage Certificates
3. Right-click certificate → Export
4. Save as `.p12` with password
5. Export provisioning profile from Apple Developer Portal

---

## Architecture Tested

The full VM test validates this complete flow:

```
Developer
   ↓ (submits build)
Controller (Elixir)
   ↓ (assigns to worker)
Real Worker (TypeScript)
   ↓ (clones VM)
Tart VM (macOS)
   ├─ bootstrap.sh runs automatically
   │  ├─ Phase 1: Load config from mount
   │  ├─ Phase 2: Authenticate (OTP → VM token)
   │  ├─ Phase 3: Fetch certificates (iOS)
   │  ├─ Phase 4: Install certificates
   │  ├─ Phase 5: Signal ready
   │  ├─ Phase 6: Download source
   │  ├─ Phase 7: Execute build (xcodebuild/gradle)
   │  ├─ Phase 8: Upload logs
   │  └─ Phase 9: Upload artifact
   ↓ (build completes)
Worker destroys VM
   ↓ (certs erased)
Controller
   ↓ (artifact available)
Developer
```

---

## Running Tests

### Quick Mock Test

```bash
# Fast integration test (no VMs)
./test-e2e.sh
```

**Expected output:**
```
[SUCCESS]  All E2E Tests Passed! ✓
  - Build submitted
  - Worker polled and received job
  - Build completed
  - Artifact downloaded
```

### Full VM Test

```bash
# Real VM test (slow but complete)
./test-e2e-vm.sh
```

**Expected output:**
```
[INFO] Starting real worker with Tart VMs
[INFO] Cloning VM from sequoia-vanilla...
[INFO] Starting VM...
[INFO] Waiting for VM bootstrap...
[INFO] VM progress: authenticating (20%) - Authenticating with controller...
[INFO] VM progress: fetching_certs (40%) - Fetching iOS certificates...
[INFO] VM progress: installing_certs (50%) - Installing certificates...
[INFO] VM progress: ready (60%) - Ready for build...
[INFO] VM progress: downloading_source (70%) - Downloading source...
[INFO] VM progress: building (80%) - Running xcodebuild...
[INFO] VM progress: uploading_artifacts (90%) - Uploading IPA...
[INFO] VM progress: completed (100%) - Build completed successfully
[SUCCESS]  Build completed
[INFO] Cleaning up VM...
[SUCCESS]  Full E2E VM Tests Passed! ✓
```

---

## Debugging Failed Tests

### Check Controller Logs

```bash
tail -f .test-e2e-vm/controller.log
```

Look for:
- Database connection errors
- Authentication failures
- File storage errors

### Check Worker Logs

```bash
tail -f .test-e2e-vm/worker.log
```

Look for:
- Tart command failures
- VM startup errors
- Build execution failures

### Check VM Logs (while running)

```bash
# List running VMs
tart list

# Connect to running VM
tart ip build-<build-id>
ssh admin@<vm-ip>

# Inside VM, check logs
tail -f /var/log/free-agent-bootstrap.log
tail -f /var/log/build.log
```

### Inspect Build Config

```bash
# After test failure, check mounted config
cat .real-worker/*/build-config/build-config.json
cat .real-worker/*/build-config/progress.json
cat .real-worker/*/build-config/vm-ready
```

### Manual Cleanup

If test fails and leaves orphaned VMs:

```bash
# List VMs
tart list

# Stop and delete
tart stop build-<id>
tart delete build-<id>
```

---

## Performance Benchmarks

### Mock Worker Test
- **Setup:** 2-3 seconds (database, controller start)
- **Build cycle:** 2-5 seconds (simulated)
- **Total:** ~1 minute

### Full VM Test
- **Setup:** 5-10 seconds
- **VM clone:** 10-20 seconds
- **VM boot:** 5-10 seconds
- **Bootstrap:** 30-60 seconds (auth + certs)
- **Build execution:** 15-25 minutes (real iOS build)
- **Cleanup:** 5-10 seconds
- **Total:** 20-30 minutes

---

## CI/CD Integration

### GitHub Actions (Mock Test)

```yaml
name: E2E Tests
on: [push, pull_request]

jobs:
  e2e-mock:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-elixir@v1
        with:
          elixir-version: '1.18'
          otp-version: '28'
      - uses: oven-sh/setup-bun@v1

      - name: Start PostgreSQL
        run: |
          docker compose up -d postgres

      - name: Run E2E Mock Test
        run: ./test-e2e.sh
```

### Self-Hosted Runner (Full VM Test)

For full VM tests, use macOS self-hosted runner:

```yaml
jobs:
  e2e-vm:
    runs-on: [self-hosted, macOS, tart]
    steps:
      - uses: actions/checkout@v4

      - name: Run E2E VM Test
        run: ./test-e2e-vm.sh
        timeout-minutes: 40
```

---

## Comparison: Mock vs Real

| Feature | Mock Test | VM Test |
|---------|-----------|---------|
| **VM Creation** | ❌ Mocked | ✅ Real Tart VMs |
| **Bootstrap Script** | ❌ Skipped | ✅ Executed in VM |
| **OTP Auth** | ❌ Simulated | ✅ Real HTTP exchange |
| **Certificates** | ❌ Not tested | ✅ Fetched & installed |
| **Build Execution** | ❌ `sleep(2s)` | ✅ Real xcodebuild/gradle |
| **Artifacts** | ❌ Fake zip (345 bytes) | ✅ Real IPA/APK (50-200MB) |
| **VM Isolation** | ❌ Not validated | ✅ Each build in ephemeral VM |
| **Runtime** | ⚡ 1 minute | 🐢 20-30 minutes |
| **CI-Friendly** | ✅ Yes (any OS) | ⚠️ macOS only |

---

## Troubleshooting

### "Tart not found"

```bash
brew install cirruslabs/cli/tart
```

### "Base VM image not found"

```bash
# Check available images
tart list

# Pull base image
tart pull ghcr.io/sethwebster/expo-free-agent-base:latest
tart clone ghcr.io/sethwebster/expo-free-agent-base:latest sequoia-vanilla
```

### "VM bootstrap timeout"

Check that LaunchAgent is set up correctly in VM:
```bash
# Inside VM
cat ~/Library/LaunchAgents/com.expo.free-agent-bootstrap.plist
launchctl list | grep free-agent
```

### "Certificate installation failed"

Verify `/usr/local/bin/install-signing-certs` exists in VM and is executable.

### "Build failed: xcodebuild not found"

Ensure Xcode is installed in VM:
```bash
# Inside VM
xcode-select -p
xcodebuild -version
```

---

## Contributing

When adding new features, update both test suites:

1. **Mock test:** Add fast validation of API contract
2. **VM test:** Add real integration test if feature involves VM

**Example:** Adding Android support
```bash
# 1. Update mock worker to handle android platform
# 2. Update real worker to use gradle instead of xcodebuild
# 3. Create android base VM image
# 4. Update test-e2e-vm.sh to test android builds
```

---

## See Also

- [Architecture Documentation](../ARCHITECTURE.md)
- [Bootstrap Script](../free-agent/Sources/WorkerCore/Resources/free-agent-bootstrap.sh)
- [VM Setup Guide](../vm-setup/README.md)
- [Controller API](../packages/controller-elixir/API.md)
