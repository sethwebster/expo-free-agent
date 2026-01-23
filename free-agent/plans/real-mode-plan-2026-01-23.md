# Real Mode Implementation Plan

## Current State Analysis

### What Works
- Controller: 30 tests passing (registration, polling, file download/upload, job assignment)
- CLI: 28 tests passing
- Swift Free Agent: Compiles with all 5 bugs fixed
- E2E test: Works with mock worker (proves API contract is solid)

### What Doesn't Exist
- No macOS VM (the actual build environment)
- Swift app has never run against real controller
- No real Expo build has ever executed
- No SSH key pair for VM communication
- No VM image with Xcode installed

---

## Critical Path Analysis

### The Dependency Chain

```
Controller <--HTTP--> Swift Worker <--SSH--> macOS VM <--Xcode--> IPA
    |                     |                      |
  WORKING            COMPILES BUT           DOESN'T EXIST
                     NEVER TESTED
```

**Observation:** The Swift worker is the untested middle layer. Testing it against the controller requires either:
1. A real VM (expensive, slow to set up)
2. A mock SSH target (simpler, proves Swift HTTP layer works)

### Recommended Strategy: Option B (Test Incrementally)

**Rationale:**
- VM creation is complex (IPSW download, macOS install, Xcode install = 3-4 hours minimum)
- If Swift worker has bugs in HTTP layer, we waste time debugging with VM overhead
- Testing Swift -> Controller first isolates the unknown

---

## Prioritized Task List

### Phase 1: Prove Swift Worker HTTP Layer (1-2 hours)

**Goal:** Verify WorkerService.swift correctly talks to controller

#### Task 1.1: Run Controller Locally
```bash
cd packages/controller
bun run dev
```
- Proves: Controller starts, accepts connections
- Complexity: Simple
- Can fail: Port conflict, missing deps

#### Task 1.2: Build and Run Swift App
```bash
cd free-agent
swift build -c release
.build/release/FreeAgent
```
- Proves: App compiles and launches
- Complexity: Simple
- Can fail: Xcode version mismatch, signing issues

#### Task 1.3: Configure Swift App to Point at Local Controller
- Set controllerURL to `http://localhost:3000`
- Set apiKey to match controller's configured key
- Proves: Settings UI works
- Complexity: Simple

#### Task 1.4: Test Registration
- Click "Start Worker" in menu bar
- Check controller logs for registration request
- Proves: WorkerService.registerWorker() works
- Complexity: Simple
- Can fail: JSON format mismatch, wrong headers, URL encoding

#### Task 1.5: Test Polling (Without VM)
- Worker should poll controller every 30s
- Submit a build via CLI (it will fail, but assignment should work)
- Check: Worker receives job assignment
- Proves: pollForJob() works, job JSON parsing correct
- Complexity: Simple
- Can fail: snake_case vs camelCase mismatches

**Expected Outcome:** Worker registers, polls, receives job, then fails when trying to create VM. This is good - we know the HTTP layer works.

---

### Phase 2: Create Mock Build Flow (2-3 hours)

**Goal:** Test the full flow without a real VM

#### Task 2.1: Create Mock SSH Target
Instead of a full VM, create a simple mock that accepts SSH commands:

```bash
# Run on localhost with a test user
# Configure Swift app to use localhost:22 + current user
```

OR

Create a "dry run" mode in VMManager that skips VM creation and returns mock results.

- Proves: Download -> execute -> upload flow works
- Complexity: Medium
- Can fail: File paths, multipart upload format

#### Task 2.2: Test File Download
- Submit build with source.zip
- Worker polls, gets job with source_url
- Worker downloads source to temp directory
- Proves: downloadBuildPackage() works, X-Worker-Id header correct
- Complexity: Simple
- Can fail: Stream handling, auth headers

#### Task 2.3: Test Result Upload
- Create fake IPA file
- Call uploadBuildResult() with mock BuildResult
- Verify controller receives file and marks build complete
- Proves: Multipart upload format matches controller expectations
- Complexity: Medium
- Can fail: Field names (build_id vs buildId), Content-Type

#### Task 2.4: Test Error Reporting
- Simulate build failure
- Verify reportJobFailure() correctly updates build status
- Proves: Error flow works
- Complexity: Simple

---

### Phase 3: Create macOS VM (4-6 hours)

**Goal:** Have a VM that can run xcodebuild

#### Task 3.1: Download macOS IPSW
```bash
# Get latest Sonoma IPSW (~13GB)
# Use Apple's official download or ipsw.me
```
- Proves: Nothing yet
- Complexity: Simple (but slow download)
- Can fail: Network, disk space

