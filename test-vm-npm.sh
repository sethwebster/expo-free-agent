#!/bin/bash
#
# Quick VM Test: Verify npm install works
#
# This test starts a clean VM, creates a test project,
# runs npm install, and verifies node_modules is created.
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

VM_NAME="expo-free-agent-base-local"

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    /opt/homebrew/bin/tart stop "$VM_NAME" 2>/dev/null || true
    log_success "Cleanup complete"
}

trap cleanup EXIT

log_info "=========================================="
log_info "  Quick VM Test: npm install"
log_info "=========================================="
echo ""

# Check VM exists
if ! /opt/homebrew/bin/tart list | awk '{print $2}' | grep -q "^${VM_NAME}\$"; then
    log_error "VM '$VM_NAME' not found"
    log_error "Run: ./vm-setup/setup-local-test-image.sh"
    exit 1
fi

log_info "Starting VM..."
/opt/homebrew/bin/tart run "$VM_NAME" &
TART_PID=$!
sleep 20

log_info "Waiting for VM to boot..."
MAX_WAIT=60
WAITED=0
VM_IP=""
while [ $WAITED -lt $MAX_WAIT ]; do
    VM_IP=$(/opt/homebrew/bin/tart ip "$VM_NAME" 2>/dev/null || echo "")
    if [ -n "$VM_IP" ]; then
        break
    fi
    sleep 2
    WAITED=$((WAITED + 2))
done

if [ -z "$VM_IP" ]; then
    log_error "Could not get VM IP after ${MAX_WAIT}s"
    exit 1
fi

log_success "VM ready (IP: $VM_IP)"
echo ""

log_info "Testing npm install in VM..."
echo ""

# Create test project and run npm install
TEST_OUTPUT=$(/opt/homebrew/bin/tart exec "$VM_NAME" bash <<'VMSCRIPT'
set -e

# Verify Node.js and npm are installed
echo "Checking Node.js installation..."
node --version || { echo "ERROR: Node.js not found"; exit 1; }
npm --version || { echo "ERROR: npm not found"; exit 1; }
echo ""

# Create test project
echo "Creating test project..."
mkdir -p /tmp/npm-test
cd /tmp/npm-test

cat > package.json <<'EOF'
{
  "name": "npm-test",
  "version": "1.0.0",
  "dependencies": {
    "react": "19.1.0"
  }
}
EOF

echo "Running npm install..."
npm install 2>&1

# Verify node_modules exists
if [ -d "node_modules" ]; then
    echo ""
    echo "✓ npm install succeeded"
    echo "✓ node_modules created"
    ls -1 node_modules | head -5
    exit 0
else
    echo ""
    echo "✗ npm install failed - node_modules not created"
    exit 1
fi
VMSCRIPT
)

EXIT_CODE=$?

echo "$TEST_OUTPUT"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    log_success "✅ Test passed - npm install works in VM"
    echo ""
    log_info "VM is ready for Expo builds!"
else
    log_error "❌ Test failed - npm install failed"
    exit 1
fi
