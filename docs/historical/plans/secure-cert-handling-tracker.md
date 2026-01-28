# Secure Certificate Handling - Implementation Tracker

**Created:** 2026-01-26
**Status:** Planning → Implementation
**Priority:** P0 - Required for production security

---

## Executive Summary

**Problem:** Current architecture allows host machines to access signing certificates, creating security risk for community workers.

**Solution:** VM boots → randomizes password → fetches certs directly from controller → installs → host CANNOT access.

**Security Impact:**
- ✅ Host never sees plaintext certs
- ✅ VM inaccessible after boot (SSH blocked)
- ✅ Random keychain password per-build
- ✅ Certs deleted after installation

---

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│ Host Machine (Worker)                           │
│  - Boots VM with env vars only                  │
│  - Cannot SSH (password randomized)             │
│  - Monitors via Tart CLI only                   │
│  - Never downloads certs                        │
└─────────────────┬───────────────────────────────┘
                  │
                  │ tart run --env BUILD_ID=...
                  │              --env API_KEY=...
                  │
┌─────────────────▼───────────────────────────────┐
│ VM (Isolated)                                   │
│  1. Boot → randomize admin password             │
│  2. Fetch certs via HTTPS from controller       │
│  3. Install with random keychain password       │
│  4. Delete cert files immediately               │
│  5. Run build with installed certs              │
│  6. Upload results                              │
└─────────────────┬───────────────────────────────┘
                  │
                  │ HTTPS: GET /api/builds/:id/certs-secure
                  │        Headers: X-Worker-Id, X-Build-Id, X-API-Key
                  │
┌─────────────────▼───────────────────────────────┐
│ Controller                                      │
│  - Validates worker owns build                  │
│  - Generates random keychain password           │
│  - Returns: { p12: "base64", password: "...",   │
│              keychainPassword: "random...",     │
│              profiles: [...] }                  │
└─────────────────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 1: VM Template Preparation

**Goal:** Create secure VM template with bootstrap infrastructure

#### 1.1 Bootstrap Script
- [ ] **File:** `vm-setup/free-agent-vm-bootstrap`
- [ ] **Install to:** `/usr/local/bin/free-agent-vm-bootstrap` (inside VM)
- [ ] **Responsibilities:**
  - [ ] Randomize admin password (32-byte secure random)
  - [ ] Remove SSH authorized_keys
  - [ ] Validate env vars (BUILD_ID, WORKER_ID, API_KEY, CONTROLLER_URL)
  - [ ] Fetch certs from controller endpoint
  - [ ] Call cert installer
  - [ ] Shred cert files
  - [ ] Signal ready (`/tmp/free-agent-ready`)
- [ ] **Dependencies:** curl, openssl, jq
- [ ] **Test:** Manual run with mock env vars

**Script Structure:**
```bash
#!/bin/bash
set -e
# 1. Password randomization
NEW_PASSWORD=$(openssl rand -base64 32)
echo "admin:$NEW_PASSWORD" | sudo chpasswd
rm -f ~/.ssh/authorized_keys

# 2. Fetch certs
curl -H "X-API-Key: $API_KEY" \
     -H "X-Worker-Id: $WORKER_ID" \
     -H "X-Build-Id: $BUILD_ID" \
     "$CONTROLLER_URL/api/builds/$BUILD_ID/certs-secure" \
     -o /tmp/certs-secure.json

# 3. Install
/usr/local/bin/install-signing-certs --certs /tmp/certs-secure.json

# 4. Cleanup
shred -u /tmp/certs-secure.json

# 5. Signal ready
touch /tmp/free-agent-ready
```

#### 1.2 Certificate Installer
- [ ] **File:** `vm-setup/install-signing-certs`
- [ ] **Install to:** `/usr/local/bin/install-signing-certs` (inside VM)
- [ ] **Responsibilities:**
  - [ ] Parse JSON cert bundle
  - [ ] Decode base64 P12
  - [ ] Create keychain with random password
  - [ ] Import P12 with user-provided password
  - [ ] Set partition list (allow codesign)
  - [ ] Install provisioning profiles
  - [ ] Shred P12 file
  - [ ] Verify installation
- [ ] **Dependencies:** security, jq, base64
- [ ] **Test:** Run with test cert JSON

