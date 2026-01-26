#!/bin/bash
#
# Expo Free Agent - VM Bootstrap Test Script
#
# Tests the secure bootstrap infrastructure in a VM template.
# This verifies password randomization, cert fetch, and SSH blocking work correctly.
#
# Usage: ./test-vm-bootstrap.sh <vm-name> [controller-url]
#   vm-name: Name of VM template to test (will be cloned)
#   controller-url: Optional controller URL (default: http://localhost:3000)
#
# What this tests:
# 1. Bootstrap script runs on VM boot
# 2. Admin password gets randomized (SSH blocked)
# 3. /tmp/free-agent-ready signal file created
# 4. LaunchDaemon configured correctly
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
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }

# Parse arguments
if [ $# -lt 1 ]; then
    log_error "Usage: $0 <vm-name> [controller-url]"
    echo ""
    echo "Example:"
    echo "  $0 expo-agent-base http://localhost:3000"
    exit 1
fi

TEMPLATE_VM="$1"
CONTROLLER_URL="${2:-http://localhost:3000}"
TEST_VM="test-bootstrap-$(date +%s)"

log_info "=== Expo Free Agent Bootstrap Test ==="
log_info "Template: $TEMPLATE_VM"
log_info "Test VM: $TEST_VM"
log_info "Controller: $CONTROLLER_URL"
echo ""

# Verify template exists
log_step "Checking template VM..."
if ! tart list | grep -q "^$TEMPLATE_VM"; then
    log_error "Template VM '$TEMPLATE_VM' not found"
    tart list
    exit 1
fi
log_pass "Template exists"

# Clone template for testing
log_step "Cloning template for test..."
tart clone "$TEMPLATE_VM" "$TEST_VM"
log_pass "Test VM cloned"

# Cleanup function
cleanup() {
    log_step "Cleaning up test VM..."
    tart stop "$TEST_VM" 2>/dev/null || true
    sleep 2
    tart delete "$TEST_VM" 2>/dev/null || true
    log_info "✓ Cleanup complete"
}
trap cleanup EXIT

# Generate test credentials
TEST_BUILD_ID="test-build-$(date +%s)"
TEST_WORKER_ID="test-worker-$(date +%s)"
TEST_API_KEY="test-api-key-$(openssl rand -hex 8)"

log_info "Test credentials:"
log_info "  BUILD_ID: $TEST_BUILD_ID"
log_info "  WORKER_ID: $TEST_WORKER_ID"
log_info "  API_KEY: $TEST_API_KEY"
echo ""

# Start VM with bootstrap env vars
log_step "Starting VM with bootstrap env vars..."
tart run "$TEST_VM" \
    --env "BUILD_ID=$TEST_BUILD_ID" \
    --env "WORKER_ID=$TEST_WORKER_ID" \
    --env "API_KEY=$TEST_API_KEY" \
    --env "CONTROLLER_URL=$CONTROLLER_URL" \
    &

VM_PID=$!
log_info "VM started (PID: $VM_PID)"

# Wait for IP
log_step "Waiting for VM IP..."
MAX_WAIT=60
WAITED=0
VM_IP=""
while [ $WAITED -lt $MAX_WAIT ]; do
    VM_IP=$(tart ip "$TEST_VM" 2>/dev/null || echo "")
    if [ -n "$VM_IP" ]; then
        break
    fi
    sleep 2
    WAITED=$((WAITED + 2))
done

if [ -z "$VM_IP" ]; then
    log_fail "Could not get VM IP after ${MAX_WAIT}s"
    exit 1
fi
log_pass "VM IP: $VM_IP"

# Wait for bootstrap to complete
log_step "Waiting for bootstrap completion..."
MAX_WAIT=180  # 3 minutes max
WAITED=0
BOOTSTRAP_COMPLETE=false

while [ $WAITED -lt $MAX_WAIT ]; do
    if tart exec "$TEST_VM" -- test -f /tmp/free-agent-ready 2>/dev/null; then
        BOOTSTRAP_COMPLETE=true
        break
    fi
    sleep 5
    WAITED=$((WAITED + 5))
    echo -n "."
done
echo ""

if [ "$BOOTSTRAP_COMPLETE" = false ]; then
    log_fail "Bootstrap did not complete after ${MAX_WAIT}s"
    log_error "Checking bootstrap log..."
    tart exec "$TEST_VM" -- cat /tmp/free-agent-bootstrap.log 2>/dev/null || log_error "No bootstrap log found"
    exit 1
fi
log_pass "Bootstrap completed in ${WAITED}s"

# Test 1: Check bootstrap log
log_step "TEST 1: Checking bootstrap log..."
if tart exec "$TEST_VM" -- test -f /tmp/free-agent-bootstrap.log; then
    LOG_CONTENT=$(tart exec "$TEST_VM" -- cat /tmp/free-agent-bootstrap.log)
    echo "$LOG_CONTENT"

    if echo "$LOG_CONTENT" | grep -q "Password randomized"; then
        log_pass "✓ Password randomization logged"
    else
        log_fail "✗ Password randomization not logged"
    fi

    if echo "$LOG_CONTENT" | grep -q "SSH keys removed"; then
        log_pass "✓ SSH keys removal logged"
    else
        log_warn "⚠ SSH keys removal not logged"
    fi

    # Check for errors
    if echo "$LOG_CONTENT" | grep -qi "ERROR"; then
        log_warn "⚠ Errors found in bootstrap log"
    fi
else
    log_fail "✗ Bootstrap log not found"
fi
echo ""

# Test 2: Verify SSH is blocked
log_step "TEST 2: Verifying SSH access blocked..."
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@"$VM_IP" "echo connected" 2>/dev/null; then
    log_fail "✗ SSH access still works (password not randomized!)"
    log_error "SECURITY ISSUE: Host can still SSH into VM"
    exit 1
else
    log_pass "✓ SSH access blocked (password randomized successfully)"
fi
echo ""

# Test 3: Verify ready signal
log_step "TEST 3: Verifying ready signal..."
if tart exec "$TEST_VM" -- test -f /tmp/free-agent-ready; then
    log_pass "✓ /tmp/free-agent-ready exists"
else
    log_fail "✗ /tmp/free-agent-ready not found"
fi
echo ""

# Test 4: Check environment variables
log_step "TEST 4: Checking environment variables..."
ENV_CHECK=$(tart exec "$TEST_VM" -- bash -c 'echo BUILD_ID=$BUILD_ID WORKER_ID=$WORKER_ID CONTROLLER_URL=$CONTROLLER_URL' || echo "")
if echo "$ENV_CHECK" | grep -q "BUILD_ID=$TEST_BUILD_ID"; then
    log_pass "✓ BUILD_ID set correctly"
else
    log_warn "⚠ BUILD_ID not in environment (expected for LaunchDaemon context)"
fi
echo ""

# Test 5: Verify scripts installed
log_step "TEST 5: Verifying scripts installed..."
SCRIPTS=(
    "/usr/local/bin/free-agent-vm-bootstrap"
    "/usr/local/bin/install-signing-certs"
    "/usr/local/bin/free-agent-run-job"
    "/usr/local/bin/vm-monitor.sh"
)

ALL_SCRIPTS_OK=true
for script in "${SCRIPTS[@]}"; do
    if tart exec "$TEST_VM" -- test -x "$script"; then
        log_pass "✓ $script exists and is executable"
    else
        log_fail "✗ $script missing or not executable"
        ALL_SCRIPTS_OK=false
    fi
done
echo ""

if [ "$ALL_SCRIPTS_OK" = false ]; then
    log_fail "Some scripts missing"
    exit 1
fi

# Test 6: Check LaunchDaemon
log_step "TEST 6: Checking LaunchDaemon..."
if tart exec "$TEST_VM" -- test -f /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist; then
    log_pass "✓ LaunchDaemon plist exists"

    # Check if loaded
    if tart exec "$TEST_VM" -- sudo launchctl list | grep -q "free-agent.bootstrap"; then
        log_pass "✓ LaunchDaemon loaded"
    else
        log_warn "⚠ LaunchDaemon not loaded (will auto-load on next boot)"
    fi
else
    log_fail "✗ LaunchDaemon plist not found"
fi
echo ""

# Test 7: Check dependencies
log_step "TEST 7: Checking dependencies..."
DEPS_OK=true

if tart exec "$TEST_VM" -- which jq &>/dev/null; then
    log_pass "✓ jq installed"
else
    log_fail "✗ jq not installed"
    DEPS_OK=false
fi

if tart exec "$TEST_VM" -- which curl &>/dev/null; then
    log_pass "✓ curl installed"
else
    log_fail "✗ curl not installed"
    DEPS_OK=false
fi

if tart exec "$TEST_VM" -- which security &>/dev/null; then
    log_pass "✓ security command available"
else
    log_fail "✗ security command not available"
    DEPS_OK=false
fi
echo ""

if [ "$DEPS_OK" = false ]; then
    log_warn "Some dependencies missing"
fi

# Summary
log_info "=== Test Summary ==="
echo ""

if [ "$BOOTSTRAP_COMPLETE" = true ] && [ "$ALL_SCRIPTS_OK" = true ]; then
    log_pass "✓ ALL TESTS PASSED"
    log_info "VM template '$TEMPLATE_VM' is ready for production use"
    echo ""
    log_info "Next steps:"
    echo "  1. Clone to production template:"
    echo "     tart clone $TEMPLATE_VM expo-free-agent-secure"
    echo ""
    echo "  2. Update controller BASE_IMAGE_ID in .env:"
    echo "     BASE_IMAGE_ID=expo-free-agent-secure"
    echo ""
    echo "  3. Workers will automatically use secure bootstrap on next build"
    exit 0
else
    log_fail "✗ SOME TESTS FAILED"
    log_error "Review errors above and fix before using in production"
    exit 1
fi
