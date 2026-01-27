# Final Comprehensive Code Review: Secure Certificate Handling Architecture

**Date:** 2026-01-26
**Reviewer:** Claude Opus 4.5
**Scope:** End-to-end secure certificate handling across all 4 phases
**Verdict:** APPROVE WITH REQUIRED FIXES

---

## Executive Summary

The architecture achieves its stated security goal: **the host machine never accesses signing certificates**. The trust model is sound - VM fetches certs directly from controller over HTTPS using build-specific credentials. However, **15 critical/high issues** across phases must be fixed before production deployment.

### Issue Distribution by Phase

| Phase | Critical | High | Medium | Low |
|-------|----------|------|--------|-----|
| Phase 1 (VM Bootstrap) | 3 | 3 | 2 | 2 |
| Phase 2 (Controller) | 2 | 1 | 2 | 2 |
| Phase 3 (Swift Worker) | 3 | 1 | 3 | 2 |
| Phase 4 (Build Script) | 1 | 1 | 2 | 2 |
| **Cross-Phase** | **2** | **1** | **1** | **0** |
| **Total** | **11** | **7** | **10** | **8** |

---

## Architecture Analysis

### Security Goal Achievement

**Goal:** "Host cannot access signing certs"

**Analysis:**
- VM boots with env vars only (BUILD_ID, WORKER_ID, API_KEY, CONTROLLER_URL)
- Bootstrap script randomizes password immediately, blocking host SSH
- VM fetches certs directly from controller via HTTPS
- Certs are shredded after keychain installation
- Host never downloads, stores, or transmits certificates

**Verdict:** ACHIEVED - with caveats noted below

### Trust Model

```
User --> Controller --> [stores certs encrypted at rest]
                   \
                    --> VM (direct HTTPS fetch)
                   /
Host Worker ------/
     (env vars only, no cert access)
```

**Analysis:**
- Controller is trusted party (holds certs briefly during fetch)
- VM is ephemeral and isolated (destroyed after build)
- Host is semi-trusted (can start VM, cannot access internals)
- Network assumed secure (HTTPS, no cert pinning in v1)

**Gap:** If attacker controls host root, they could theoretically read VM memory via hypervisor. This is documented and accepted for prototype phase.

---

## Cross-Phase Critical Issues

### CRITICAL-X1: Contract Mismatch - Pending Build Access

**Location:**
- Controller: `/packages/controller/src/middleware/auth.ts:78-85`
- Bootstrap: `/vm-setup/free-agent-vm-bootstrap:129-173`

**Problem:** The `requireWorkerAccess` middleware allows ANY registered worker to access a **pending** build's certificates (where `worker_id` is null). The condition:

```typescript
if (build.worker_id && build.worker_id !== workerId) {
  return reply.status(403)...
}
```

This means `build.worker_id === null` passes validation.

**Sequence:**
1. Build submitted (status: pending, worker_id: null)
2. Worker A polls, gets assigned, VM boots
3. Before VM bootstrap completes, Worker B polls
4. Worker B requests `/certs-secure` with its own worker ID
5. Since `build.worker_id` is null, request succeeds
6. Worker B now has the certificates

**Impact:** Certificate theft by any registered worker during the assignment race window.

**Solution:**
```typescript
// In requireWorkerAccess when requireBuildIdHeader is true (secure endpoint)
if (requireBuildIdHeader) {
  // For secure endpoints, build MUST be assigned to requesting worker
  if (!build.worker_id || build.worker_id !== workerId) {
    return reply.status(403).send({
      error: 'Build not assigned to this worker',
    });
  }
}
```

---

### CRITICAL-X2: Bootstrap Can Run Before Assignment Complete

**Location:**
- Swift: `/free-agent/Sources/BuildVM/TartVMManager.swift:51-93`
- Controller: Build assignment logic

**Problem:** Swift worker clones VM and starts it with env vars BEFORE the build is marked as "assigned" in the database. The VM bootstrap starts immediately and may fetch certs during the assignment race window.

**Timeline:**
```
T0: Worker polls, receives build (build still "pending" in DB)
T1: Worker calls tart clone
T2: Worker calls tart run --env BUILD_ID=...
T3: VM boots, bootstrap fetches /certs-secure
T4: Worker reports "building" to controller
T5: Controller marks build as "assigned"
```

