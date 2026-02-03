#!/bin/bash
#
# Setup Local Test Image for E2E Testing
#
# Creates/updates a local VM image with the latest bootstrap scripts
# for testing without pushing to registry.
#
# Usage: ./setup-local-test-image.sh [base-image]
#   base-image: Optional base to clone from (default: ghcr.io/sethwebster/expo-free-agent-base:latest)
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
LOCAL_IMAGE_NAME="expo-free-agent-base-local"
BASE_IMAGE="${1:-ghcr.io/sethwebster/expo-free-agent-base:latest}"

log_info "=== Setup Local Test Image ==="
log_info "Local Image: $LOCAL_IMAGE_NAME"
log_info "Base Image: $BASE_IMAGE"
echo ""

# Step 1: Check if Tart is installed
log_step "Checking prerequisites..."
if ! command -v /opt/homebrew/bin/tart &> /dev/null; then
    log_error "Tart not found"
    log_error "Install: brew install cirruslabs/cli/tart"
    exit 1
fi
log_info "✓ Tart installed"

# Step 2: Check if local image already exists
if /opt/homebrew/bin/tart list | awk '{print $2}' | grep -q "^${LOCAL_IMAGE_NAME}\$"; then
    log_step "Local image exists, updating..."

    # Delete existing local image
    /opt/homebrew/bin/tart delete "$LOCAL_IMAGE_NAME"
    log_info "✓ Deleted existing local image"
else
    log_step "Creating new local image..."
fi

# Step 3: Check if base image is available locally
if ! /opt/homebrew/bin/tart list | grep -q "$BASE_IMAGE"; then
    log_step "Base image not found locally, pulling..."
    /opt/homebrew/bin/tart pull "$BASE_IMAGE" || {
        log_error "Failed to pull base image: $BASE_IMAGE"
        exit 1
    }
    log_info "✓ Base image pulled"
fi

# Step 4: Clone base image to local test image
log_step "Cloning base image to local test image..."
/opt/homebrew/bin/tart clone "$BASE_IMAGE" "$LOCAL_IMAGE_NAME"
log_info "✓ VM cloned"

# Step 5: Install latest scripts
log_step "Installing latest bootstrap scripts..."
"$SCRIPT_DIR/install-to-vm-template.sh" "$LOCAL_IMAGE_NAME" || {
    log_error "Script installation failed"
    log_warn "Cleaning up..."
    /opt/homebrew/bin/tart delete "$LOCAL_IMAGE_NAME" || true
    exit 1
}
log_info "✓ Scripts installed"

# Success!
echo ""
log_info "=== Local Test Image Ready ==="
log_info "Image Name: $LOCAL_IMAGE_NAME"
echo ""
log_info "Installed scripts from:"
log_info "  • free-agent-stub.sh"
log_info "  • install-signing-certs"
log_info "  • free-agent-run-job"
log_info "  • vm-monitor.sh"
log_info "  • LaunchDaemons"
echo ""
log_info "To test with this image:"
echo "  ./test-e2e-vm.sh"
echo ""
log_info "To update scripts and re-test:"
echo "  1. Make changes to vm-setup/*.sh files"
echo "  2. Run: ./vm-setup/setup-local-test-image.sh"
echo "  3. Run: ./test-e2e-vm.sh"
echo ""
