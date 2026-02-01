#!/bin/bash
#
# free-agent-stub.sh
#
# Minimal VM stub (baked into image)
# Performs security lockdown then execs versioned bootstrap from mount
#
# Responsibilities:
#   1. Randomize admin password (prevents host SSH access)
#   2. Remove SSH authorized_keys
#   3. Wait for bootstrap mount
#   4. Exec versioned bootstrap script
#
# This stub is minimal and rarely changes. All build logic is in the
# versioned bootstrap provided by the worker.
#

set -euo pipefail

# Configuration
LOG_FILE="/var/log/free-agent-stub.log"
MOUNT_POINT="/Volumes/My Shared Files/build-config"
BOOTSTRAP_SCRIPT="${MOUNT_POINT}/bootstrap.sh"
MOUNT_TIMEOUT=60

# Logging helper
log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" | tee -a "$LOG_FILE"
}

# Error handler
fail() {
    log "ERROR: $*"
    exit 1
}

log "=========================================="
log "Expo Free Agent - VM Stub"
log "=========================================="

# ========================================
# Phase 1: Security Lockdown
# ========================================

log "Phase 1: Security lockdown..."

# 1.1. Randomize admin password
log "Randomizing admin password..."
NEW_PASSWORD=$(openssl rand -base64 32)
if echo "admin:${NEW_PASSWORD}" | sudo chpasswd 2>/dev/null; then
    log "✓ Admin password randomized (32 bytes)"
    # Clear password from memory
    unset NEW_PASSWORD
else
    fail "Failed to randomize admin password"
fi

# 1.2. Delete SSH authorized_keys
log "Removing SSH authorized keys..."
if [[ -f /Users/admin/.ssh/authorized_keys ]]; then
    rm -f /Users/admin/.ssh/authorized_keys || true
    log "✓ SSH authorized_keys removed"
else
    log "✓ No authorized_keys found (already clean)"
fi

log "✓ Security lockdown complete"

# ========================================
# Phase 2: Wait for Bootstrap Mount
# ========================================

log "Phase 2: Waiting for bootstrap mount..."
log "Mount point: ${MOUNT_POINT}"
log "Bootstrap script: ${BOOTSTRAP_SCRIPT}"
log "Timeout: ${MOUNT_TIMEOUT}s"

for i in $(seq 1 $MOUNT_TIMEOUT); do
    if [[ -d "$MOUNT_POINT" ]]; then
        log "✓ Mount point available (waited ${i}s)"
        break
    fi

    if [[ $i -eq $MOUNT_TIMEOUT ]]; then
        fail "Mount point not available after ${MOUNT_TIMEOUT}s"
    fi

    sleep 1
done

# ========================================
# Phase 3: Verify Bootstrap Script
# ========================================

log "Phase 3: Verifying bootstrap script..."

if [[ ! -f "$BOOTSTRAP_SCRIPT" ]]; then
    fail "Bootstrap script not found at ${BOOTSTRAP_SCRIPT}"
fi

# Make executable (in case mount doesn't preserve permissions)
chmod +x "$BOOTSTRAP_SCRIPT" || fail "Failed to make bootstrap executable"

log "✓ Bootstrap script verified"

# ========================================
# Phase 4: Exec Versioned Bootstrap
# ========================================

log "Phase 4: Executing versioned bootstrap..."
log "Replacing this process with: ${BOOTSTRAP_SCRIPT}"
log "=========================================="

# Exec bootstrap (replaces current process)
# LaunchDaemon will monitor the bootstrap process
exec "$BOOTSTRAP_SCRIPT"