Between T3 and T5, the build may still be "pending" with null worker_id.

**Impact:** Combined with CRITICAL-X1, this is exploitable.

**Solution:** Change the Swift worker to mark build as assigned BEFORE starting VM:

```swift
// Before cloning VM
try await markBuildAssigned(buildId: buildId, workerId: workerId)

// Then clone and run
vmName = "fa-\(jobID)"
try await executeCommand(tartPath, ["clone", templateImage, vmName!])
```

Or ensure controller's `/poll` endpoint atomically assigns the build before returning it.

---

### HIGH-X1: Timeout Inconsistency

**Location:**
- Swift: `TartVMManager.swift:92` - bootstrap timeout: 180s
- Swift: `TartVMManager.swift:16-17` - IP timeout: 120s, SSH timeout: 180s
- Bootstrap: `free-agent-vm-bootstrap:37-38` - fetch retries: 5s + 15s + 45s = 65s max

**Problem:** Bootstrap has 65s max retry window, Swift waits 180s. If network is slow but recovers after 90s, bootstrap will have already failed while Swift is still waiting.

**Impact:** False negatives - builds fail that could have succeeded.

**Solution:** Align timeouts:
- Bootstrap max retry: 120s (5s + 15s + 45s + 55s = 120s with 4 retries)
- Or Swift bootstrap timeout: 90s (match bootstrap max + buffer)

---

### MEDIUM-X1: Error Indistinguishability

**Problem:** When build fails, the error chain collapses context:

1. Bootstrap fails with HTTP 403 -> writes to `/tmp/free-agent-bootstrap.log`
2. Swift gets `VMError.bootstrapTimeout` (not 403)
3. Worker reports "build failed" (not "cert fetch forbidden")
4. User sees generic "build failed" message

**Impact:** Debugging requires SSH into VM template (impossible in production) or log scraping.

**Solution:** Bootstrap should write structured error to a file readable by `tart exec`:

```bash
# On error
echo '{"phase":"cert_fetch","error":"HTTP 403","details":"Worker not authorized"}' > /tmp/free-agent-error.json
```

Swift checks this file on timeout:
```swift
if let errorJson = try? await tartExec("cat /tmp/free-agent-error.json") {
    // Parse and include in error message
}
```

---

## Phase-Specific Critical Issues

### Phase 1: VM Bootstrap

#### CRITICAL-1: chpasswd Not Available on macOS

**Location:** `/vm-setup/free-agent-vm-bootstrap:84`

```bash
if echo "admin:$NEW_PASSWORD" | sudo chpasswd 2>/dev/null; then
```

**Problem:** `chpasswd` is Linux. macOS requires `dscl` or `sysadminctl`. The `2>/dev/null` hides the failure completely.

**Impact:** Password NOT randomized. VM remains accessible with original password. Host can SSH in and extract certificates.

**THIS DEFEATS THE ENTIRE SECURITY MODEL.**

**Fix:**
```bash
if sudo dscl . -passwd /Users/admin "$NEW_PASSWORD" 2>/dev/null; then
    log "Admin password randomized via dscl"
elif sudo sysadminctl -resetPasswordFor admin -newPassword "$NEW_PASSWORD" 2>&1 | grep -q "Done"; then
    log "Admin password randomized via sysadminctl"
else
    error_exit "CRITICAL: Failed to randomize admin password - aborting for security" 1
fi
```

#### CRITICAL-2: Shell Injection via Environment Variables

**Location:** `/vm-setup/free-agent-vm-bootstrap:129,133,135-143`

```bash
FETCH_URL="${CONTROLLER_URL}/api/builds/${BUILD_ID}/certs-secure"
curl ... "$FETCH_URL" ...
```

**Problem:** If `BUILD_ID` contains `$(malicious_command)` or `;rm -rf /`, it executes.

**Impact:** RCE on VM during bootstrap.

**Fix:** Validate all env vars against strict patterns:
```bash
[[ "$BUILD_ID" =~ ^[a-zA-Z0-9_-]+$ ]] || error_exit "Invalid BUILD_ID format" 1
[[ "$WORKER_ID" =~ ^[a-zA-Z0-9_-]+$ ]] || error_exit "Invalid WORKER_ID format" 1
[[ "$CONTROLLER_URL" =~ ^https?://[a-zA-Z0-9._:/-]+$ ]] || error_exit "Invalid CONTROLLER_URL format" 1
```