**Script Structure:**
```bash
#!/bin/bash
# Parse --certs argument
# Extract: p12, p12Password, keychainPassword, profiles
# Decode base64 → files
# security create-keychain -p "$KEYCHAIN_PASS" build.keychain-db
# security import cert.p12 -k build.keychain-db -P "$P12_PASS"
# security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASS"
# Install profiles to ~/Library/MobileDevice/Provisioning Profiles/
# shred -u cert.p12
# Verify: security find-identity -v -p codesigning
```

#### 1.3 LaunchDaemon
- [ ] **File:** `vm-setup/com.expo.free-agent.bootstrap.plist`
- [ ] **Install to:** `/Library/LaunchDaemons/` (inside VM)
- [ ] **Configuration:**
  - [ ] RunAtLoad: true
  - [ ] ProgramArguments: /usr/local/bin/free-agent-vm-bootstrap
  - [ ] StandardOutPath: /tmp/free-agent-bootstrap.log
  - [ ] EnvironmentVariables: (populated by Tart --env)
- [ ] **Load:** `sudo launchctl load com.expo.free-agent.bootstrap.plist`
- [ ] **Test:** Boot VM, check log, verify password changed

**Plist:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.expo.free-agent.bootstrap</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/free-agent-vm-bootstrap</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/free-agent-bootstrap.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/free-agent-bootstrap.log</string>
</dict>
</plist>
```

#### 1.4 Template Preparation Checklist
- [ ] Boot base Tart VM
- [ ] Install dependencies: `brew install jq`
- [ ] Copy `free-agent-vm-bootstrap` → `/usr/local/bin/`
- [ ] Copy `install-signing-certs` → `/usr/local/bin/`
- [ ] `chmod +x /usr/local/bin/free-agent-vm-bootstrap`
- [ ] `chmod +x /usr/local/bin/install-signing-certs`
- [ ] Copy plist → `/Library/LaunchDaemons/`
- [ ] `sudo launchctl load /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist`
- [ ] Test bootstrap with mock env vars
- [ ] Verify bootstrap log created
- [ ] Verify password randomization works
- [ ] Shutdown VM cleanly
- [ ] Clone to production template: `tart clone <vm> expo-free-agent-tahoe-26.2-xcode-expo-54-secure`

---

### Phase 2: Controller Changes

**Goal:** Secure cert delivery endpoint

#### 2.1 New Endpoint: `/api/builds/:id/certs-secure`
- [ ] **File:** `packages/controller/src/api/builds/index.ts`
- [ ] **Route:** `GET /api/builds/:id/certs-secure`
- [ ] **Middleware:**
  - [ ] `requireApiKey(db)` - Validates X-API-Key header
  - [ ] `requireWorkerAccess(db)` - Validates X-Worker-Id + X-Build-Id
- [ ] **Response Structure:**
  ```typescript
  {
    p12: string              // base64 encoded P12 file
    p12Password: string      // User-provided P12 password
    keychainPassword: string // Random 24-byte keychain password
    provisioningProfiles: string[] // Array of base64 profiles
  }
  ```
- [ ] **Security:**
  - [ ] Verify worker owns build (worker_id matches)
  - [ ] Generate random keychain password per request
  - [ ] Return 404 if certs don't exist
  - [ ] Return 403 if worker doesn't own build
- [ ] **Test:** curl with headers, verify JSON response

**Code Location:** After line 310 in `packages/controller/src/api/builds/index.ts`

**Implementation:**
```typescript
router.get(
  '/:id/certs-secure',
  requireApiKey(db),
  requireWorkerAccess(db),
  async (req, res) => {
    const buildId = req.params.id
    const build = db.getBuild(buildId)

    if (!build?.certs_path) {
      return res.status(404).json({ error: 'Certs not found' })
    }

    // Generate random keychain password
    const keychainPassword = crypto.randomBytes(24).toString('base64')

    // Read and unzip certs
    const certsZip = await storage.readBuildCerts(build.certs_path)
    const unzipped = await unzipCerts(certsZip) // Helper to extract

    return res.json({
      p12: unzipped.p12.toString('base64'),
      p12Password: unzipped.password || '',
      keychainPassword,
      provisioningProfiles: unzipped.profiles.map(p => p.toString('base64'))
    })
  }
)
```

#### 2.2 Enhanced Middleware: `requireWorkerAccess`
- [ ] **File:** `packages/controller/src/middleware/auth.ts`
- [ ] **Changes:**
  - [ ] Add `X-Build-Id` header requirement
  - [ ] Verify worker owns the specified build
  - [ ] Return 401 if headers missing
  - [ ] Return 403 if worker doesn't own build
- [ ] **Test:** Valid worker + build → 200, Mismatched → 403

**Code Location:** Around line 45 in `packages/controller/src/middleware/auth.ts`

**Implementation:**
```typescript
export function requireWorkerAccess(db: DatabaseService) {
  return (req: Request, res: Response, next: NextFunction) => {
    const workerId = req.headers['x-worker-id'] as string
    const buildId = req.headers['x-build-id'] as string

    if (!workerId || !buildId) {
      return res.status(401).json({
        error: 'Missing X-Worker-Id or X-Build-Id header'
      })
    }

    const build = db.getBuild(buildId)
    if (!build || build.worker_id !== workerId) {
      return res.status(403).json({
        error: 'Worker not assigned to this build'
      })
    }

    next()
  }
}
```

#### 2.3 Helper: Unzip Certs
- [ ] **File:** `packages/controller/src/services/FileStorage.ts` (or new helper)
- [ ] **Function:** `unzipCerts(zipBuffer: Buffer): Promise<CertsBundle>`
- [ ] **Extract:**
  - [ ] `cert.p12` or `*.p12` → p12 buffer
  - [ ] `password.txt` → p12Password string (optional)
  - [ ] `*.mobileprovision` → profiles array
- [ ] **Return:**
  ```typescript
  interface CertsBundle {
    p12: Buffer
    password: string
    profiles: Buffer[]
  }
  ```
- [ ] **Test:** Unzip test cert bundle, verify structure

**Implementation:**
```typescript
import AdmZip from 'adm-zip'

