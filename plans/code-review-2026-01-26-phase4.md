# Code Review: Phase 4 - Build Script Code Signing Enablement

**Date:** 2026-01-26
**Reviewer:** Code Review Bot
**Scope:** `vm-setup/free-agent-run-job` lines 148-189 (xcodebuild archive + ExportOptions.plist)

---

## Summary

Phase 4 enables code signing in the VM build script by:
1. Removing `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, `CODE_SIGN_IDENTITY=""` from xcodebuild archive
2. Adding `-allowProvisioningUpdates` flag
3. Changing ExportOptions.plist: `method` from `development` to `ad-hoc`, `signingStyle` from `manual` to `automatic`

---

## Critical Issues

### 1. Missing CODE_SIGN_IDENTITY creates ambiguity

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-run-job:148-155`

**Problem:** With automatic signing and no explicit `CODE_SIGN_IDENTITY`, xcodebuild will auto-select from available identities. If `build.keychain-db` contains multiple certificates (e.g., development AND distribution), xcodebuild may pick wrong one.

**Impact:** Build failure OR incorrect signing (dev cert for ad-hoc distribution = unusable IPA)

**Current code:**
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

**Solution:** Either:
A. Trust automatic selection (acceptable if `install-signing-certs` only ever imports ONE identity per build)
B. Query installed identity and set explicitly:
```bash
# Get first signing identity from build keychain
IDENTITY=$(security find-identity -v -p codesigning build.keychain-db 2>/dev/null \
    | grep -m1 "^[[:space:]]*1)" \
    | sed 's/.*"\(.*\)"/\1/')

xcodebuild archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination generic/platform=iOS \
    -allowProvisioningUpdates \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    | tee -a "$OUT_DIR/xcodebuild.log"
```

**Verdict:** LOW-MEDIUM RISK. The `install-signing-certs` script imports a single P12, so only one identity should exist. However, explicit selection is more robust. **Recommend adding explicit identity query** as defensive measure.

---

### 2. `-allowProvisioningUpdates` requires Xcode authentication

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-run-job:154`

**Problem:** `-allowProvisioningUpdates` allows Xcode to automatically download/create provisioning profiles from Apple Developer Portal. This requires:
1. Apple Developer account signed into Xcode
2. Session not expired
3. Network access to Apple servers

In ephemeral VM without pre-authenticated Xcode, this flag may cause:
- Hang waiting for Apple ID prompt
- Silent failure to update profiles
- Error: "No profiles for 'com.example.app' were found"

**Impact:** Build failure on first use OR intermittent failures when session expires.

**Current code:**
```bash
xcodebuild archive \
    ...
    -allowProvisioningUpdates \
    ...
```

**Solution:** Two options:

A. **Remove flag if profiles pre-installed** (recommended for hermetic builds):
```bash
xcodebuild archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination generic/platform=iOS \
    | tee -a "$OUT_DIR/xcodebuild.log"
```
Requires: User uploads matching provisioning profile in cert bundle.

B. **Keep flag but ensure Xcode authenticated in template:**
- Sign into Xcode with Apple ID during template baking
- Document: Template expires when Apple session expires (~90 days)
- Add: `-allowProvisioningDeviceRegistration` if devices need auto-registration

**Verdict:** MEDIUM RISK. The flag is correct for automatic signing workflow, BUT requires either:
1. Pre-authenticated Xcode in template (maintenance burden, session expiry)
2. User-provided profiles MUST match app bundle ID (profiles installed by `install-signing-certs`)

**Recommendation:** Document that user MUST include matching `.mobileprovision` in cert bundle. `-allowProvisioningUpdates` then works with locally-installed profiles without Apple authentication. If profile missing, build fails fast with clear error.

---

### 3. `ad-hoc` method requires Distribution certificate

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-run-job:174`

**Problem:** Export method `ad-hoc` requires an Apple Distribution certificate, not a Development certificate. Users who upload iOS Development certificates will get cryptic export errors.

**Impact:** User confusion, failed exports with misleading error messages.

**Current code:**
```xml
<key>method</key>
<string>ad-hoc</string>
```

**Solution:** Either:
A. Document: "Ad-hoc distribution requires Apple Distribution certificate (not Development)"
B. Make method configurable via input parameter
C. Auto-detect cert type and adjust method:
```bash
# Detect if distribution cert
CERT_NAME=$(security find-identity -v -p codesigning build.keychain-db | head -1 | grep -o '"[^"]*"' | tr -d '"')
if [[ "$CERT_NAME" == *"Distribution"* ]]; then
    METHOD="ad-hoc"  # or app-store
else
    METHOD="development"
fi
```

