# Code Review: VM Bootstrap Infrastructure (Phase 1)

**Date:** 2026-01-26
**Reviewer:** Claude Opus 4.5
**Scope:** `vm-setup/free-agent-vm-bootstrap`, `vm-setup/install-signing-certs`, `vm-setup/com.expo.free-agent.bootstrap.plist`

---

## Executive Summary

Solid Phase 1 implementation with good security fundamentals: password randomization, SSH lockdown, retry logic, and secure file deletion. However, several critical security gaps and shell scripting vulnerabilities require attention before production deployment.

---

## Red Critical Issues

### 1. Shell Injection via Environment Variables

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-vm-bootstrap` lines 129, 133, 135-143

**Problem:** `BUILD_ID`, `WORKER_ID`, `API_KEY`, and `CONTROLLER_URL` are interpolated directly into strings and curl commands without sanitization. An attacker who controls these values can inject shell commands.

**Impact:** Remote code execution. If a malicious `BUILD_ID` contains `$(malicious_command)` or backticks, it executes.

**Code:**
```bash
# Line 129 - Direct interpolation
FETCH_URL="${CONTROLLER_URL}/api/builds/${BUILD_ID}/certs-secure"

# Line 133 - Logged without sanitization
log "Attempt $attempt/$MAX_RETRIES: Fetching from $FETCH_URL"
```

**Solution:** Validate all environment variables against strict patterns before use:

```bash
# After line 116, add validation
validate_env_var() {
    local name="$1" value="$2" pattern="$3"
    if [[ ! "$value" =~ ^${pattern}$ ]]; then
        error_exit "Invalid $name: contains disallowed characters" 1
    fi
}

validate_env_var "BUILD_ID" "$BUILD_ID" '[a-zA-Z0-9_-]+'
validate_env_var "WORKER_ID" "$WORKER_ID" '[a-zA-Z0-9_-]+'
validate_env_var "CONTROLLER_URL" "$CONTROLLER_URL" 'https?://[a-zA-Z0-9._:/-]+'
# API_KEY: alphanumeric plus common key chars
validate_env_var "API_KEY" "$API_KEY" '[a-zA-Z0-9_=-]+'
```

---

### 2. API Key Logged to Disk

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-vm-bootstrap` line 120

**Problem:** First 8 characters of API key logged to `/tmp/free-agent-bootstrap.log`. Log files persist and can be read by other processes.

**Impact:** Credential exposure. Even partial key disclosure aids brute-force attacks.

**Code:**
```bash
log "API_KEY: ${API_KEY:0:8}..." # Log only first 8 chars
```

**Solution:** Remove API key logging entirely:

```bash
log "API_KEY: [REDACTED]"
```

---

### 3. chpasswd Not Available on macOS

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-vm-bootstrap` line 84

**Problem:** `chpasswd` is a Linux utility. macOS uses `dscl` or `sysadminctl` for password changes. This will silently fail on macOS VMs (stderr redirected to /dev/null).

**Impact:** Password randomization fails completely - VM remains accessible with original password. The `2>/dev/null` hides the failure.

**Code:**
```bash
if echo "admin:$NEW_PASSWORD" | sudo chpasswd 2>/dev/null; then
```

**Solution:** Use macOS-compatible password change:

```bash
if sudo dscl . -passwd /Users/admin "$NEW_PASSWORD" 2>/dev/null; then
    log "Admin password randomized (32 bytes)"
    unset NEW_PASSWORD
elif sudo sysadminctl -resetPasswordFor admin -newPassword "$NEW_PASSWORD" 2>/dev/null; then
    log "Admin password randomized via sysadminctl"
    unset NEW_PASSWORD
else
    error_exit "Failed to randomize admin password" 1
fi
```

---

### 4. Race Condition: Cert File Written Before Validation

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-vm-bootstrap` lines 135-153

**Problem:** Curl writes response to `$CERTS_FILE` before HTTP status check. If curl gets a 200 but times out during write, or if response is partial, the file exists with incomplete/attacker-controlled content.

**Impact:** If another process reads `$CERTS_FILE` between write and validation, it may process attacker data.

**Code:**
```bash
HTTP_CODE=$(curl -w "%{http_code}" -o "$CERTS_FILE" \
    ...
    "$FETCH_URL" 2>&1 | tail -n 1 || echo "000")

if [[ "$HTTP_CODE" == "200" ]]; then
    # File already on disk at this point
    if jq empty "$CERTS_FILE" 2>/dev/null; then
```