export async function unzipCerts(zipBuffer: Buffer): Promise<CertsBundle> {
  const zip = new AdmZip(zipBuffer)
  const entries = zip.getEntries()

  let p12: Buffer | null = null
  let password = ''
  const profiles: Buffer[] = []

  for (const entry of entries) {
    if (entry.entryName.endsWith('.p12')) {
      p12 = entry.getData()
    } else if (entry.entryName === 'password.txt') {
      password = entry.getData().toString('utf-8').trim()
    } else if (entry.entryName.endsWith('.mobileprovision')) {
      profiles.push(entry.getData())
    }
  }

  if (!p12) {
    throw new Error('No P12 certificate found in bundle')
  }

  return { p12, password, profiles }
}
```

#### 2.4 Testing Checklist
- [ ] Unit test: `requireWorkerAccess` middleware
  - [ ] Valid worker + build → next()
  - [ ] Missing headers → 401
  - [ ] Wrong worker → 403
- [ ] Unit test: `unzipCerts` helper
  - [ ] Valid zip → CertsBundle
  - [ ] No P12 → throws error
  - [ ] Optional password.txt → handles correctly
- [ ] Integration test: `/api/builds/:id/certs-secure`
  - [ ] Valid request → JSON with base64 certs
  - [ ] Invalid build ID → 404
  - [ ] Wrong worker → 403
  - [ ] Missing headers → 401

---

### Phase 3: Swift Worker Changes

**Goal:** Remove cert download, pass env vars to VM

#### 3.1 TartVMManager: Pass Environment Variables
- [ ] **File:** `free-agent/Sources/BuildVM/TartVMManager.swift`
- [ ] **Function:** `executeBuild(...)` around line 37
- [ ] **Changes:**
  - [ ] Add parameters: `buildId`, `workerId`, `controllerURL`, `apiKey`
  - [ ] Build `tart run` command with `--env` flags
  - [ ] Example: `tart run --no-graphics job-123 --env BUILD_ID=123 --env API_KEY=...`
  - [ ] Add `waitForBootstrapComplete()` helper
  - [ ] Monitor `/tmp/free-agent-ready` via `tart exec`
  - [ ] Remove SCP cert upload (line ~128-134)
- [ ] **Test:** Boot VM manually, verify env vars set

**Code Location:** Lines 37-150 in `free-agent/Sources/BuildVM/TartVMManager.swift`

**Implementation:**
```swift
public func executeBuild(
    sourceCodePath: URL,
    signingCertsPath: URL?, // Now optional - unused
    buildTimeout: TimeInterval,
    buildId: String?,
    workerId: String?,
    controllerURL: String?,
    apiKey: String?
) async throws -> BuildResult {
    var logs = ""
    var created = false

    do {
        let cloneId = buildId ?? "job-\(UUID().uuidString.prefix(8))"
        vmName = cloneId

        // Clone template
        logs += "Cloning VM from template: \(templateImage)...\n"
        try await executeCommand("\(tartPath) clone \(templateImage) \(cloneId)")
        created = true

        // Start VM with env vars for bootstrap
        logs += "Starting VM with secure bootstrap...\n"
        var startCmd = "\(tartPath) run --no-graphics \(cloneId)"

        if let buildId = buildId {
            startCmd += " --env BUILD_ID=\(buildId)"
        }
        if let workerId = workerId {
            startCmd += " --env WORKER_ID=\(workerId)"
        }
        if let apiKey = apiKey {
            startCmd += " --env API_KEY=\(apiKey)"
        }
        if let controllerURL = controllerURL {
            startCmd += " --env CONTROLLER_URL=\(controllerURL)"
        }

        try await executeCommandBackground(startCmd)
        logs += "✓ VM started\n"

        // Wait for bootstrap (password randomization + cert fetch)
        logs += "Waiting for VM bootstrap...\n"
        try await waitForBootstrapComplete(cloneId, timeout: 180)
        logs += "✓ Bootstrap complete - certs installed, SSH blocked\n"

        // Wait for IP (for SCP operations later)
        logs += "Waiting for VM IP...\n"
        vmIP = try await getVMIP(cloneId, timeout: ipTimeout)
        logs += "✓ VM IP: \(vmIP!)\n"

        // Upload source ONLY (no certs)
        logs += "Uploading source code...\n"
        try await uploadSource(sourceCodePath, to: cloneId)
        logs += "✓ Source uploaded\n"

        // Run build
        logs += "Executing build...\n"
        let buildResult = try await executeBuildInVM(cloneId, timeout: buildTimeout)
        logs += buildResult.logs

        // Download artifacts
        logs += "Downloading artifacts...\n"
        let artifacts = try await downloadArtifacts(from: cloneId)
        logs += "✓ Artifacts downloaded\n"

        return BuildResult(
            success: buildResult.success,
            logs: logs,
            artifactPath: artifacts
        )

    } catch {
        logs += "ERROR: \(error.localizedDescription)\n"
        throw VMError.buildFailed(message: logs)
    } finally {
        // Cleanup
        if created, let name = vmName {
            logs += "Cleaning up VM...\n"
            try? await executeCommand("\(tartPath) delete \(name)")
            logs += "✓ VM deleted\n"
        }
    }
}

