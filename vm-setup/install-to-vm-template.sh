#!/bin/bash
#
# Expo Free Agent - VM Template Installation Script
#
# This script installs the secure bootstrap infrastructure into a Tart VM template.
# Run this ONCE per template to enable secure certificate handling.
#
# Usage: ./install-to-vm-template.sh <vm-name>
#   vm-name: Name of the Tart VM to install into (e.g., expo-agent-base)
#
# Requirements:
# - Tart installed and in PATH
# - VM must be stopped (not running)
# - VM must have brew installed
# - Scripts must exist in vm-setup/ directory
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
    log_error "Usage: $0 <vm-name>"
    echo ""
    echo "Example:"
    echo "  $0 expo-agent-base"
    echo ""
    echo "This will install bootstrap scripts into the VM template."
    exit 1
fi

VM_NAME="$1"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

log_info "=== Expo Free Agent VM Template Installer ==="
log_info "VM: $VM_NAME"
log_info "Scripts: $SCRIPT_DIR"
echo ""

# Step 1: Verify Tart installed
log_step "Verifying Tart installation..."
if ! command -v tart &> /dev/null; then
    log_error "Tart not found in PATH"
    log_error "Install: brew install cirruslabs/cli/tart"
    exit 1
fi
log_info "✓ Tart found: $(which tart)"

# Step 2: Verify VM exists and is stopped
log_step "Checking VM status..."
if ! tart list | awk '{print $2}' | grep -q "^$VM_NAME\$"; then
    log_error "VM '$VM_NAME' not found"
    log_error "Available VMs:"
    tart list
    exit 1
fi

if tart list | awk -v vm="$VM_NAME" '$2 == vm {print $NF}' | grep -q "running"; then
    log_error "VM '$VM_NAME' is running - please stop it first:"
    log_error "  tart stop $VM_NAME"
    exit 1
fi
log_info "✓ VM found and stopped"