#### Task 3.2: Create VM Using Virtualization.framework
- Write setup script using VZMacOSInstaller
- Install macOS in VM
- Proves: VM infrastructure works
- Complexity: Hard (this is the biggest unknown)
- Can fail: Entitlements, hardware model, memory allocation

#### Task 3.3: Configure VM for SSH
- Enable Remote Login in VM
- Create `builder` user
- Generate and install SSH key pair
- Test: `ssh builder@192.168.64.x 'echo hello'`
- Proves: SSH communication works
- Complexity: Medium
- Can fail: NAT networking, firewall, key permissions

#### Task 3.4: Install Xcode in VM
```bash
ssh builder@vm 'xcode-select --install'
# Or download full Xcode from Apple Developer
```
- Proves: Build environment ready
- Complexity: Medium (but time consuming ~1 hour)
- Can fail: Apple ID auth, disk space (Xcode is 20GB+)

#### Task 3.5: Install Node.js and EAS CLI
```bash
ssh builder@vm 'brew install node'
ssh builder@vm 'npm install -g eas-cli'
```
- Proves: Expo toolchain ready
- Complexity: Simple

---

### Phase 4: Integration Test (2-3 hours)

**Goal:** Real build end-to-end

#### Task 4.1: Create Minimal Expo App
```bash
npx create-expo-app@latest test-app
cd test-app
npx expo prebuild --platform ios
```
- Proves: We have a buildable project
- Complexity: Simple

#### Task 4.2: Submit Build via CLI
```bash
fa submit --source ./test-app --platform ios
```
- Proves: CLI packages correctly
- Can fail: Zip format, app.json parsing

#### Task 4.3: Watch Full Flow
1. Controller receives build
2. Worker polls and claims it
3. Worker downloads source
4. Worker creates/starts VM (or reuses)
5. Worker copies source to VM via SCP
6. Worker runs `eas build --local` in VM
7. Worker extracts IPA
8. Worker uploads to controller
9. CLI downloads result

- Proves: The system works
- Complexity: Everything must work together
- Can fail: Any layer

---

## Immediate Blockers

### 1. VM Creation (Biggest Blocker)
- Apple's Virtualization.framework requires:
  - Entitlements (already have)
  - Hardware model file (must be created on first run)
  - macOS IPSW (~13GB download)
  - Xcode installation in VM (~20GB)

**Mitigation:** Test HTTP layer first, defer VM until we know Swift<->Controller works.

### 2. SSH Key Generation
- XcodeBuildExecutor expects key at `~/.ssh/free_agent_ed25519`
- Need to generate and distribute to VM

**Mitigation:** Simple, can do during VM setup.

### 3. VM Networking
- NAT IP `192.168.64.2` is assumed in code
- May not be correct for every setup

**Mitigation:** Make configurable in settings.

### 4. Certificate Signing (Blocked for Real Builds)
- Need real Apple Developer certs for signed IPA
- Can test with simulator build first (no signing needed)

**Mitigation:** Test unsigned builds first, add signing later.

---

## Decision: What to Do First

### Recommended: Phase 1 + Phase 2 First

**Why:**
1. Takes 3-5 hours vs 4-6 hours for VM alone
2. Proves the Swift code is correct before investing in VM
3. Easier to debug HTTP issues without VM complexity
4. If bugs exist, faster to fix and retest

### If Phase 1 Succeeds With No Bugs:
- Proceed to Phase 3 (VM creation)
- Confidence that Swift worker is solid

### If Phase 1 Reveals Bugs:
- Fix Swift code
- Retest against controller
- Much faster iteration than debugging with VM

---

## Estimated Timeline

| Phase | Duration | Cumulative |
|-------|----------|------------|
| Phase 1: HTTP Layer | 1-2 hours | 2 hours |
| Phase 2: Mock Build | 2-3 hours | 5 hours |
| Phase 3: VM Setup | 4-6 hours | 11 hours |
| Phase 4: Integration | 2-3 hours | 14 hours |

**Total:** 10-14 hours to fully working system

---

## Unresolved Questions

1. **VM IP discovery:** How to reliably get VM's IP after NAT assignment?
2. **Xcode license:** Can VM accept Xcode license non-interactively?
3. **VM persistence:** Reuse VMs or create fresh each build? Trade-off between speed and cleanliness.
4. **Cert handling:** How to transfer P12 securely? Password in plaintext file?
5. **Build timeout:** 120 min default enough for large Expo apps?