**Verdict:** LOW RISK if documented. Users who want ad-hoc distribution already know they need Distribution certs. **Recommend documenting requirement** in TART-SETUP.md and CLI help.

---

## Architecture Concerns

### 4. No validation that signing prerequisites exist

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-run-job:131-162`

**Problem:** The script proceeds to xcodebuild without validating:
1. Keychain `build.keychain-db` exists
2. Signing identity installed
3. Provisioning profiles installed

If bootstrap failed silently, build will fail deep in xcodebuild with confusing errors.

**Impact:** Poor debuggability when bootstrap fails.

**Solution:** Add pre-flight check before xcodebuild:
```bash
# Step 5: Build with xcodebuild
log_info "Building with xcodebuild..."

# Pre-flight: Verify signing setup
if ! security list-keychains -d user | grep -q "build.keychain-db"; then
    log_error "build.keychain-db not found - bootstrap may have failed"
    log_error "Check /tmp/free-agent-bootstrap.log for details"
    exit 1
fi

IDENTITY_COUNT=$(security find-identity -v -p codesigning build.keychain-db 2>/dev/null | grep -c "^[[:space:]]*[0-9])" || echo "0")
if [ "$IDENTITY_COUNT" -eq 0 ]; then
    log_error "No signing identities found in build.keychain-db"
    log_error "Verify certificate installation succeeded"
    exit 1
fi
log_info "Found $IDENTITY_COUNT signing identity(ies)"
```

---

### 5. ExportOptions.plist hardcoded for single use case

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-run-job:168-183`

**Problem:** Hardcoded `ad-hoc` method doesn't support:
- `app-store` - App Store submission
- `enterprise` - In-house distribution
- `development` - Development builds with device-specific profiles

**Impact:** Limited to ad-hoc only; users wanting other distribution methods cannot use system.

**Current code:**
```bash
cat > "$WORK_DIR/ExportOptions.plist" <<EOF
...
    <key>method</key>
    <string>ad-hoc</string>
...
EOF
```

**Solution:** Accept method as input parameter:
```bash
# In argument parsing
EXPORT_METHOD="${EXPORT_METHOD:-ad-hoc}"  # Default to ad-hoc

# In ExportOptions generation
cat > "$WORK_DIR/ExportOptions.plist" <<EOF
...
    <key>method</key>
    <string>$EXPORT_METHOD</string>
...
EOF
```

**Verdict:** ACCEPTABLE for MVP. Single-purpose ad-hoc is fine. **Document as known limitation**, add TODO for Phase 7.

---

## DRY Opportunities

### 6. Duplicate log redirection pattern

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-run-job:155,189`

**Problem:** Both xcodebuild commands pipe to `tee -a "$OUT_DIR/xcodebuild.log"`:
```bash
xcodebuild archive ... | tee -a "$OUT_DIR/xcodebuild.log"
xcodebuild -exportArchive ... | tee -a "$OUT_DIR/xcodebuild.log"
```

This duplicates the log path and appends (`-a`) unnecessarily since line 86 already redirects all output:
```bash
exec > >(tee "$OUT_DIR/xcodebuild.log") 2>&1
```

**Impact:** Log file written twice (once via exec redirect, once via explicit tee), potential file contention.

**Solution:** Remove redundant `| tee -a` since exec already captures:
```bash
xcodebuild archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination generic/platform=iOS \
    -allowProvisioningUpdates

# exec redirect already captures this output
```

---

## Maintenance Improvements

### 7. Exit code check after pipe may miss xcodebuild failure

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-run-job:157-160,191-194`

**Problem:** With `set -e` and a pipe to `tee`, the exit code checked is from `tee`, not `xcodebuild`:
```bash
xcodebuild archive ... | tee -a "$OUT_DIR/xcodebuild.log"

if [ $? -ne 0 ]; then  # This checks tee's exit code, not xcodebuild's
    log_error "Archive failed"
    exit 1
fi
```

**Impact:** Silent failure if xcodebuild fails but tee succeeds. Build appears successful when it failed.

**Solution:** Use PIPESTATUS or remove pipe (since exec redirect handles logging):
```bash
# Option A: Use PIPESTATUS
xcodebuild archive ... | tee -a "$OUT_DIR/xcodebuild.log"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log_error "Archive failed"
    exit 1
fi

# Option B: Remove pipe, let exec handle logging
xcodebuild archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination generic/platform=iOS \
    -allowProvisioningUpdates || {
    log_error "Archive failed"
    exit 1
}
```

---