**Solution:** Write to temp file first, validate, then atomically move:

```bash
CERTS_FILE_TMP="${CERTS_FILE}.tmp"

HTTP_CODE=$(curl -w "%{http_code}" -o "$CERTS_FILE_TMP" \
    ... \
    "$FETCH_URL" 2>&1 | tail -n 1 || echo "000")

if [[ "$HTTP_CODE" == "200" ]]; then
    if jq empty "$CERTS_FILE_TMP" 2>/dev/null; then
        mv "$CERTS_FILE_TMP" "$CERTS_FILE"
        # ...
    else
        secure_delete "$CERTS_FILE_TMP"
    fi
fi
```

---

### 5. P12 Password May Be Empty (Valid Attack Vector)

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/install-signing-certs` lines 166-169, 249-251

**Problem:** P12 password is not validated for presence. An attacker could provide empty `p12Password` to import unprotected certificates into keychain.

**Impact:** Lower security bar - certificates without password protection can be extracted more easily if keychain is compromised.

**Code:**
```bash
if [[ -z "$P12_B64" || "$P12_B64" == "null" ]]; then  # P12 checked
    error "Missing 'p12' field in cert bundle"
# But P12_PASSWORD not checked

# Later, conditionally adds -P flag
if [[ -n "$P12_PASSWORD" ]]; then
    IMPORT_ARGS+=(-P "$P12_PASSWORD")
fi
```

**Solution:** Require P12 password:

```bash
if [[ -z "$P12_PASSWORD" || "$P12_PASSWORD" == "null" ]]; then
    error "Missing 'p12Password' field in cert bundle - passwordless P12 not allowed"
    exit 2
fi
```

---

### 6. Insecure Temp File Path with PID

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/install-signing-certs` lines 46-47

**Problem:** Using `$$` (PID) for temp file names is predictable. Attacker can pre-create symlink at `/tmp/cert-<predicted_pid>.p12` pointing to sensitive file before script runs.

**Impact:** Symlink attack - attacker overwrites arbitrary file with P12 content.

**Code:**
```bash
TMP_P12="/tmp/cert-$$.p12"
TMP_PROFILE_PREFIX="/tmp/profile-$$"
```

**Solution:** Use `mktemp` for unpredictable paths with secure permissions:

```bash
TMP_P12=$(mktemp /tmp/cert-XXXXXXXXXX.p12) || exit 1
chmod 600 "$TMP_P12"
TMP_PROFILE_DIR=$(mktemp -d /tmp/profile-XXXXXXXXXX) || exit 1
chmod 700 "$TMP_PROFILE_DIR"
TMP_PROFILE_PREFIX="${TMP_PROFILE_DIR}/profile"
```

---

## Yellow Architecture Concerns

### 1. LaunchDaemon Runs as admin, Not root

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/com.expo.free-agent.bootstrap.plist` lines 52-55

**Problem:** LaunchDaemon specifies `UserName: admin` but bootstrap script uses `sudo` for privileged operations. This requires admin to have passwordless sudo, which is a security risk.

**Impact:** Configuration assumes passwordless sudo. If sudo requires password, bootstrap fails silently or hangs.

**Code:**
```xml
<key>UserName</key>
<string>admin</string>
```

**Recommendation:** Either:
- Run as root (remove UserName/GroupName) and drop privileges where needed
- Document passwordless sudo requirement in README
- Add sudo check at script start

---

### 2. DRY Violation: secure_delete Duplicated

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-vm-bootstrap` lines 52-65, `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/install-signing-certs` lines 73-84

**Problem:** Identical `secure_delete` function copied between scripts.

**Impact:** Maintenance burden - bug fixes must be applied twice.

**Code (both files):**
```bash
secure_delete() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        return 0
    fi
    if command -v shred &> /dev/null; then
        shred -u -n 3 "$file" 2>/dev/null || rm -f "$file"
    else
        rm -f "$file"
    fi
}
```

**Recommendation:** Extract to shared library `/usr/local/lib/free-agent-common.sh` and source it:

```bash
# In both scripts
source /usr/local/lib/free-agent-common.sh
```

---

