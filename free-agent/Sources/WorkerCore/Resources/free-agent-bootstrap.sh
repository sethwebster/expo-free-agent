#!/bin/bash
#
# free-agent-bootstrap.sh
#
# Versioned bootstrap script (bundled with worker)
# Reads build-config.json, fetches certs, signals ready
#
# This script is extensible and versioned with the worker.
# Updates don't require VM image rebuild.
#
# Responsibilities:
#   1. Load build configuration from mount
#   2. Authenticate with controller (OTP → VM token)
#   3. Fetch signing certificates (iOS only)
#   4. Install certificates
#   5. Signal ready to host
#

set -euo pipefail

# Configuration
MOUNT_POINT="/Volumes/My Shared Files/build-config"
CONFIG_FILE="${MOUNT_POINT}/build-config.json"
READY_FILE="${MOUNT_POINT}/vm-ready"
LOG_FILE="/var/log/free-agent-bootstrap.log"

# Logging helper
log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" | tee -a "$LOG_FILE"
}

# Error handler - writes failure to vm-ready
fail() {
    local error_msg="$1"
    log "ERROR: ${error_msg}"

    # Write failure status to vm-ready
    cat > "$READY_FILE" <<EOF
{
  "status": "failed",
  "error": "${error_msg}"
}
EOF

    exit 1
}

# Secure file deletion
secure_delete() {
    local file="$1"
    if [[ -f "$file" ]]; then
        if command -v shred &> /dev/null; then
            shred -u -n 3 "$file" 2>/dev/null || rm -f "$file"
        else
            rm -f "$file"
        fi
    fi
}

log "=========================================="
log "Expo Free Agent - Bootstrap"
log "=========================================="

# ========================================
# Phase 1: Load Configuration
# ========================================

log "Phase 1: Loading build configuration..."

if [[ ! -f "$CONFIG_FILE" ]]; then
    fail "Build config not found at ${CONFIG_FILE}"
fi

# Validate JSON
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    fail "Invalid JSON in configuration file"
fi

# Extract required fields
BUILD_ID=$(jq -r '.build_id' "$CONFIG_FILE")
BUILD_TOKEN=$(jq -r '.build_token' "$CONFIG_FILE")
CONTROLLER_URL=$(jq -r '.controller_url' "$CONFIG_FILE")
PLATFORM=$(jq -r '.platform' "$CONFIG_FILE")

# Validate extracted values
if [[ -z "$BUILD_ID" || "$BUILD_ID" == "null" ]]; then
    fail "Missing build_id in configuration"
fi
if [[ -z "$BUILD_TOKEN" || "$BUILD_TOKEN" == "null" ]]; then
    fail "Missing build_token in configuration"
fi
if [[ -z "$CONTROLLER_URL" || "$CONTROLLER_URL" == "null" ]]; then
    fail "Missing controller_url in configuration"
fi
if [[ -z "$PLATFORM" || "$PLATFORM" == "null" ]]; then
    fail "Missing platform in configuration"
fi