// NEW: Wait for bootstrap completion
private func waitForBootstrapComplete(_ vmName: String, timeout: TimeInterval) async throws {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        // Check if bootstrap signal file exists
        let checkCmd = "\(tartPath) exec \(vmName) -- test -f /tmp/free-agent-ready"
        do {
            try await executeCommand(checkCmd)
            return // Success
        } catch {
            // Not ready yet, wait
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2s
        }
    }

    throw VMError.bootstrapTimeout
}
```

#### 3.2 VMError: Add Bootstrap Timeout
- [ ] **File:** `free-agent/Sources/BuildVM/TartVMManager.swift`
- [ ] **Enum:** `VMError`
- [ ] **Add case:** `case bootstrapTimeout`
- [ ] **Description:** "VM bootstrap timed out (password randomization or cert fetch failed)"

**Code Location:** Around line 362 in `free-agent/Sources/BuildVM/TartVMManager.swift`

**Implementation:**
```swift
public enum VMError: Error, LocalizedError {
    case cloneFailed(message: String)
    case startFailed(message: String)
    case bootstrapTimeout // NEW
    case ipTimeout
    case sshTimeout
    case buildFailed(message: String)
    case artifactNotFound
    case vmCleanupFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .bootstrapTimeout:
            return "VM bootstrap timed out - check /tmp/free-agent-bootstrap.log in VM"
        // ... other cases
        }
    }
}
```

#### 3.3 WorkerService: Remove Cert Download
- [ ] **File:** `free-agent/Sources/WorkerCore/WorkerService.swift`
- [ ] **Function:** `executeBuildJob(...)` around line 260
- [ ] **Changes:**
  - [ ] Remove `downloadSigningCertificates()` call (lines ~312-344)
  - [ ] Pass `nil` for `signingCertsPath` parameter
  - [ ] Pass `buildId`, `workerId`, `controllerURL`, `apiKey` to VMManager
- [ ] **Test:** Submit build, verify worker doesn't download certs

**Code Location:** Lines 260-344 in `free-agent/Sources/WorkerCore/WorkerService.swift`

**Implementation:**
```swift
private func executeBuildJob(_ job: BuildJob) async throws {
    updateStatus(.building)
    logger.log("Executing build job: \(job.id)")

    // Download source
    let sourcePath = try await downloadBuildSource(job)
    logger.log("✓ Source downloaded")

    // NO CERT DOWNLOAD - VM fetches directly now
    // OLD CODE REMOVED:
    // let certsPath = job.certs_url != nil
    //     ? try await downloadSigningCertificates(job)
    //     : nil

    // Execute build with VM fetching certs directly
    let result = try await vmManager.executeBuild(
        sourceCodePath: sourcePath,
        signingCertsPath: nil, // VM fetches via API now
        buildTimeout: TimeInterval(job.estimatedDuration ?? 3600),
        buildId: job.id,
        workerId: configuration.workerId,
        controllerURL: configuration.controllerURL,
        apiKey: configuration.apiKey
    )

    // Upload result
    if result.success {
        try await uploadBuildResult(job.id, artifactPath: result.artifactPath)
        logger.log("✓ Build succeeded")
    } else {
        try await reportJobFailure(job.id, error: result.logs)
        logger.log("✗ Build failed")
    }

    updateStatus(.idle)
}
```

#### 3.4 WorkerConfiguration: Ensure API Key Available
- [ ] **File:** `free-agent/Sources/WorkerCore/WorkerConfiguration.swift`
- [ ] **Verify:** `apiKey` field exists in struct
- [ ] **If missing:** Add `public let apiKey: String`
- [ ] **Test:** Configuration loads from settings

**Code Location:** Check struct definition

---

### Phase 4: Build Script Updates

**Goal:** Enable code signing in VM build script

#### 4.1 free-agent-run-job: Enable Signing
- [x] **File:** `vm-setup/free-agent-run-job`
- [x] **Lines:** 148-158 (xcodebuild archive)
- [x] **Changes:**
  - [x] Remove: `CODE_SIGNING_ALLOWED=NO`
  - [x] Remove: `CODE_SIGNING_REQUIRED=NO`
  - [x] Remove: `CODE_SIGN_IDENTITY=""`
  - [x] Add: `-allowProvisioningUpdates`
- [ ] **Test:** Run script in VM with installed cert, verify signed

**Code Location:** Lines 148-158 in `vm-setup/free-agent-run-job`

**Before:**
```bash
xcodebuild archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination generic/platform=iOS \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGN_ENTITLEMENTS="" \
    | tee -a "$OUT_DIR/xcodebuild.log"
