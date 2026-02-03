#!/bin/bash
#
# CLI-Based End-to-End Test
#
# True E2E test that uses the CLI commands (expo-free-agent)
# instead of direct API calls, testing the complete user experience.
#
# Tests:
# - expo-free-agent submit (with certificates)
# - expo-free-agent status --watch
# - expo-free-agent download
# - expo-free-agent list
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_DIR=".test-e2e-cli"
CONTROLLER_PORT=4446
API_KEY="e2e-cli-test-api-key-minimum-32-characters-long"
CONTROLLER_URL="http://localhost:${CONTROLLER_PORT}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

cleanup() {
    log_info "Cleaning up..."

    # Kill controller
    if [ ! -z "$CONTROLLER_PID" ]; then
        log_info "Stopping controller (PID: $CONTROLLER_PID)"
        kill $CONTROLLER_PID 2>/dev/null || true
        wait $CONTROLLER_PID 2>/dev/null || true
    fi

    # Kill worker
    if [ ! -z "$WORKER_PID" ]; then
        log_info "Stopping worker (PID: $WORKER_PID)"
        kill $WORKER_PID 2>/dev/null || true
        wait $WORKER_PID 2>/dev/null || true
    fi

    # Clean up VMs
    log_info "Checking for orphaned VMs..."
    /opt/homebrew/bin/tart list | grep "^build-" | awk '{print $1}' | while read vm; do
        log_warning "Cleaning up VM: $vm"
        /opt/homebrew/bin/tart stop "$vm" 2>/dev/null || true
        /opt/homebrew/bin/tart delete "$vm" 2>/dev/null || true
    done

    # Clean up certs
    if [ -n "$CERTS_ZIP" ] && [ -f "$CERTS_ZIP" ]; then
        CERTS_DIR=$(dirname "$CERTS_ZIP")
        if [[ "$CERTS_DIR" == /tmp/* ]] || [[ "$CERTS_DIR" == /var/folders/* ]]; then
            rm -rf "$CERTS_DIR" 2>/dev/null || true
        fi
    fi

    # Drop database
    if [ -d "$ORIGINAL_DIR/packages/controller-elixir" ]; then
        cd "$ORIGINAL_DIR/packages/controller-elixir"
        MIX_ENV=test mix ecto.drop > /dev/null 2>&1 || true
        cd "$ORIGINAL_DIR"
    fi

    # Remove test directory
    if [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi

    log_success "Cleanup complete"
}

trap cleanup EXIT

log_info "=========================================="
log_info "  CLI-Based E2E Test"
log_info "=========================================="
echo ""

ORIGINAL_DIR=$(pwd)

# Step 1: Build CLI
log_info "Step 1: Building CLI"
cd packages/cli
bun run build > /dev/null 2>&1
CLI_PATH="$ORIGINAL_DIR/packages/cli/dist/index.js"
log_success "✓ CLI built: $CLI_PATH"
cd "$ORIGINAL_DIR"
echo ""

# Step 2: Start controller
log_info "Step 2: Starting controller on port ${CONTROLLER_PORT}"

lsof -ti:${CONTROLLER_PORT} | xargs kill -9 2>/dev/null || true
sleep 2

cd packages/controller-elixir
mix ecto.reset --quiet 2>&1 || true

mkdir -p "$ORIGINAL_DIR/$TEST_DIR/storage"

CONTROLLER_API_KEY="$API_KEY" PORT="$CONTROLLER_PORT" \
    STORAGE_ROOT="$ORIGINAL_DIR/$TEST_DIR/storage" \
    mix phx.server > "$ORIGINAL_DIR/$TEST_DIR/controller.log" 2>&1 &
CONTROLLER_PID=$!

log_info "Controller started (PID: $CONTROLLER_PID)"
cd "$ORIGINAL_DIR"

# Wait for controller
sleep 5
MAX_WAIT=30
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    if curl -s -f "$CONTROLLER_URL/health" > /dev/null 2>&1; then
        log_success "Controller is healthy"
        break
    fi
    sleep 1
    WAITED=$((WAITED + 1))
done

if [ $WAITED -ge $MAX_WAIT ]; then
    log_error "Controller failed to start"
    exit 1
fi
echo ""

# Step 3: Configure CLI
log_info "Step 3: Configuring CLI"
export EXPO_CONTROLLER_URL="$CONTROLLER_URL"
export EXPO_CONTROLLER_API_KEY="$API_KEY"
log_success "✓ CLI configured"
log_info "  Controller: $CONTROLLER_URL"
echo ""

# Step 4: Prepare test project
log_info "Step 4: Preparing test project"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

MINIMAL_APP="$ORIGINAL_DIR/test/fixtures/minimal-test-app"
if [ ! -d "$MINIMAL_APP" ]; then
    log_error "Test fixture not found: $MINIMAL_APP"
    exit 1
fi

cp -R "$MINIMAL_APP" test-project
log_success "✓ Test project copied"
echo ""

# Step 5: Find certificates
log_info "Step 5: Finding iOS signing certificates"
echo ""

CERTS_ZIP=""
CERT_FINDER="$ORIGINAL_DIR/test/find-dev-certs.sh"

if [ -x "$CERT_FINDER" ]; then
    CERTS_ZIP=$("$CERT_FINDER")
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ] && [ -n "$CERTS_ZIP" ] && [ -f "$CERTS_ZIP" ]; then
        log_success "✓ Certificates found: $CERTS_ZIP"
    else
        log_error "Certificate discovery failed"
        exit 1
    fi
else
    log_error "Certificate finder not found: $CERT_FINDER"
    exit 1
fi
echo ""

# Step 6: Start worker
log_info "Step 6: Starting worker"

BASE_IMAGE="expo-free-agent-base-local"
if ! /opt/homebrew/bin/tart list | awk '{print $2}' | grep -q "^${BASE_IMAGE}\$"; then
    log_error "Base VM image not found: $BASE_IMAGE"
    log_error "Run: ./vm-setup/setup-local-test-image.sh"
    exit 1
fi

bun "$ORIGINAL_DIR/test/real-worker.ts" \
    --url "$CONTROLLER_URL" \
    --api-key "$API_KEY" \
    --name "e2e-cli-worker" \
    --platform ios \
    --base-image "$BASE_IMAGE" \
    --build-timeout 1200 > "$ORIGINAL_DIR/$TEST_DIR/worker.log" 2>&1 &
WORKER_PID=$!

log_success "✓ Worker started (PID: $WORKER_PID)"
sleep 3
echo ""

# Step 7: Submit build using CLI
log_info "Step 7: Submitting build via CLI"
log_info "  Command: expo-free-agent submit"
echo ""

# Submit build
SUBMIT_OUTPUT=$(node "$CLI_PATH" submit test-project \
    --certs "$CERTS_ZIP" \
    --platform ios 2>&1)

echo "$SUBMIT_OUTPUT"
echo ""

# Extract build ID from output
BUILD_ID=$(echo "$SUBMIT_OUTPUT" | grep -o "Build ID: [a-zA-Z0-9_-]*" | cut -d' ' -f3)

if [ -z "$BUILD_ID" ]; then
    log_error "Failed to extract build ID from CLI output"
    log_error "Output: $SUBMIT_OUTPUT"
    exit 1
fi

log_success "✓ Build submitted: $BUILD_ID"
echo ""

# Step 8: Watch build status using CLI
log_info "Step 8: Watching build status via CLI"
log_info "  Command: expo-free-agent status $BUILD_ID --watch"
log_warning "This may take 15-30 minutes for a real iOS build..."
echo ""

# Watch status (with timeout)
timeout 1800 node "$CLI_PATH" status "$BUILD_ID" --watch || {
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 124 ]; then
        log_error "Build timed out after 30 minutes"
    else
        log_error "Build failed or status command failed"
    fi
    exit 1
}

log_success "✓ Build completed"
echo ""

# Step 9: Download artifact using CLI
log_info "Step 9: Downloading artifact via CLI"
log_info "  Command: expo-free-agent download $BUILD_ID"
echo ""

node "$CLI_PATH" download "$BUILD_ID" -o result.ipa

if [ ! -f "result.ipa" ]; then
    log_error "Download failed - result.ipa not found"
    exit 1
fi

FILE_SIZE=$(stat -f%z result.ipa 2>/dev/null || stat -c%s result.ipa 2>/dev/null)
log_success "✓ Artifact downloaded (${FILE_SIZE} bytes)"

if [ "$FILE_SIZE" -gt 10000000 ]; then
    log_success "✓ File size indicates real build"
fi
echo ""

# Step 10: List builds using CLI
log_info "Step 10: Listing builds via CLI"
log_info "  Command: expo-free-agent list"
echo ""

LIST_OUTPUT=$(node "$CLI_PATH" list)
echo "$LIST_OUTPUT"

if echo "$LIST_OUTPUT" | grep -q "$BUILD_ID"; then
    log_success "✓ Build appears in list"
else
    log_warning "Build not found in list output"
fi
echo ""

# All tests passed
log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "  CLI E2E Tests Passed! ✓"
log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

log_info "Tests validated:"
log_success "  ✓ expo-free-agent submit (with certificates)"
log_success "  ✓ expo-free-agent status --watch"
log_success "  ✓ expo-free-agent download"
log_success "  ✓ expo-free-agent list"
log_success "  ✓ Full build pipeline (VM + bootstrap + build)"
echo ""

log_info "Test artifacts available in: $TEST_DIR"
log_info "  - controller.log: Controller output"
log_info "  - worker.log: Worker output"
log_info "  - result.ipa: Downloaded build artifact"
echo ""

exit 0
