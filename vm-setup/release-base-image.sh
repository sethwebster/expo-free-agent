#!/bin/bash
#
# Expo Free Agent - Base VM Image Release Script
#
# This script automates the release of a new base VM image:
# 1. Updates VERSION file
# 2. Pulls current base image
# 3. Clones for update
# 4. Installs updated bootstrap scripts
# 5. Pushes to GitHub Container Registry
# 6. Updates code references
#
# Usage: ./release-base-image.sh <new-version>
#   new-version: Semantic version (e.g., 0.1.24)
#
# Prerequisites:
# - Tart installed (/opt/homebrew/bin/tart)
# - GitHub CLI authenticated (gh auth login)
# - write:packages permission on ghcr.io
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

# Check arguments
if [ $# -ne 1 ]; then
    log_error "Usage: $0 <new-version>"
    echo ""
    echo "Example:"
    echo "  $0 0.1.24"
    echo ""
    echo "This will release a new base VM image with updated bootstrap scripts."
    exit 1
fi

NEW_VERSION="$1"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Validate version format
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_error "Invalid version format: $NEW_VERSION"
    log_error "Must be semantic version (e.g., 0.1.24)"
    exit 1
fi

log_info "=== Expo Free Agent Base Image Release ==="
log_info "New Version: $NEW_VERSION"
log_info "Script Dir: $SCRIPT_DIR"
log_info "Repo Root: $REPO_ROOT"
echo ""

# Step 1: Verify prerequisites
log_step "Verifying prerequisites..."

if ! command -v tart &> /dev/null; then
    log_error "Tart not found at /opt/homebrew/bin/tart"
    log_error "Install: brew install cirruslabs/cli/tart"
    exit 1
fi
log_info "✓ Tart found: $(which tart)"

if ! command -v gh &> /dev/null; then
    log_error "GitHub CLI not found"
    log_error "Install: brew install gh"
    exit 1
fi
log_info "✓ GitHub CLI found: $(which gh)"

if ! gh auth status &> /dev/null; then
    log_error "GitHub CLI not authenticated"
    log_error "Run: gh auth login"
    exit 1
fi
log_info "✓ GitHub CLI authenticated"

# Step 2: Read current version
log_step "Reading current version..."
CURRENT_VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "unknown")
log_info "Current version: $CURRENT_VERSION"

if [ "$CURRENT_VERSION" = "$NEW_VERSION" ]; then
    log_warn "Version unchanged ($NEW_VERSION)"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted by user"
        exit 0
    fi
fi

# Step 3: Update VERSION file
log_step "Updating VERSION file..."
echo "$NEW_VERSION" > "$SCRIPT_DIR/VERSION"
log_info "✓ VERSION updated to $NEW_VERSION"

# Step 4: Set up registry authentication
log_step "Setting up GitHub Container Registry authentication..."
export TART_REGISTRY_USERNAME=sethwebster
export TART_REGISTRY_PASSWORD="$(gh auth token)"
log_info "✓ Registry credentials configured"

# Step 5: Pull current base image
CURRENT_IMAGE="ghcr.io/sethwebster/expo-free-agent-base:$CURRENT_VERSION"
log_step "Pulling current base image: $CURRENT_IMAGE..."

if tart list | grep -q "^ghcr.io/sethwebster/expo-free-agent-base@$CURRENT_VERSION"; then
    log_info "✓ Current image already pulled"
else
    log_info "Pulling from registry..."
    /opt/homebrew/bin/tart pull "$CURRENT_IMAGE" || {
        log_error "Failed to pull current image"
        log_error "Ensure image exists: $CURRENT_IMAGE"
        exit 1
    }
    log_info "✓ Current image pulled"
fi

# Step 6: Clone for update
TEMP_VM_NAME="expo-agent-base-update-$NEW_VERSION"
log_step "Cloning to temporary VM: $TEMP_VM_NAME..."