# Step 3: Verify required scripts exist
log_step "Verifying script files..."
REQUIRED_FILES=(
    "free-agent-stub.sh"
    "free-agent-auto-update"
    "install-signing-certs"
    "vm-monitor.sh"
    "com.expo.free-agent.bootstrap.plist"
    "VERSION"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$SCRIPT_DIR/$file" ]; then
        log_error "Missing required file: $file"
        exit 1
    fi
done
log_info "✓ All required files found"

# Step 4: Start VM temporarily for installation
log_step "Starting VM for installation..."
tart run "$VM_NAME" &
VM_PID=$!
sleep 10  # Give VM time to boot
log_info "✓ VM started (PID: $VM_PID)"

# Wait for IP
log_step "Waiting for VM IP..."
MAX_WAIT=60
WAITED=0
VM_IP=""
while [ $WAITED -lt $MAX_WAIT ]; do
    VM_IP=$(tart ip "$VM_NAME" 2>/dev/null || echo "")
    if [ -n "$VM_IP" ]; then
        break
    fi
    sleep 2
    WAITED=$((WAITED + 2))
done

if [ -z "$VM_IP" ]; then
    log_error "Could not get VM IP after ${MAX_WAIT}s"
    tart stop "$VM_NAME"
    exit 1
fi
log_info "✓ VM IP: $VM_IP"

# Step 5: Install dependencies
log_step "Installing dependencies (jq)..."
tart exec "$VM_NAME" bash -c "brew list jq &>/dev/null || brew install jq" || {
    log_warn "Failed to install jq - you may need to install manually"
}
log_info "✓ Dependencies installed"

# Step 6: Copy scripts to VM via base64 encoding
log_step "Copying scripts to VM..."

# Helper function to copy file via base64
copy_file_to_vm() {
    local src_file="$1"
    local dst_path="$2"
    local permissions="$3"

    # Encode file content as base64 and decode in VM
    local encoded=$(base64 < "$src_file")
    tart exec "$VM_NAME" bash -c "echo '$encoded' | base64 --decode > '$dst_path'"
    if [ -n "$permissions" ]; then
        tart exec "$VM_NAME" sudo chmod "$permissions" "$dst_path"
    fi
}

# Stub script (minimal security, then execs worker-provided bootstrap)
copy_file_to_vm "$SCRIPT_DIR/free-agent-stub.sh" "/tmp/free-agent-stub.sh" "0755"
tart exec "$VM_NAME" sudo mv /tmp/free-agent-stub.sh /usr/local/bin/
log_info "✓ Installed free-agent-stub.sh"

# Auto-update launcher (checks for mounted bootstrap or downloads from GitHub)
copy_file_to_vm "$SCRIPT_DIR/free-agent-auto-update" "/tmp/free-agent-auto-update" "0755"
tart exec "$VM_NAME" sudo mv /tmp/free-agent-auto-update /usr/local/bin/
log_info "✓ Installed free-agent-auto-update"

# Cert installer
copy_file_to_vm "$SCRIPT_DIR/install-signing-certs" "/tmp/install-signing-certs" "0755"
tart exec "$VM_NAME" sudo mv /tmp/install-signing-certs /usr/local/bin/
log_info "✓ Installed install-signing-certs"

# Build runner
copy_file_to_vm "$SCRIPT_DIR/free-agent-run-job" "/tmp/free-agent-run-job" "0755"
tart exec "$VM_NAME" sudo mv /tmp/free-agent-run-job /usr/local/bin/
log_info "✓ Installed free-agent-run-job"

# VM monitor
copy_file_to_vm "$SCRIPT_DIR/vm-monitor.sh" "/tmp/vm-monitor.sh" "0755"
tart exec "$VM_NAME" sudo mv /tmp/vm-monitor.sh /usr/local/bin/
log_info "✓ Installed vm-monitor.sh"

# Version file
tart exec "$VM_NAME" sudo mkdir -p /usr/local/etc
copy_file_to_vm "$SCRIPT_DIR/VERSION" "/tmp/free-agent-version" "0644"
tart exec "$VM_NAME" sudo mv /tmp/free-agent-version /usr/local/etc/free-agent-version
log_info "✓ Installed VERSION file"

# Step 7: Install LaunchDaemons
log_step "Installing LaunchDaemons..."

# Bootstrap daemon
copy_file_to_vm "$SCRIPT_DIR/com.expo.free-agent.bootstrap.plist" "/tmp/com.expo.free-agent.bootstrap.plist" "0644"
tart exec "$VM_NAME" sudo mv /tmp/com.expo.free-agent.bootstrap.plist /Library/LaunchDaemons/
tart exec "$VM_NAME" sudo chown root:wheel /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist

# Virtiofs auto-mount daemon
copy_file_to_vm "$SCRIPT_DIR/com.expo.virtiofs-automount.plist" "/tmp/com.expo.virtiofs-automount.plist" "0644"
tart exec "$VM_NAME" sudo mv /tmp/com.expo.virtiofs-automount.plist /Library/LaunchDaemons/
tart exec "$VM_NAME" sudo chown root:wheel /Library/LaunchDaemons/com.expo.virtiofs-automount.plist

log_info "✓ LaunchDaemons installed"

# Step 8: Load LaunchDaemons
log_step "Loading LaunchDaemons..."

# Load virtiofs automount first (bootstrap depends on it)
tart exec "$VM_NAME" sudo launchctl load /Library/LaunchDaemons/com.expo.virtiofs-automount.plist || {
    log_warn "Virtiofs automount LaunchDaemon load failed - will auto-load on next boot"
}

# Load bootstrap daemon
tart exec "$VM_NAME" sudo launchctl load /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist || {
    log_warn "Bootstrap LaunchDaemon load failed - may already be loaded or will auto-load on next boot"
}

log_info "✓ LaunchDaemons configured"

# Step 9: Verify installation
log_step "Verifying installation..."
VERIFICATION_FAILED=false

# Check scripts exist with correct permissions
for script in free-agent-stub.sh install-signing-certs free-agent-run-job vm-monitor.sh; do
    if ! tart exec "$VM_NAME" test -x "/usr/local/bin/$script"; then
        log_error "Script not executable: $script"
        VERIFICATION_FAILED=true
    fi
done

# Check version file
if ! tart exec "$VM_NAME" test -f /usr/local/etc/free-agent-version; then
    log_error "Version file not found"
    VERIFICATION_FAILED=true
fi

# Check LaunchDaemons
if ! tart exec "$VM_NAME" test -f /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist; then
    log_error "Bootstrap LaunchDaemon plist not found"
    VERIFICATION_FAILED=true
fi

if ! tart exec "$VM_NAME" test -f /Library/LaunchDaemons/com.expo.virtiofs-automount.plist; then
    log_error "Virtiofs automount LaunchDaemon plist not found"
    VERIFICATION_FAILED=true
fi

if [ "$VERIFICATION_FAILED" = true ]; then
    log_error "Verification failed - see errors above"
    tart stop "$VM_NAME"
    exit 1
fi

log_info "✓ All files verified"

# Step 10: Create verification script
log_step "Creating test verification script..."
cat > /tmp/verify-bootstrap.sh << 'EOF'
#!/bin/bash
echo "=== Bootstrap Verification ==="
echo "Scripts installed:"
ls -lh /usr/local/bin/free-agent* /usr/local/bin/vm-monitor.sh /usr/local/bin/install-signing-certs
echo ""
echo "Version:"
cat /usr/local/etc/free-agent-version || echo "WARNING: Version file not found"
echo ""
echo "LaunchDaemons:"
ls -lh /Library/LaunchDaemons/com.expo.*.plist
echo ""
echo "Dependencies:"
which jq || echo "WARNING: jq not found"
which curl || echo "ERROR: curl not found"
which security || echo "ERROR: security not found"
echo ""
echo "✓ VM template ready for secure certificate handling with auto-update"
EOF

copy_file_to_vm "/tmp/verify-bootstrap.sh" "/tmp/verify-bootstrap.sh" "0755"
tart exec "$VM_NAME" bash /tmp/verify-bootstrap.sh
rm /tmp/verify-bootstrap.sh

# Step 11: Stop VM
log_step "Stopping VM..."
tart stop "$VM_NAME"
log_info "✓ VM stopped cleanly"

# Success!
echo ""
log_info "=== Installation Complete ==="
log_info "VM template '$VM_NAME' is now ready with extensible bootstrap architecture"
echo ""
log_info "Architecture:"
echo "  • VM contains minimal security stub (free-agent-stub.sh)"
echo "  • Stub randomizes password, deletes SSH keys, then execs worker bootstrap"
echo "  • Worker provides versioned bootstrap.sh via mount"
echo "  • Bootstrap updates without VM image rebuilds"
echo ""
log_info "Next steps:"
echo "  1. Test the template:"
echo "     ./vm-setup/test-vm-bootstrap.sh $VM_NAME"
echo ""
echo "  2. Push to registry via release script"
echo ""
log_info "On boot, stub will exec /Volumes/My Shared Files/build-config/bootstrap.sh"