### 3. No TLS Certificate Verification Flag

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-vm-bootstrap` lines 135-143

**Problem:** Curl does not explicitly enable certificate verification. While curl verifies by default, an attacker could set `CURL_CA_BUNDLE` environment variable to bypass verification.

**Impact:** MITM attack could intercept certificate fetch and inject malicious certs.

**Recommendation:** Explicitly verify TLS and pin CA if possible:

```bash
--cacert /etc/ssl/certs/ca-certificates.crt \
--ssl-reqd \
```

Or for production, consider certificate pinning.

---

### 4. Shred Ineffective on SSDs/APFS

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-vm-bootstrap` line 60, `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/install-signing-certs` line 80

**Problem:** `shred` overwrites file in place, but macOS APFS uses copy-on-write. Original data remains on disk. VMs typically use APFS.

**Impact:** Certificates may be recoverable from disk after "secure deletion."

**Recommendation:** Document limitation. For true security:
1. Use encrypted volume for `/tmp`
2. Or use memory-backed tmpfs
3. Or accept limitation (VM is destroyed after use anyway)

---

## Green DRY Opportunities

### 1. Logging Functions Duplicated

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-vm-bootstrap` lines 41-49, `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/install-signing-certs` lines 56-70

**Problem:** Both scripts define similar logging functions with slight variations (one uses colors, one doesn't).

**Recommendation:** Standardize logging in shared library with optional color support.

---

### 2. JSON Field Extraction Pattern

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/install-signing-certs` lines 160-163, 310

**Problem:** Repeated pattern of `jq -r '.field' "$CERTS_FILE" || echo ""` and null checks.

**Code:**
```bash
P12_B64=$(jq -r '.p12' "$CERTS_FILE" 2>/dev/null || echo "")
P12_PASSWORD=$(jq -r '.p12Password' "$CERTS_FILE" 2>/dev/null || echo "")
KEYCHAIN_PASSWORD=$(jq -r '.keychainPassword' "$CERTS_FILE" 2>/dev/null || echo "")
```

**Recommendation:** Helper function:

```bash
json_field() {
    local field="$1" file="$2"
    jq -r ".$field // empty" "$file" 2>/dev/null
}
```

---

## Blue Maintenance Improvements

### 1. Exit Code Not Captured Correctly

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-vm-bootstrap` lines 195-200

**Problem:** Exit code captured after error_exit call, which never returns. Also, with `set -e` active, the else branch may not execute as expected.

**Code:**
```bash
if /usr/local/bin/install-signing-certs --certs "$CERTS_FILE" >> "$LOG_FILE" 2>&1; then
    log "Certificates installed successfully"
else
    EXIT_CODE=$?  # This line may not execute with set -e
    error_exit "Certificate installation failed (exit code: $EXIT_CODE)" 3
fi
```

**Solution:** Capture in subshell or disable errexit temporarily:

```bash
set +e
/usr/local/bin/install-signing-certs --certs "$CERTS_FILE" >> "$LOG_FILE" 2>&1
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -ne 0 ]]; then
    error_exit "Certificate installation failed (exit code: $EXIT_CODE)" 3
fi
log "Certificates installed successfully"
```

---

### 2. Retry Delay Array Index May Go Out of Bounds

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-vm-bootstrap` line 165

**Problem:** If MAX_RETRIES is increased beyond array size, `${RETRY_DELAYS[$((attempt - 1))]}` returns empty string.

**Code:**
```bash
MAX_RETRIES=3
RETRY_DELAYS=(5 15 45)  # Array has 3 elements
# If MAX_RETRIES changed to 5, attempts 4 and 5 have no delay
DELAY=${RETRY_DELAYS[$((attempt - 1))]}
```

**Solution:** Use last delay for any overflow:

```bash
DELAY_INDEX=$((attempt - 1))
if [[ $DELAY_INDEX -ge ${#RETRY_DELAYS[@]} ]]; then
    DELAY_INDEX=$((${#RETRY_DELAYS[@]} - 1))
fi
DELAY=${RETRY_DELAYS[$DELAY_INDEX]}
```

---

### 3. Curl Error Output Lost

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/free-agent-vm-bootstrap` lines 135-143

**Problem:** `2>&1 | tail -n 1` loses curl error messages. Only HTTP code captured.

**Impact:** Debugging network failures is difficult - no error details logged.

**Code:**
```bash
HTTP_CODE=$(curl -w "%{http_code}" -o "$CERTS_FILE" \
    ...
    "$FETCH_URL" 2>&1 | tail -n 1 || echo "000")