#### CRITICAL-3: API Key Logged to Disk

**Location:** `/vm-setup/free-agent-vm-bootstrap:120`

```bash
log "API_KEY: ${API_KEY:0:8}..."
```

**Problem:** Even first 8 chars of API key persisted to `/tmp/free-agent-bootstrap.log`.

**Impact:** Credential leak if VM disk accessed.

**Fix:**
```bash
log "API_KEY: [REDACTED - present]"
```

---

### Phase 2: Controller

#### CRITICAL-4: Zip Bomb Attack Vector

**Location:** `/packages/controller/src/services/FileStorage.ts:192-214`

```typescript
export function unzipCerts(zipBuffer: Buffer): CertsBundle {
  const zip = new AdmZip(zipBuffer);
  const entries = zip.getEntries();
  // No size validation!
  for (const entry of entries) {
    p12 = entry.getData(); // Decompresses entire entry into memory
  }
}
```

**Problem:** No decompression size limit. A 10MB zip (within `maxCertsFileSize`) could decompress to gigabytes.

**Impact:** Server OOM crash (DoS).

**Fix:**
```typescript
const MAX_DECOMPRESSED_SIZE = 50 * 1024 * 1024; // 50MB
const MAX_FILES = 20;

let totalSize = 0;
for (const entry of entries) {
  totalSize += entry.header.size; // Check BEFORE decompressing
  if (totalSize > MAX_DECOMPRESSED_SIZE) {
    throw new Error('Cert bundle exceeds size limit');
  }
}
if (entries.length > MAX_FILES) {
  throw new Error('Too many files in cert bundle');
}
```

#### CRITICAL-5: Path Traversal in Zip Entry Names

**Location:** `/packages/controller/src/services/FileStorage.ts:200-207`

```typescript
if (entry.entryName.endsWith('.p12')) {
  p12 = entry.getData();
}
```

**Problem:** Entry names not sanitized. `../../../etc/passwd.p12` would match.

**Impact:** While `getData()` doesn't write to disk, this establishes a bad pattern. If entry names are ever logged or used in paths, it becomes exploitable.

**Fix:**
```typescript
const basename = entry.entryName.split('/').pop() || '';
if (entry.entryName.includes('..') || entry.entryName.startsWith('/')) {
  continue; // Skip suspicious entries
}
if (basename.endsWith('.p12')) {
  p12 = entry.getData();
}
```

---

### Phase 3: Swift Worker

#### CRITICAL-6: API Key Visible in Process List

**Location:** `/free-agent/Sources/BuildVM/TartVMManager.swift:133`

```swift
let monitorCommand = "/usr/local/bin/vm-monitor.sh '\(controllerURL)' '\(buildId)' '\(workerId)' '\(apiKey)' 30 > /dev/null 2>&1 & echo $!"
```

**Problem:** API key passed as command-line argument, visible to any process via `ps aux`.

**Impact:** Credential exposure to any process on VM.

**Fix:** Pass via stdin or environment:
```swift
let monitorCommand = "API_KEY='\(shellEscape(apiKey))' /usr/local/bin/vm-monitor.sh '\(shellEscape(controllerURL))' '\(shellEscape(buildId))' '\(shellEscape(workerId))' 30 > /dev/null 2>&1 & echo $!"
```

#### CRITICAL-7: Command Injection in SSH Commands

**Location:** `/free-agent/Sources/BuildVM/TartVMManager.swift:133`

```swift
let monitorCommand = "... '\(controllerURL)' '\(buildId)' '\(workerId)' '\(apiKey)' ..."
```

**Problem:** Single quotes not escaped. If `controllerURL = "http://x'; rm -rf /"`, the quote breaks out.

**Impact:** Full RCE on VM.

**Fix:**
```swift
private func shellEscape(_ value: String) -> String {
    return value.replacingOccurrences(of: "'", with: "'\\''")
}
```

#### CRITICAL-8: Shell Injection in Tart Env Vars

**Location:** `/free-agent/Sources/BuildVM/TartVMManager.swift:70-85`

