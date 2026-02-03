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

# Update progress for worker monitoring (generic, no sensitive data)
update_progress() {
    local phase="$1"
    local percent="$2"
    local message="$3"

    cat > "${MOUNT_POINT}/progress.json" <<EOF
{
  "status": "running",
  "phase": "${phase}",
  "progress_percent": ${percent},
  "message": "${message}",
  "updated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
}

# Upload build log to controller (batched to avoid overwhelming controller)
upload_build_log() {
    if [[ -f "$BUILD_LOG" ]]; then
        log "Uploading build log..."

        local line_count=0
        local batch=""

        while IFS= read -r line; do
            # Escape for JSON
            escaped_line=$(echo "$line" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g')
            batch="${batch}{\"level\":\"info\",\"message\":\"${escaped_line}\"},"
            ((line_count++))

            # Upload in batches of 50 lines
            if ((line_count >= 50)); then
                batch="[${batch%,}]"
                curl -X POST \
                    -H "Content-Type: application/json" \
                    -H "X-VM-Token: ${VM_TOKEN}" \
                    -d "{\"logs\":${batch}}" \
                    --silent --max-time 10 \
                    "${CONTROLLER_URL}/api/builds/${BUILD_ID}/logs" || true

                batch=""
                line_count=0
            fi
        done < "$BUILD_LOG"

        # Upload remaining lines
        if [[ -n "$batch" ]]; then
            batch="[${batch%,}]"
            curl -X POST \
                -H "Content-Type: application/json" \
                -H "X-VM-Token: ${VM_TOKEN}" \
                -d "{\"logs\":${batch}}" \
                --silent --max-time 10 \
                "${CONTROLLER_URL}/api/builds/${BUILD_ID}/logs" || true
        fi
    fi
}

# Signal build completion
signal_build_complete() {
    update_progress "completed" 100 "Build completed successfully"

    cat > "${MOUNT_POINT}/build-complete" <<EOF
{
  "status": "success",
  "completed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "artifact_uploaded": true
}
EOF
}

# Signal build error
signal_build_error() {
    local error_msg="$1"
    log "ERROR: ${error_msg}"

    update_progress "failed" 0 "Build failed: ${error_msg}"

    cat > "${MOUNT_POINT}/build-error" <<EOF
{
  "status": "failed",
  "completed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "error": "${error_msg}",
  "artifact_uploaded": false
}
EOF

    # Upload logs before exiting
    upload_build_log
    exit 1
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

    if [[ "$HTTP_CODE" == "404" ]]; then
        log "⚠ No certificates provided - build will not be signed"
        secure_delete "$CERT_RESPONSE"

        # Skip to Phase 5 - continue without certificates
        # This is OK for testing or builds that don't require signing
    elif [[ "$HTTP_CODE" != "200" ]]; then
        ERROR_MSG=$(cat "$CERT_RESPONSE" 2>/dev/null || echo "No response")
        secure_delete "$CERT_RESPONSE"
        fail "Certificate fetch failed (HTTP ${HTTP_CODE}): ${ERROR_MSG}"
    else
        # HTTP 200 - certificates available, proceed with installation

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
            log "⚠️  Certificate installation failed (exit code: ${EXIT_CODE})"
            log "⚠️  Continuing anyway for testing purposes..."
        fi

        # Securely delete temp files
        secure_delete "${TEMP_DIR}/cert.p12"
        rm -rf "$TEMP_DIR"
        log "✓ Temporary certificate files deleted"
    fi

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

# ========================================
# Phase 7: Build Execution
# ========================================

log "Phase 7: Build execution starting..."
BUILD_LOG="/var/log/build.log"

# 7.1. Download source
log "Step 7.1: Downloading source..."
update_progress "downloading_source" 10 "Downloading source code..."

SOURCE_URL="${CONTROLLER_URL}/api/builds/${BUILD_ID}/source"
SOURCE_ZIP="/tmp/source.zip"
WORKSPACE_DIR="/tmp/workspace"

HTTP_CODE=$(curl -w "%{http_code}" -o "$SOURCE_ZIP" \
    -H "X-VM-Token: ${VM_TOKEN}" \
    --silent --max-time 300 \
    "$SOURCE_URL" 2>&1 | tail -n 1 || echo "000")

[[ "$HTTP_CODE" == "200" ]] || signal_build_error "Source download failed (HTTP ${HTTP_CODE})"

# 7.2. Extract source
log "Step 7.2: Extracting source..."
mkdir -p "$WORKSPACE_DIR"
unzip -q "$SOURCE_ZIP" -d "$WORKSPACE_DIR" || signal_build_error "Extraction failed"
secure_delete "$SOURCE_ZIP"

cd "$WORKSPACE_DIR" || signal_build_error "Cannot cd to workspace"
update_progress "building" 20 "Source extracted, starting build..."

# 7.3. Detect project type and prepare build
log "Step 7.3: Preparing build environment..."

# Check if this is an Expo project
IS_EXPO=false
if [[ -f "app.json" ]] && jq -e '.expo' app.json > /dev/null 2>&1; then
    IS_EXPO=true
    log "Detected Expo project"
fi

# Install dependencies
if [[ -f "package.json" ]]; then
    log "Installing dependencies..."
    update_progress "building" 22 "Installing npm dependencies..."

    npm ci >> "$BUILD_LOG" 2>&1 || {
        log "npm ci failed, trying npm install..."
        npm install >> "$BUILD_LOG" 2>&1 || {
            upload_build_log
            signal_build_error "npm install failed"
        }
    }

    log "✓ Dependencies installed"
fi

# Run Expo prebuild if needed
if [[ "$IS_EXPO" == "true" ]]; then
    log "Running Expo prebuild for $PLATFORM..."
    update_progress "building" 25 "Running Expo prebuild..."

    npx expo prebuild --platform "$PLATFORM" --no-install >> "$BUILD_LOG" 2>&1 || {
        upload_build_log
        signal_build_error "Expo prebuild failed"
    }

    log "✓ Expo prebuild completed"
fi

# 7.4. Run build
log "Step 7.4: Running build..."

ARTIFACT_PATH=""
if [[ "$PLATFORM" == "ios" ]]; then
    # iOS build
    update_progress "building" 30 "Running xcodebuild..."

    # Find workspace or project file
    WORKSPACE=$(find . -maxdepth 2 -name "*.xcworkspace" | head -1)
    if [[ -z "$WORKSPACE" ]]; then
        # Try xcodeproj if no workspace
        WORKSPACE=$(find . -maxdepth 2 -name "*.xcodeproj" | head -1)
        if [[ -z "$WORKSPACE" ]]; then
            upload_build_log
            signal_build_error "No Xcode workspace or project found"
        fi
    fi

    log "Using workspace/project: $WORKSPACE"

    # Determine scheme (usually project name)
    if [[ "$WORKSPACE" == *.xcworkspace ]]; then
        SCHEME=$(basename "$WORKSPACE" .xcworkspace)
        BUILD_FLAG="-workspace"
    else
        SCHEME=$(basename "$WORKSPACE" .xcodeproj)
        BUILD_FLAG="-project"
    fi

    log "Using scheme: $SCHEME"

    xcodebuild $BUILD_FLAG "$WORKSPACE" -scheme "$SCHEME" \
        -configuration Release -archivePath /tmp/app.xcarchive \
        archive >> "$BUILD_LOG" 2>&1 || {
        upload_build_log
        signal_build_error "xcodebuild archive failed"
    }

    update_progress "building" 70 "Exporting IPA..."
    xcodebuild -exportArchive -archivePath /tmp/app.xcarchive \
        -exportPath /tmp -exportOptionsPlist exportOptions.plist \
        >> "$BUILD_LOG" 2>&1 || {
        upload_build_log
        signal_build_error "IPA export failed"
    }

    ARTIFACT_PATH="/tmp/App.ipa"

elif [[ "$PLATFORM" == "android" ]]; then
    update_progress "building" 30 "Running Gradle..."

    # Ensure gradlew is executable
    [[ -f "./gradlew" ]] || signal_build_error "gradlew not found"
    chmod +x ./gradlew

    ./gradlew assembleRelease >> "$BUILD_LOG" 2>&1 || {
        upload_build_log
        signal_build_error "Gradle build failed"
    }

    ARTIFACT_PATH="app/build/outputs/apk/release/app-release.apk"
fi

# 7.5. Upload logs
log "Step 7.5: Uploading build logs..."
upload_build_log

# 7.6. Upload artifact
log "Step 7.6: Uploading artifact..."
update_progress "uploading_artifacts" 80 "Uploading artifact..."

[[ -f "$ARTIFACT_PATH" ]] || signal_build_error "Artifact not found: ${ARTIFACT_PATH}"

HTTP_CODE=$(curl -w "%{http_code}" -o /dev/null \
    -X POST -H "X-VM-Token: ${VM_TOKEN}" \
    -F "artifact=@${ARTIFACT_PATH}" \
    --silent --max-time 600 \
    "${CONTROLLER_URL}/api/builds/${BUILD_ID}/artifact" \
    2>&1 | tail -n 1 || echo "000")

[[ "$HTTP_CODE" == "200" ]] || signal_build_error "Artifact upload failed (HTTP ${HTTP_CODE})"

# 7.7. Signal completion
log "Step 7.7: Signaling completion..."
signal_build_complete

log "=========================================="
log "Build execution complete!"
log "=========================================="
exit 0
