#!/bin/bash
#
# CLI Flow Test (No Certificates)
#
# Tests CLI commands without requiring certificates or full builds.
# Validates that CLI commands work end-to-end:
# - submit (without certs)
# - status
# - list
#
# This is faster than full E2E and doesn't require interactive input.
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_DIR=".test-cli-flow"
CONTROLLER_PORT=4447
API_KEY="cli-flow-test-api-key-minimum-32-chars"
CONTROLLER_URL="http://localhost:${CONTROLLER_PORT}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

cleanup() {
    log_info "Cleaning up..."

    if [ ! -z "$CONTROLLER_PID" ]; then
        log_info "Stopping controller (PID: $CONTROLLER_PID)"
        kill $CONTROLLER_PID 2>/dev/null || true
        wait $CONTROLLER_PID 2>/dev/null || true
    fi

    # Drop database
    if [ -d "$ORIGINAL_DIR/packages/controller-elixir" ]; then
        cd "$ORIGINAL_DIR/packages/controller-elixir"
        MIX_ENV=test mix ecto.drop > /dev/null 2>&1 || true
        cd "$ORIGINAL_DIR"
    fi

    if [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi

    log_success "Cleanup complete"
}

trap cleanup EXIT

log_info "=========================================="
log_info "  CLI Flow Test (No Certificates)"
log_info "=========================================="
echo ""

ORIGINAL_DIR=$(pwd)

# Step 1: Build CLI
log_info "Step 1: Building CLI"
cd packages/cli
bun run build > /dev/null 2>&1
CLI_PATH="$ORIGINAL_DIR/packages/cli/dist/index.js"
log_success "✓ CLI built"
cd "$ORIGINAL_DIR"
echo ""

# Step 2: Start controller
log_info "Step 2: Starting controller"

lsof -ti:${CONTROLLER_PORT} | xargs kill -9 2>/dev/null || true
sleep 2

cd packages/controller-elixir
mix ecto.reset --quiet 2>&1 || true

mkdir -p "$ORIGINAL_DIR/$TEST_DIR/storage"

CONTROLLER_API_KEY="$API_KEY" PORT="$CONTROLLER_PORT" \
    STORAGE_ROOT="$ORIGINAL_DIR/$TEST_DIR/storage" \
    mix phx.server > "$ORIGINAL_DIR/$TEST_DIR/controller.log" 2>&1 &
CONTROLLER_PID=$!

cd "$ORIGINAL_DIR"

# Wait for controller
sleep 5
MAX_WAIT=30
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    if curl -s -f "$CONTROLLER_URL/health" > /dev/null 2>&1; then
        log_success "✓ Controller ready"
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
echo ""

# Step 4: Prepare test project
log_info "Step 4: Preparing test project"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

cp -R "$ORIGINAL_DIR/test/fixtures/minimal-test-app" test-project
log_success "✓ Test project copied"
echo ""

# Step 5: Test submit command (no certs)
log_info "Step 5: Testing 'expo-free-agent submit --no-certs'"
echo ""

SUBMIT_OUTPUT=$(node "$CLI_PATH" submit test-project --no-certs --platform ios 2>&1)
echo "$SUBMIT_OUTPUT"
echo ""

# Extract build ID
BUILD_ID=$(echo "$SUBMIT_OUTPUT" | grep -o "Build ID: [a-zA-Z0-9_-]*" | cut -d' ' -f3)

if [ -z "$BUILD_ID" ]; then
    log_error "Failed to extract build ID"
    log_error "Output: $SUBMIT_OUTPUT"
    exit 1
fi

log_success "✓ Submit works: $BUILD_ID"
echo ""

# Step 6: Test status command
log_info "Step 6: Testing 'expo-free-agent status'"
echo ""

STATUS_OUTPUT=$(node "$CLI_PATH" status "$BUILD_ID" 2>&1)
echo "$STATUS_OUTPUT"
echo ""

if echo "$STATUS_OUTPUT" | grep -q "Status:"; then
    log_success "✓ Status command works"
else
    log_error "Status command failed"
    exit 1
fi
echo ""

# Step 7: Test list command
log_info "Step 7: Testing 'expo-free-agent list'"
echo ""

LIST_OUTPUT=$(node "$CLI_PATH" list 2>&1)
echo "$LIST_OUTPUT"
echo ""

if echo "$LIST_OUTPUT" | grep -q "$BUILD_ID"; then
    log_success "✓ List command works"
else
    log_error "Build not found in list"
    exit 1
fi
echo ""

# Step 8: Test config command
log_info "Step 8: Testing 'expo-free-agent config'"
echo ""

CONFIG_OUTPUT=$(node "$CLI_PATH" config --show 2>&1)
echo "$CONFIG_OUTPUT"
echo ""

if echo "$CONFIG_OUTPUT" | grep -q "Controller URL"; then
    log_success "✓ Config command works"
else
    log_error "Config command failed"
    exit 1
fi
echo ""

# All tests passed
log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "  CLI Flow Tests Passed! ✓"
log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

log_info "Validated CLI commands:"
log_success "  ✓ expo-free-agent submit --no-certs"
log_success "  ✓ expo-free-agent status <build-id>"
log_success "  ✓ expo-free-agent list"
log_success "  ✓ expo-free-agent config --show"
echo ""

log_info "Note: Full E2E test with builds requires:"
log_info "  - ./test-e2e-cli.sh (interactive certificate selection)"
log_info "  - Worker running with VM support"
echo ""

exit 0