```

**After:**
```bash
xcodebuild archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination generic/platform=iOS \
    -allowProvisioningUpdates \
    | tee -a "$OUT_DIR/xcodebuild.log"
```

#### 4.2 Export Options: Use Proper Signing
- [x] **File:** `vm-setup/free-agent-run-job`
- [x] **Lines:** 171-186 (ExportOptions.plist)
- [x] **Changes:**
  - [x] Method: development → ad-hoc
  - [x] signingStyle: manual → automatic
  - [x] Kept compileBitcode: false
  - [x] Kept stripSwiftSymbols: true
- [ ] **Test:** Export succeeds with signed IPA

**Before:**
```xml
<key>method</key>
<string>development</string>
<key>signingStyle</key>
<string>manual</string>
```

**After:**
```xml
<key>method</key>
<string>ad-hoc</string>
<key>signingStyle</key>
<string>automatic</string>
```

---

### Phase 5: Testing & Validation

#### 5.1 Unit Tests
- [ ] **Controller Tests:**
  - [ ] `requireWorkerAccess` middleware
    - [ ] ✅ Valid worker + build → passes
    - [ ] ✅ Missing X-Build-Id → 401
    - [ ] ✅ Wrong worker → 403
  - [ ] `unzipCerts` helper
    - [ ] ✅ Valid bundle → extracts correctly
    - [ ] ✅ Missing P12 → throws
    - [ ] ✅ Optional password → handles
  - [ ] `/api/builds/:id/certs-secure` endpoint
    - [ ] ✅ Valid request → JSON response
    - [ ] ✅ Random keychain password generated
    - [ ] ✅ Base64 encoding correct
- [ ] **Swift Tests:**
  - [ ] `waitForBootstrapComplete` timeout behavior
  - [ ] VMError descriptions

#### 5.2 Integration Tests

**Test 1: Bootstrap Script**
- [ ] Boot VM with test env vars
- [ ] Check `/tmp/free-agent-bootstrap.log`
- [ ] Verify password changed: `ssh admin@<vm-ip>` (should fail)
- [ ] Verify signal file: `/tmp/free-agent-ready` exists

**Test 2: Cert Fetch**
- [ ] Mock controller endpoint with test certs
- [ ] Boot VM with valid env vars
- [ ] Check bootstrap log for curl success
- [ ] Verify keychain created: `security list-keychains`
- [ ] Verify cert installed: `security find-identity -v -p codesigning`

**Test 3: End-to-End Build**
- [ ] Submit test Expo app with real signing cert
- [ ] Worker picks up job
- [ ] Verify worker doesn't download certs (check logs)
- [ ] VM boots and fetches certs directly
- [ ] Build completes with signing
- [ ] Download IPA
- [ ] Verify signature: `codesign -vv result.ipa`
- [ ] Verify provisioning profile embedded

**Test 4: Security Validation**
- [ ] After VM boot, attempt SSH from host (should fail)
- [ ] Check host filesystem for cert files (should not exist)
- [ ] Inspect VM via `tart exec` (certs should be deleted)
- [ ] Verify keychain password is random (not 'build123')

#### 5.3 Test Cert Creation
- [ ] Create test Apple Developer certificate
- [ ] Create test provisioning profile (ad-hoc or development)
- [ ] Export P12 with password
- [ ] Bundle: `test-certs.zip` containing:
  - [ ] `cert.p12`
  - [ ] `password.txt` (optional)
  - [ ] `test.mobileprovision`
- [ ] Use for testing

---

### Phase 6: Rollout

#### 6.1 Pre-Rollout Checklist
- [ ] All unit tests passing
- [ ] Integration tests passing
- [ ] End-to-end test with real cert successful
- [ ] Security validation complete
- [ ] Documentation updated
- [ ] Rollback plan prepared

#### 6.2 Rollout Steps

**Step 1: Prepare Secure VM Template**
- [ ] Clone existing template
- [ ] Install bootstrap scripts
- [ ] Install LaunchDaemon
- [ ] Test bootstrap manually
- [ ] Save as: `expo-free-agent-tahoe-26.2-xcode-expo-54-secure`
- [ ] Verify template works: `tart run <template> --env BUILD_ID=test`

**Step 2: Deploy Controller Changes**
- [ ] Deploy `/api/builds/:id/certs-secure` endpoint
- [ ] Deploy enhanced middleware
- [ ] Deploy helper functions
- [ ] Test with curl: `curl -H "X-API-Key:..." -H "X-Worker-Id:..." -H "X-Build-Id:..." <url>/api/builds/<id>/certs-secure`
- [ ] Verify JSON response structure

**Step 3: Update Worker Agent**
- [ ] Update TartVMManager to pass env vars
- [ ] Remove cert download from WorkerService
- [ ] Build and test locally
- [ ] Deploy to test worker machine

**Step 4: Validation Build**
- [ ] Submit real build with production cert
- [ ] Monitor worker logs (should skip cert download)
- [ ] Monitor VM bootstrap log
- [ ] Verify build succeeds
- [ ] Verify IPA signature
- [ ] Install IPA on physical device (ultimate test)

**Step 5: Gradual Rollout**
- [ ] Update 1 worker machine (yours)
- [ ] Run 3-5 test builds
- [ ] Monitor for issues
- [ ] Update 2-3 colleague workers
- [ ] Run more test builds
- [ ] If successful, update all workers

#### 6.3 Rollback Plan
- [ ] Keep old template available
- [ ] Keep old worker binary
- [ ] If issues:
  - [ ] Point workers back to old template
  - [ ] Redeploy old worker binary
  - [ ] Controller endpoint backward compatible (old endpoint still works)

---

## Security Analysis

### Attack Surface Reduction

**Before (Current):**
- ❌ Host downloads certs (plaintext on disk)
- ❌ Host SCPs certs to VM
- ❌ Host can SSH into VM (password: 'admin')
- ❌ SSH keys in authorized_keys
- ❌ Hardcoded keychain password

**After (Secure):**
- ✅ Host never sees certs
- ✅ Host cannot SSH (password randomized)
- ✅ No SSH keys work
- ✅ Random keychain password per-build
- ✅ Certs deleted immediately after install

### Remaining Attack Vectors

| Attack | Probability | Impact | Mitigation |
|--------|-------------|--------|------------|
| Hypervisor escape | Very Low | High | Tart/Apple hypervisor security, regular updates |
| Host root + memory read | Low | High | Document: Workers must be trusted machines |
| Network MITM | Low | Medium | HTTPS required, consider cert pinning |
| Compromised VM template | Low | High | Template checksums, secure distribution |
| LaunchDaemon bypass | Very Low | Medium | macOS SIP protection, requires root |

### Recommended Additional Security

**Phase 7 (Future):**
- [ ] Controller TLS cert pinning in VM
- [ ] VM template integrity verification (checksums)
- [ ] Encrypted logging (bootstrap logs contain sensitive info)
- [ ] Rate limiting on `/certs-secure` endpoint
- [ ] Audit logging for cert fetches

---

## Files Modified

### New Files (7)
1. ✅ `vm-setup/free-agent-vm-bootstrap` - VM bootstrap script
2. ✅ `vm-setup/install-signing-certs` - Cert installation helper
3. ✅ `vm-setup/com.expo.free-agent.bootstrap.plist` - LaunchDaemon
4. `packages/controller/src/api/builds/certs.ts` - NEW: Separate certs route file (optional)
5. `packages/controller/src/helpers/unzipCerts.ts` - Cert unzip helper
6. `free-agent/Tests/BuildVM/TartVMManagerTests.swift` - Unit tests (NEW)
7. `test/integration/secure-cert-flow.test.ts` - E2E test

### Modified Files (5)
1. `packages/controller/src/api/builds/index.ts` - Add `/certs-secure` endpoint
2. `packages/controller/src/middleware/auth.ts` - Enhance `requireWorkerAccess`
3. `free-agent/Sources/BuildVM/TartVMManager.swift` - Pass env vars, wait for bootstrap
4. `free-agent/Sources/WorkerCore/WorkerService.swift` - Remove cert download
5. `vm-setup/free-agent-run-job` - Enable code signing

---

## Open Questions

### Q1: P12 Password Handling
**Current:** User provides P12 password via CLI (`--cert-password`), stored in `password.txt` in cert bundle.

**Options:**
- A. Keep as-is (plaintext in bundle, deleted after install)
- B. Encrypt P12 password separately with VM's public key
- C. User re-enters password when build starts (UX friction)

**Decision:** ✅ A
**Rationale:** P12 password never touches host (User → Controller → VM via HTTPS → keychain → shredded). Window of exposure ~30s inside ephemeral VM. Alternatives add complexity without meaningful security improvement for threat model.

### Q2: VM Template Distribution
**Issue:** Workers need updated templates when Xcode/SDK changes. Current: Manual clone.

**Options:**
- A. Manual update (document process)
- B. Auto-download from controller (requires template storage/versioning)
- C. OCI registry (ghcr.io, like Tart's base images)

**Decision:** ✅ A (prototype) → C (production)
**Rationale:** Prototype with friends: manual updates acceptable, templates change rarely. Production with community: OCI registry battle-tested (Tart native support: `tart clone ghcr.io/you/expo-template:sdk-54`). Free hosting on GitHub Container Registry, version pinning, CDN bandwidth.

### Q3: Warm VM Pool
**Current:** Clone → build → destroy (clean but slow)

**Alternative:** Keep VMs warm between builds (faster)
- Requires: Password re-randomization between builds
- Requires: Keychain cleanup between builds
- Benefit: 30-60s boot time saved

**Decision:** ✅ One-shot (current)
**Rationale:** Simplicity wins. Guaranteed clean slate, smaller attack surface (VM only exists during build), no state management complexity. 30-60s boot overhead acceptable for prototype. Warm pool risks incomplete cleanup = cert leakage. Can optimize later if build time becomes bottleneck with real usage data.

### Q4: Network Cert Pinning
**Issue:** VM fetches certs via HTTPS. MITM possible if controller cert not pinned.

**Options:**
- A. Trust system CA bundle (standard HTTPS)
- B. Pin controller's TLS cert in VM bootstrap script
- C. Use mutual TLS (VM has client cert)

**Decision:** ✅ A (prototype) → B (production)
**Rationale:** Prototype with trusted network (localhost/VPN): standard HTTPS sufficient. Production over internet: pin cert fingerprint (`curl --pinnedpubkey sha256//ABC123...`) prevents MITM on compromised networks. Mutual TLS overkill for this use case.

