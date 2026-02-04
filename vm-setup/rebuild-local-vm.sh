#!/bin/bash
#
# Rebuild the local VM template with updated scripts
# This clones from expo-free-agent-base-save-never-overwrite and creates expo-free-agent-base-local
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SOURCE_VM="expo-free-agent-base-save-never-overwrite"
TARGET_VM="expo-free-agent-base-local"

log_info "=== Rebuilding Local VM Template ==="
echo ""

# Step 1: Check source VM exists
log_step "Checking source VM..."
if ! /opt/homebrew/bin/tart list | grep -q "$SOURCE_VM"; then
    log_error "Source VM '$SOURCE_VM' not found!"
    exit 1
fi
log_info "✓ Source VM found"

# Step 2: Delete existing target if it exists
if /opt/homebrew/bin/tart list | grep -q "$TARGET_VM"; then
    log_warn "Target VM '$TARGET_VM' exists, deleting..."
    /opt/homebrew/bin/tart delete "$TARGET_VM" || true
fi

# Step 3: Clone from source
log_step "Cloning VM..."
/opt/homebrew/bin/tart clone "$SOURCE_VM" "$TARGET_VM"
log_info "✓ VM cloned as $TARGET_VM"

# Step 4: Install updated scripts
log_step "Installing updated scripts to VM..."
cd "$SCRIPT_DIR"
./install-to-vm-template.sh "$TARGET_VM"

log_info ""
log_info "=== VM Template Rebuild Complete ==="
log_info "VM Name: $TARGET_VM"
log_info ""
log_info "The stub script now supports the 'no-password-reset' flag:"
log_info "  - Create a file named 'no-password-reset' in the mount directory"
log_info "  - The VM will skip password randomization for debugging"
log_info ""
log_info "Test with:"
log_info "  ./test-vm-debug.sh"
log_info ""