```

**Solution:** Capture stderr separately:

```bash
CURL_STDERR=$(mktemp)
HTTP_CODE=$(curl -w "%{http_code}" -o "$CERTS_FILE" \
    ... \
    "$FETCH_URL" 2>"$CURL_STDERR") || HTTP_CODE="000"

if [[ "$HTTP_CODE" != "200" ]]; then
    log "Curl error: $(cat "$CURL_STDERR")"
fi
rm -f "$CURL_STDERR"
```

---

### 4. Keychain Search List Manipulation Fragile

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/install-signing-certs` line 227

**Problem:** Parsing `security list-keychains` output with `sed 's/"//g'` is brittle. Paths with special characters will break.

**Code:**
```bash
security list-keychains -d user -s "$KEYCHAIN_NAME" $(security list-keychains -d user | sed 's/"//g') 2>/dev/null
```

**Solution:** Use proper array handling:

```bash
# Get current keychains as array
mapfile -t CURRENT_KEYCHAINS < <(security list-keychains -d user | tr -d '"')
security list-keychains -d user -s "$KEYCHAIN_NAME" "${CURRENT_KEYCHAINS[@]}" 2>/dev/null
```

---

### 5. No Timeout on Keychain Operations

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/vm-setup/install-signing-certs` lines 213-293

**Problem:** Keychain operations can hang indefinitely if macOS prompts for GUI authentication.

**Impact:** Bootstrap hangs forever in headless VM.

**Recommendation:** Add timeout wrapper:

```bash
timeout 30 security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME" 2>/dev/null
```

---

## White Nitpicks

### 1. Inconsistent Error Exit Codes

**Observation:** `free-agent-vm-bootstrap` uses 1-3, `install-signing-certs` uses 1-6. Document exit code strategy.

### 2. Hardcoded Paths

**Observation:** `/usr/local/bin/install-signing-certs` hardcoded. Consider making configurable or using `$0` directory.

### 3. Missing set -u

**Observation:** Scripts use `set -e` and `set -o pipefail` but not `set -u` for undefined variable errors.

**Recommendation:** Add `set -u` after fixing all `${VAR:-}` patterns.

### 4. Log File Not Rotated

**Observation:** `/tmp/free-agent-bootstrap.log` grows unbounded across VM reboots (if VM is reused).

**Recommendation:** Clear or rotate at script start.

---

## Check Strengths

1. **Exponential backoff** - Well-implemented retry logic with increasing delays
2. **JSON validation** - Validates response is valid JSON before processing
3. **Cert bundle structure validation** - Checks for required keys before installation
4. **Cleanup trap** - Properly registered EXIT trap for secure deletion
5. **One-shot LaunchDaemon** - KeepAlive: false prevents restart loops
6. **Comprehensive exit codes** - Distinct codes for different failure modes
7. **Verification phase** - Confirms installation success before signaling ready
8. **SSH lockdown** - Proactive removal of authorized_keys
9. **Good documentation** - BOOTSTRAP-README.md is thorough with test instructions

---

## Unresolved Questions

1. macOS version tested? `dscl` vs `sysadminctl` behavior varies
2. VM reused across builds or destroyed? (affects shred limitation severity)
3. Is passwordless sudo configured in base image?
4. Controller TLS cert - self-signed or CA-issued? (affects pinning strategy)
5. What happens if bootstrap fails partway - VM left in inconsistent state?

---

## Priority Fixes (in order)

| Priority | Issue | Location |
|----------|-------|----------|
| CRITICAL | Fix chpasswd - use macOS-compatible password change | free-agent-vm-bootstrap:84 |
| CRITICAL | Add input validation for all environment variables | free-agent-vm-bootstrap:109-116 |
| CRITICAL | Remove API key from logs | free-agent-vm-bootstrap:120 |
| HIGH | Use mktemp instead of predictable PID-based paths | install-signing-certs:46-47 |
| HIGH | Fix temp file race condition with atomic move | free-agent-vm-bootstrap:135-153 |
| MEDIUM | Require P12 password (disallow empty) | install-signing-certs:166-169 |
| MEDIUM | Fix exit code capture pattern | free-agent-vm-bootstrap:195-200 |
| MEDIUM | Extract shared functions to common library | both scripts |