# Delete if exists
if /opt/homebrew/bin/tart list | awk '{print $2}' | grep -q "^$TEMP_VM_NAME\$"; then
    log_warn "Temporary VM already exists, deleting..."
    /opt/homebrew/bin/tart delete "$TEMP_VM_NAME" || true
fi

/opt/homebrew/bin/tart clone "$CURRENT_IMAGE" "$TEMP_VM_NAME"
log_info "✓ VM cloned"

# Step 7: Install updated scripts
log_step "Installing updated bootstrap scripts..."
"$SCRIPT_DIR/install-to-vm-template.sh" "$TEMP_VM_NAME" || {
    log_error "Script installation failed"
    log_warn "Cleaning up temporary VM..."
    /opt/homebrew/bin/tart delete "$TEMP_VM_NAME" || true
    exit 1
}
log_info "✓ Scripts installed"

# Step 8: Push to registry with version tag and :latest
NEW_IMAGE="ghcr.io/sethwebster/expo-free-agent-base:$NEW_VERSION"
LATEST_IMAGE="ghcr.io/sethwebster/expo-free-agent-base:latest"

log_step "Pushing to GitHub Container Registry..."
log_info "Pushing as: $NEW_IMAGE"
log_info "Pushing as: $LATEST_IMAGE"

/opt/homebrew/bin/tart push "$TEMP_VM_NAME" "$NEW_IMAGE" "$LATEST_IMAGE" || {
    log_error "Failed to push to registry"
    log_warn "Cleaning up temporary VM..."
    /opt/homebrew/bin/tart delete "$TEMP_VM_NAME" || true
    exit 1
}
log_info "✓ Images pushed to registry"

# Step 9: Clean up temporary VM
log_step "Cleaning up temporary VM..."
/opt/homebrew/bin/tart delete "$TEMP_VM_NAME"
log_info "✓ Temporary VM deleted"

# Step 10: Update code references
log_step "Updating code references..."

FILES_TO_UPDATE=(
    "$REPO_ROOT/free-agent/Sources/BuildVM/TartVMManager.swift"
    "$REPO_ROOT/free-agent/Sources/WorkerCore/WorkerService.swift"
    "$REPO_ROOT/free-agent/Sources/FreeAgent/SettingsView.swift"
    "$REPO_ROOT/free-agent/Sources/FreeAgent/VMSyncService.swift"
    "$REPO_ROOT/free-agent/Sources/FreeAgent/main.swift"
)

OLD_IMAGE_REF="ghcr.io/sethwebster/expo-free-agent-base:$CURRENT_VERSION"
NEW_IMAGE_REF="ghcr.io/sethwebster/expo-free-agent-base:$NEW_VERSION"

for file in "${FILES_TO_UPDATE[@]}"; do
    if [ -f "$file" ]; then
        if grep -q "$OLD_IMAGE_REF" "$file"; then
            sed -i '' "s|$OLD_IMAGE_REF|$NEW_IMAGE_REF|g" "$file"
            log_info "✓ Updated: $(basename "$file")"
        else
            log_warn "No reference found in: $(basename "$file")"
        fi
    else
        log_warn "File not found: $file"
    fi
done

log_info "✓ Code references updated"

# Success!
echo ""
log_info "=== Release Complete ==="
echo ""
log_info "Base VM Image: $NEW_IMAGE_REF"
log_info "Also tagged:   $LATEST_IMAGE"
echo ""
log_info "Next steps:"
echo "  1. Review changes:"
echo "     git diff"
echo ""
echo "  2. Test the new image:"
echo "     ./vm-setup/test-vm-bootstrap.sh ghcr.io/sethwebster/expo-free-agent-base:$NEW_VERSION"
echo ""
echo "  3. Commit changes:"
echo "     git add vm-setup/VERSION free-agent/Sources"
echo "     git commit -m \"Release base VM image v$NEW_VERSION\""
echo ""
echo "  4. Push to repository:"
echo "     git push origin main"
echo ""
log_info "Workers will automatically pull new image on next build"