### 8. Missing error context in build.json on failure

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-run-job:211-218`

**Problem:** `build.json` only created on success. On failure, no structured metadata about what failed.

**Impact:** Harder to programmatically parse failures; host must grep log file.

**Solution:** Create build.json on both success and failure:
```bash
# After archive/export, before copying artifact
create_build_metadata() {
    local success="$1"
    local error_msg="${2:-}"

    cat > "$OUT_DIR/build.json" <<EOF
{
    "success": $success,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "scheme": "$SCHEME",
    "artifact": "${success:+artifact.ipa}",
    "error": "$error_msg"
}
EOF
}

# On archive failure:
log_error "Archive failed"
create_build_metadata false "xcodebuild archive failed"
exit 1

# On success:
create_build_metadata true
```

---

## Nitpicks

### 9. `compileBitcode: false` appropriate but undocumented

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-run-job:175-176`

**Problem:** Bitcode compilation disabled but no comment explaining why.

**Recommendation:** Add comment:
```xml
<!-- Bitcode deprecated in Xcode 14+, disable for smaller IPAs -->
<key>compileBitcode</key>
<false/>
```

### 10. Missing `set -o pipefail`

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-run-job:12`

**Problem:** `set -e` present but `set -o pipefail` missing. Pipeline failures may not trigger exit.

**Solution:**
```bash
set -e
set -o pipefail
```

---

## Strengths

1. **Clean separation**: Build script focused solely on build, bootstrap handles certs
2. **Hermetic design**: Each VM gets fresh clone, no state leakage
3. **Automatic signing style correct**: For ephemeral VMs with user-provided certs, automatic is right choice
4. **Log capture**: exec redirect ensures logs captured even on early failures
5. **ExportOptions minimal**: Only necessary keys, no bloat

---

## Action Items by Priority

### Must Fix (Before Production)

| Item | Location | Issue | Fix |
|------|----------|-------|-----|
| 7 | Line 157, 191 | PIPESTATUS not checked | Use PIPESTATUS[0] or remove pipe |
| 10 | Line 12 | Missing pipefail | Add `set -o pipefail` |

### Should Fix (Before Beta)

| Item | Location | Issue | Fix |
|------|----------|-------|-----|
| 4 | Before line 131 | No pre-flight validation | Add keychain/identity checks |
| 6 | Line 155, 189 | Redundant tee pipes | Remove, exec handles logging |
| 2 | Line 154 | -allowProvisioningUpdates ambiguity | Document profile requirement |

### Consider (Post-MVP)

| Item | Location | Issue | Fix |
|------|----------|-------|-----|
| 1 | Line 148 | Implicit identity selection | Query and set explicitly |
| 3 | Line 174 | ad-hoc requires distribution cert | Document requirement |
| 5 | Line 168-183 | Hardcoded export method | Parameterize method |
| 8 | Line 211-218 | No failure metadata | Create build.json on failure too |

---

## Security Assessment

### Keychain Access from xcodebuild

**Analysis:** xcodebuild accesses `build.keychain-db` which was:
1. Created with random password by `install-signing-certs`
2. Added to keychain search list
3. Partition list configured with `apple-tool:,apple:`

**Risk:** LOW. Partition list allows only Apple tools (codesign, xcodebuild), not arbitrary processes.

### -allowProvisioningUpdates Security

**Analysis:** This flag could:
1. Download profiles from Apple (requires authenticated Xcode)
2. Modify locally-installed profiles (no)
3. Leak credentials (no - uses Xcode's own session management)

**Risk:** LOW. Even if Xcode authenticated, profiles downloaded are scoped to that Apple ID's team.

### Certificate Trust Chain

**Analysis:** Imported P12 must have valid certificate chain. If:
1. P12 contains expired cert: Build fails at signing (good)
2. P12 contains revoked cert: Build succeeds but IPA rejected at install (acceptable)
3. P12 malformed: Import fails in bootstrap (good)

**Risk:** LOW. macOS keychain validates cert integrity at import time.

### Log Exposure

**Analysis:** `xcodebuild.log` may contain:
1. Bundle identifiers (low sensitivity)
2. Team IDs (low sensitivity)
3. Signing identity names (low sensitivity)
4. File paths (low sensitivity)
5. Entitlements (low-medium sensitivity)

**Risk:** LOW. No secrets exposed. Entitlements visible but not actionable without certs.

---

## Conclusion

Phase 4 implementation is **fundamentally sound** for the secure signing workflow. The changes correctly transition from unsigned builds to automatic signing with user-provided credentials.

**Blocking issues:** #7 (PIPESTATUS) must be fixed - current code may silently succeed on xcodebuild failure.

**Important gaps:** Pre-flight validation (#4) and profile requirement documentation (#2) should be addressed before beta.

**Overall verdict:** Approve with required fixes. The design is correct; implementation needs minor hardening.