### Q5: Bootstrap Failure Handling
**Issue:** If bootstrap fails (network, controller down, etc), how to handle?

**Options:**
- A. Timeout and fail build (current plan)
- B. Retry bootstrap N times with exponential backoff
- C. Fallback to old flow (download certs) if bootstrap fails

**Decision:** ✅ B (Retry with backoff)
**Rationale:** Network glitches happen (controller restart, DNS hiccup). Retry 3x with exponential backoff (5s, 15s, 45s = max 65s total) provides transparent resilience without being brittle. Still fails fast if controller truly down. Implementation: `for attempt in 1 2 3; do curl...; [ $? -eq 0 ] && break; sleep $((5 * 3**(attempt-1))); done`

---

## Success Criteria

### Must Have (Blocking)
- [ ] Host cannot SSH into VM after boot (tested)
- [ ] Host never sees plaintext certs (verified via filesystem check)
- [ ] Keychain password is random per-build (inspected via security CLI)
- [ ] Certs deleted from VM after installation (verified)
- [ ] Build succeeds with proper code signing (IPA signature valid)
- [ ] End-to-end test passes (submit → build → download → verify)

### Nice to Have (Post-MVP)
- [ ] Cert pinning implemented
- [ ] Template integrity verification
- [ ] Warm VM pool optimization
- [ ] Encrypted bootstrap logs
- [ ] Audit logging for cert fetches