```swift
runArgs.append("BUILD_ID=\(buildId)")
```

**Problem:** No validation or escaping of buildId, workerId, controllerURL, apiKey before interpolation.

**Impact:** Command injection if controller returns malicious build ID.

**Fix:** Validate format:
```swift
guard buildId.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else {
    throw VMError.invalidBuildId
}
```

---

### Phase 4: Build Script

#### CRITICAL-9: PIPESTATUS Not Checked

**Location:** `/vm-setup/free-agent-run-job:155-160`

```bash
xcodebuild archive ... | tee -a "$OUT_DIR/xcodebuild.log"

if [ $? -ne 0 ]; then  # Checks tee's exit code, NOT xcodebuild's!
    log_error "Archive failed"
```

**Problem:** With pipe to `tee`, `$?` reflects `tee`'s status, not `xcodebuild`'s.

**Impact:** Build could fail but report success.

**Fix:**
```bash
xcodebuild archive ... | tee -a "$OUT_DIR/xcodebuild.log"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log_error "Archive failed"
    exit 1
fi
```

#### HIGH-1: Missing set -o pipefail

**Location:** `/vm-setup/free-agent-run-job:12`

**Problem:** Script has `set -e` but no `set -o pipefail`.

**Fix:** Add after line 12:
```bash
set -e
set -o pipefail
```

---

## Prioritized Fix List

### Must Fix Before Production (Blocking)

| # | Issue | Effort | File |
|---|-------|--------|------|
| 1 | CRITICAL-1: chpasswd on macOS | 30m | free-agent-vm-bootstrap |
| 2 | CRITICAL-X1: Pending build access | 15m | auth.ts |
| 3 | CRITICAL-2: Shell injection (bootstrap) | 30m | free-agent-vm-bootstrap |
| 4 | CRITICAL-6: API key in process list | 15m | TartVMManager.swift |
| 5 | CRITICAL-7: Command injection (SSH) | 15m | TartVMManager.swift |
| 6 | CRITICAL-8: Shell injection (tart env) | 30m | TartVMManager.swift |
| 7 | CRITICAL-4: Zip bomb protection | 30m | FileStorage.ts |
| 8 | CRITICAL-9: PIPESTATUS check | 10m | free-agent-run-job |
| 9 | HIGH-1: pipefail | 5m | free-agent-run-job |
| 10 | CRITICAL-3: API key logged | 5m | free-agent-vm-bootstrap |
| 11 | CRITICAL-5: Zip entry validation | 15m | FileStorage.ts |

**Total effort: ~3.5 hours**

### Should Fix Before Beta

| # | Issue | Effort |
|---|-------|--------|
| 12 | CRITICAL-X2: Assignment before VM start | 1h |
| 13 | HIGH-X1: Timeout alignment | 30m |
| 14 | MEDIUM-X1: Structured error propagation | 2h |
| 15 | Phase 1: Predictable temp file paths | 30m |
| 16 | Phase 1: Temp file race condition | 30m |
| 17 | Phase 3: Error type information loss | 1h |
| 18 | Phase 4: Pre-flight keychain validation | 30m |

**Total effort: ~6 hours**

### Can Fix Post-MVP

| # | Issue |
|---|-------|
| 19 | DRY: shared secure_delete function |
| 20 | DRY: shared logging functions |
| 21 | Phase 2: Type safety for request.build |
| 22 | Phase 3: VM cleanup race condition |
| 23 | Phase 3: Task cancellation checks |
| 24 | Phase 4: Parameterize export method |

---

## Residual Risk Assessment

After all critical fixes applied:

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Hypervisor escape | Very Low | Critical | Accept - Apple/Tart security updates |
| Host root + memory read | Low | High | Document: workers must be trusted machines |
| Network MITM (no cert pinning) | Low | Medium | Planned for Phase 7: cert pinning |
| APFS copy-on-write (shred ineffective) | Low | Low | Accept - VM destroyed after build |
| Template compromise | Low | High | Planned: template checksums |
| Controller DB compromise | Low | Critical | Out of scope - standard infra security |

---

## Testing Strategy Recommendations (Phase 5)

### Unit Tests Required

1. **auth.ts: requireWorkerAccess**
   - Pending build + random worker = 403 (after fix)
   - Assigned build + correct worker = 200
   - Assigned build + wrong worker = 403