# Validate format (prevent injection)
if ! [[ "$BUILD_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    fail "Invalid BUILD_ID format"
fi
if ! [[ "$CONTROLLER_URL" =~ ^https?://[a-zA-Z0-9._:-]+(/[a-zA-Z0-9._/-]*)?$ ]]; then
    fail "Invalid CONTROLLER_URL format"
fi

log "✓ Build ID: ${BUILD_ID}"
log "✓ Platform: ${PLATFORM}"
log "✓ Controller: ${CONTROLLER_URL}"

# ========================================
# Phase 2: Authenticate with Controller
# ========================================

log "Phase 2: Authenticating with controller..."

AUTH_URL="${CONTROLLER_URL}/api/builds/${BUILD_ID}/authenticate"
AUTH_RESPONSE=$(mktemp)

log "Calling ${AUTH_URL}"
HTTP_CODE=$(curl -w "%{http_code}" -o "$AUTH_RESPONSE" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{\"otp\":\"$BUILD_TOKEN\"}" \
    --silent \
    --show-error \
    --max-time 30 \
    "$AUTH_URL" 2>&1 | tail -n 1 || echo "000")

if [[ "$HTTP_CODE" != "200" ]]; then
    ERROR_MSG=$(cat "$AUTH_RESPONSE" 2>/dev/null || echo "No response")
    secure_delete "$AUTH_RESPONSE"
    fail "Authentication failed (HTTP ${HTTP_CODE}): ${ERROR_MSG}"
fi

# Extract VM token
VM_TOKEN=$(jq -r '.vm_token // empty' "$AUTH_RESPONSE")
secure_delete "$AUTH_RESPONSE"

if [[ -z "$VM_TOKEN" ]]; then
    fail "No VM token in authentication response"
fi

log "✓ Authenticated successfully (VM token received)"

# ========================================
# Phase 3: Fetch Certificates (iOS only)
# ========================================

if [[ "$PLATFORM" == "ios" ]]; then
    log "Phase 3: Fetching iOS signing certificates..."

    CERT_URL="${CONTROLLER_URL}/api/builds/${BUILD_ID}/certs-secure"
    CERT_RESPONSE=$(mktemp)

    log "Calling ${CERT_URL}"
    HTTP_CODE=$(curl -w "%{http_code}" -o "$CERT_RESPONSE" \
        -H "X-VM-Token: ${VM_TOKEN}" \
        -H "Accept: application/json" \
        --silent \
        --show-error \
        --max-time 30 \
        "$CERT_URL" 2>&1 | tail -n 1 || echo "000")

    if [[ "$HTTP_CODE" != "200" ]]; then
        ERROR_MSG=$(cat "$CERT_RESPONSE" 2>/dev/null || echo "No response")
        secure_delete "$CERT_RESPONSE"
        fail "Certificate fetch failed (HTTP ${HTTP_CODE}): ${ERROR_MSG}"
    fi

    # Validate JSON response
    if ! jq empty "$CERT_RESPONSE" 2>/dev/null; then
        secure_delete "$CERT_RESPONSE"
        fail "Invalid JSON in certificate response"
    fi

    log "✓ Certificates fetched successfully"

    # ========================================
    # Phase 4: Install Certificates
    # ========================================

    log "Phase 4: Installing certificates..."

    # Create temp directory for cert files
    TEMP_DIR=$(mktemp -d)

    # Extract and decode certificate data
    jq -r '.p12' "$CERT_RESPONSE" | base64 -d > "${TEMP_DIR}/cert.p12"
    P12_PASSWORD=$(jq -r '.p12Password' "$CERT_RESPONSE")
    KEYCHAIN_PASSWORD=$(jq -r '.keychainPassword' "$CERT_RESPONSE" | base64 -d)

    # Extract provisioning profiles
    PROFILE_COUNT=$(jq -r '.provisioningProfiles | length' "$CERT_RESPONSE")
    log "Extracting ${PROFILE_COUNT} provisioning profiles..."

    for i in $(seq 0 $((PROFILE_COUNT - 1))); do
        jq -r ".provisioningProfiles[$i]" "$CERT_RESPONSE" | base64 -d > "${TEMP_DIR}/profile${i}.mobileprovision"
    done

    # Clear cert response from disk
    secure_delete "$CERT_RESPONSE"

    # Call install-signing-certs helper
    if [[ ! -x /usr/local/bin/install-signing-certs ]]; then
        rm -rf "$TEMP_DIR"
        fail "Certificate installer not found: /usr/local/bin/install-signing-certs"
    fi

    # Install certificates
    if /usr/local/bin/install-signing-certs \
        --p12 "${TEMP_DIR}/cert.p12" \
        --p12-password "$P12_PASSWORD" \
        --keychain-password "$KEYCHAIN_PASSWORD" \
        --profiles "${TEMP_DIR}"/*.mobileprovision \
        >> "$LOG_FILE" 2>&1; then
        log "✓ Certificates installed successfully"
    else
        EXIT_CODE=$?
        rm -rf "$TEMP_DIR"
        fail "Certificate installation failed (exit code: ${EXIT_CODE})"
    fi

    # Securely delete temp files
    secure_delete "${TEMP_DIR}/cert.p12"
    rm -rf "$TEMP_DIR"
    log "✓ Temporary certificate files deleted"

else
    log "Phase 3-4: Skipping certificate installation (platform: ${PLATFORM})"
fi

# ========================================
# Phase 5: Generate Verification Token
# ========================================

log "Phase 5: Generating verification token..."

# Generate random token for host verification
VERIFICATION_TOKEN=$(openssl rand -base64 32)

log "✓ Verification token generated"

# ========================================
# Phase 6: Signal Ready
# ========================================

log "Phase 6: Signaling ready to host..."

# Write ready status with verification token
cat > "$READY_FILE" <<EOF
{
  "status": "ready",
  "vm_token": "${VERIFICATION_TOKEN}"
}
EOF

log "✓ Ready signal written to ${READY_FILE}"

# Write completion marker for verification
cat > "${MOUNT_POINT}/bootstrap-complete" <<EOF
Bootstrap completed successfully at $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Build ID: ${BUILD_ID}
Platform: ${PLATFORM}
EOF

log "✓ Bootstrap completion marker written"

log "=========================================="
log "Bootstrap complete! VM ready for builds."
log "=========================================="

exit 0