---

## Timeline Estimate

| Phase | Effort | Dependencies |
|-------|--------|--------------|
| Phase 1: VM Template Prep | 4-6 hours | None |
| Phase 2: Controller Changes | 3-4 hours | None |
| Phase 3: Swift Worker Changes | 2-3 hours | None |
| Phase 4: Build Script Updates | 1 hour | Phase 1 |
| Phase 5: Testing & Validation | 4-6 hours | Phases 1-4 |
| Phase 6: Rollout | 2-4 hours | Phase 5 |
| **Total** | **16-24 hours** | |

---

## Status Tracking

**Current Phase:** [✅] Planning / [ ] Implementation / [ ] Testing / [ ] Rollout / [ ] Complete

**Blockers:**
- None identified

**Recent Updates:**
- 2026-01-26: Initial tracker created
- 2026-01-26: All 5 open questions resolved, ready for implementation
  - Q1: Keep P12 password as-is
  - Q2: Manual distribution (prototype) → OCI registry (production)
  - Q3: One-shot VM lifecycle (clone → build → destroy)
  - Q4: Standard HTTPS (prototype) → cert pinning (production)
  - Q5: Retry bootstrap 3x with exponential backoff
- 2026-01-26: Phase 4 implemented - Code signing enabled in VM build script
  - Removed CODE_SIGNING_ALLOWED=NO, CODE_SIGNING_REQUIRED=NO flags
  - Removed CODE_SIGN_IDENTITY="" and CODE_SIGN_ENTITLEMENTS=""
  - Added -allowProvisioningUpdates flag for automatic provisioning
  - Changed ExportOptions.plist: method development → ad-hoc
  - Changed ExportOptions.plist: signingStyle manual → automatic
  - Maintained compileBitcode: false and stripSwiftSymbols: true

---

## Notes & Lessons Learned

_Document issues encountered, solutions found, and gotchas discovered during implementation._

**Example:**
- Date: 2026-01-26
- Issue: LaunchDaemon didn't run on boot
- Root Cause: Plist ownership was wrong (needs root:wheel)
- Solution: `sudo chown root:wheel /Library/LaunchDaemons/*.plist`