2. **FileStorage.ts: unzipCerts**
   - Valid bundle extracts correctly
   - Zip bomb (>50MB decompressed) throws
   - Path traversal entry skipped
   - Missing P12 throws

3. **TartVMManager: shellEscape**
   - Single quotes escaped
   - Empty string handled
   - Unicode handled

### Integration Tests Required

1. **Bootstrap Script**
   - Password actually changes (test with `ssh` after bootstrap)
   - Cert fetch with valid credentials succeeds
   - Cert fetch with wrong worker ID fails (403)
   - Cert fetch for pending build fails (403 after fix)

2. **End-to-End**
   - Submit build with valid cert bundle
   - Worker picks up, VM boots, certs installed
   - Build succeeds, IPA signed
   - Verify signature: `codesign -vv artifact.ipa`

3. **Security Validation**
   - After VM boot, host cannot SSH (password changed)
   - `/tmp/certs-secure.json` deleted (check via tart exec)
   - API key not in bootstrap log

### Chaos Tests Recommended

1. Kill controller mid-cert-fetch (bootstrap should retry)
2. Kill VM mid-build (cleanup should succeed)
3. Submit malicious build ID (should be rejected)

---

## Final Verdict

**APPROVE WITH REQUIRED FIXES**

The architecture is sound and achieves its security goal. The implementation has significant vulnerabilities that MUST be fixed before any production use, but all identified issues have straightforward solutions.

Critical path to production:
1. Fix CRITICAL-1 (chpasswd) - Without this, the entire security model is broken
2. Fix CRITICAL-X1 (pending build access) - Cert theft vector
3. Fix injection vulnerabilities (CRITICAL-2, 6, 7, 8) - RCE vectors
4. Fix zip bomb (CRITICAL-4) - DoS vector
5. Fix exit code handling (CRITICAL-9, HIGH-1) - Silent failures

After these fixes, the system is deployable for trusted prototype phase. Before community worker rollout, also implement:
- Structured error propagation
- TLS cert pinning
- Template integrity verification

---

## Appendix: Contract Verification

### ENV Vars: Swift -> VM Bootstrap

| Variable | Swift Source | Bootstrap Consumer | Match |
|----------|--------------|-------------------|-------|
| BUILD_ID | `TartVMManager.swift:71` | `free-agent-vm-bootstrap:109` | YES |
| WORKER_ID | `TartVMManager.swift:75` | `free-agent-vm-bootstrap:110` | YES |
| CONTROLLER_URL | `TartVMManager.swift:79` | `free-agent-vm-bootstrap:112` | YES |
| API_KEY | `TartVMManager.swift:83` | `free-agent-vm-bootstrap:111` | YES |

### HTTP: Bootstrap -> Controller

| Field | Bootstrap Sends | Controller Expects | Match |
|-------|-----------------|-------------------|-------|
| URL | `${CONTROLLER_URL}/api/builds/${BUILD_ID}/certs-secure` | Route: `/:id/certs-secure` | YES |
| X-API-Key | Line 136 | Global hook `requireApiKey` | YES |
| X-Worker-Id | Line 137 | `requireWorkerAccess` line 46 | YES |
| X-Build-Id | Line 138 | `requireWorkerAccess` line 47 | YES |

### File Signals: Bootstrap -> Swift

| Signal | Bootstrap Creates | Swift Polls | Match |
|--------|-------------------|-------------|-------|
| Ready file | `/tmp/free-agent-ready` (line 211) | `test -f /tmp/free-agent-ready` (line 260) | YES |

### Response: Controller -> Bootstrap

| Field | Controller Returns | Bootstrap Expects | Match |
|-------|-------------------|-------------------|-------|
| p12 | `p12: p12.toString('base64')` | `jq -r '.p12'` | YES |
| p12Password | `p12Password: password` | `jq -r '.p12Password'` | YES |
| keychainPassword | `keychainPassword: crypto.randomBytes(24)...` | `jq -r '.keychainPassword'` | YES |
| provisioningProfiles | `provisioningProfiles: profiles.map(...)` | `jq -r '.provisioningProfiles'` | YES |

All contracts align correctly. No integration mismatches detected.
