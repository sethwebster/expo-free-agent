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
if ! tart list | grep -q "^$VM_NAME"; then
    log_error "VM '$VM_NAME' not found"
    log_error "Available VMs:"
    tart list
    exit 1
fi

if tart list | grep "^$VM_NAME" | grep -q "running"; then
    log_error "VM '$VM_NAME' is running - please stop it first:"
    log_error "  tart stop $VM_NAME"
    exit 1
fi
log_info "✓ VM found and stopped"

# Step 3: Verify required scripts exist
log_step "Verifying script files..."
REQUIRED_FILES=(
    "free-agent-vm-bootstrap"
    "install-signing-certs"
    "vm-monitor.sh"
    "free-agent-run-job"
    "com.expo.free-agent.bootstrap.plist"
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
tart exec "$VM_NAME" -- bash -c "brew list jq &>/dev/null || brew install jq" || {
    log_warn "Failed to install jq - you may need to install manually"
}
log_info "✓ Dependencies installed"

# Step 6: Copy scripts to VM
log_step "Copying scripts to VM..."

# Bootstrap script
tart exec "$VM_NAME" -- bash -c "cat > /tmp/free-agent-vm-bootstrap" < "$SCRIPT_DIR/free-agent-vm-bootstrap"
tart exec "$VM_NAME" -- sudo mv /tmp/free-agent-vm-bootstrap /usr/local/bin/
tart exec "$VM_NAME" -- sudo chmod +x /usr/local/bin/free-agent-vm-bootstrap
log_info "✓ Installed free-agent-vm-bootstrap"

# Cert installer
tart exec "$VM_NAME" -- bash -c "cat > /tmp/install-signing-certs" < "$SCRIPT_DIR/install-signing-certs"
tart exec "$VM_NAME" -- sudo mv /tmp/install-signing-certs /usr/local/bin/
tart exec "$VM_NAME" -- sudo chmod +x /usr/local/bin/install-signing-certs
log_info "✓ Installed install-signing-certs"

# Build runner
tart exec "$VM_NAME" -- bash -c "cat > /tmp/free-agent-run-job" < "$SCRIPT_DIR/free-agent-run-job"
tart exec "$VM_NAME" -- sudo mv /tmp/free-agent-run-job /usr/local/bin/
tart exec "$VM_NAME" -- sudo chmod +x /usr/local/bin/free-agent-run-job
log_info "✓ Installed free-agent-run-job"

# VM monitor
tart exec "$VM_NAME" -- bash -c "cat > /tmp/vm-monitor.sh" < "$SCRIPT_DIR/vm-monitor.sh"
tart exec "$VM_NAME" -- sudo mv /tmp/vm-monitor.sh /usr/local/bin/
tart exec "$VM_NAME" -- sudo chmod +x /usr/local/bin/vm-monitor.sh
log_info "✓ Installed vm-monitor.sh"

# Step 7: Install LaunchDaemon
log_step "Installing LaunchDaemon..."
tart exec "$VM_NAME" -- bash -c "cat > /tmp/com.expo.free-agent.bootstrap.plist" < "$SCRIPT_DIR/com.expo.free-agent.bootstrap.plist"
tart exec "$VM_NAME" -- sudo mv /tmp/com.expo.free-agent.bootstrap.plist /Library/LaunchDaemons/
tart exec "$VM_NAME" -- sudo chown root:wheel /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist
tart exec "$VM_NAME" -- sudo chmod 644 /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist
log_info "✓ LaunchDaemon installed"

# Step 8: Load LaunchDaemon
log_step "Loading LaunchDaemon..."
tart exec "$VM_NAME" -- sudo launchctl load /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist || {
    log_warn "LaunchDaemon load failed - may already be loaded or will auto-load on next boot"
}
log_info "✓ LaunchDaemon configured"

# Step 9: Verify installation
log_step "Verifying installation..."
VERIFICATION_FAILED=false

# Check scripts exist with correct permissions
for script in free-agent-vm-bootstrap install-signing-certs free-agent-run-job vm-monitor.sh; do
    if ! tart exec "$VM_NAME" -- test -x "/usr/local/bin/$script"; then
        log_error "Script not executable: $script"
        VERIFICATION_FAILED=true
    fi
done

# Check LaunchDaemon
if ! tart exec "$VM_NAME" -- test -f /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist; then
    log_error "LaunchDaemon plist not found"
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
echo "LaunchDaemon:"
ls -lh /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist
echo ""
echo "Dependencies:"
which jq || echo "WARNING: jq not found"
which curl || echo "ERROR: curl not found"
which security || echo "ERROR: security not found"
echo ""
echo "✓ VM template ready for secure certificate handling"
EOF

tart exec "$VM_NAME" -- bash -c "cat > /tmp/verify-bootstrap.sh" < /tmp/verify-bootstrap.sh
tart exec "$VM_NAME" -- chmod +x /tmp/verify-bootstrap.sh
tart exec "$VM_NAME" -- /tmp/verify-bootstrap.sh
rm /tmp/verify-bootstrap.sh

# Step 11: Stop VM
log_step "Stopping VM..."
tart stop "$VM_NAME"
log_info "✓ VM stopped cleanly"

# Success!
echo ""
log_info "=== Installation Complete ==="
log_info "VM template '$VM_NAME' is now ready for secure certificate handling"
echo ""
log_info "Next steps:"
echo "  1. Test the template:"
echo "     ./vm-setup/test-vm-bootstrap.sh $VM_NAME"
echo ""
echo "  2. Clone to production template:"
echo "     tart clone $VM_NAME expo-free-agent-tahoe-26.2-xcode-expo-54-secure"
echo ""
echo "  3. Update controller BASE_IMAGE_ID:"
echo "     export BASE_IMAGE_ID=expo-free-agent-tahoe-26.2-xcode-expo-54-secure"
echo ""
log_info "Secure bootstrap will activate on next VM boot with env vars:"
log_info "  BUILD_ID, WORKER_ID, API_KEY, CONTROLLER_URL"
