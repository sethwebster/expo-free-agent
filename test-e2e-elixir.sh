#!/bin/bash

#
# End-to-End Test Script for Elixir Controller
# Tests the complete build submission → assignment → completion flow
# Modified from test-e2e.sh to work with Elixir controller on port 4000
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TEST_DIR=".test-e2e-elixir"
CONTROLLER_PORT=4444
API_KEY="test-api-key-for-e2e-testing-minimum-32-chars"
CONTROLLER_URL="http://localhost:${CONTROLLER_PORT}"
CONTROLLER_PID=""

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup() {
    log_info "Cleaning up..."

    # Kill worker if running
    if [ ! -z "$WORKER_PID" ]; then
        log_info "Stopping mock worker (PID: $WORKER_PID)"
        kill $WORKER_PID 2>/dev/null || true
        wait $WORKER_PID 2>/dev/null || true
    fi

    # Kill controller if we started it
    if [ ! -z "$CONTROLLER_PID" ]; then
        log_info "Stopping Elixir controller (PID: $CONTROLLER_PID)"
        kill $CONTROLLER_PID 2>/dev/null || true
        wait $CONTROLLER_PID 2>/dev/null || true
    fi

    # Remove test directory
    if [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi

    log_success "Cleanup complete"
}

# Trap exit to cleanup
trap cleanup EXIT

check_health() {
    local url=$1
    local max_attempts=30
    local attempt=1

    log_info "Waiting for controller to be healthy..."

    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "$url/health" > /dev/null 2>&1; then
            log_success "Controller is healthy"
            return 0
        fi

        echo -n "."
        sleep 1
        attempt=$((attempt + 1))
    done

    log_error "Controller failed to become healthy after ${max_attempts}s"
    return 1
}

wait_for_build_completion() {
    local build_id=$1
    local max_wait=60
    local elapsed=0

    log_info "Waiting for build to complete..."

    while [ $elapsed -lt $max_wait ]; do
        status=$(curl -s -H "X-API-Key: $API_KEY" "$CONTROLLER_URL/api/builds/$build_id/status" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

        if [ "$status" = "completed" ]; then
            log_success "Build completed"
            return 0
        elif [ "$status" = "failed" ]; then
            log_error "Build failed"
            return 1
        fi

        echo -n "."
        sleep 2
        elapsed=$((elapsed + 2))
    done

    log_error "Build did not complete within ${max_wait}s"
    return 1
}

# Start test
log_info "Starting E2E Test for Elixir Controller"
echo ""

# Save original directory
ORIGINAL_DIR=$(pwd)

# Create test directory
mkdir -p "$TEST_DIR"

# Step 1: Check if Elixir controller is running, start if needed
log_info "Step 1: Checking if Elixir controller is running on port ${CONTROLLER_PORT}"

# Verify it's our controller by checking for unique response
HEALTH_RESPONSE=$(curl -s "$CONTROLLER_URL/health" 2>/dev/null || echo "")
if echo "$HEALTH_RESPONSE" | grep -q '"queue"'; then
    log_success "Controller already running and verified (port ${CONTROLLER_PORT})"
else
    log_warning "Controller not running or not ours, starting Elixir controller..."

    # Start Elixir controller in background
    cd "$ORIGINAL_DIR/packages/controller_elixir"

    log_info "Starting Elixir controller on port ${CONTROLLER_PORT}..."
    env CONTROLLER_API_KEY="$API_KEY" PORT="$CONTROLLER_PORT" MIX_ENV=dev mix phx.server > "$ORIGINAL_DIR/$TEST_DIR/controller.log" 2>&1 &
    CONTROLLER_PID=$!

    cd "$ORIGINAL_DIR"

    log_info "Controller started (PID: $CONTROLLER_PID)"
    log_info "Waiting for controller to be healthy..."

    if ! check_health "$CONTROLLER_URL"; then
        log_error "Controller failed to start"
        log_error "Check logs at: $TEST_DIR/controller.log"
        tail -n 40 "$TEST_DIR/controller.log" 2>/dev/null || true
        exit 1
    fi

    # Double-check it's our controller
    HEALTH_RESPONSE=$(curl -s "$CONTROLLER_URL/health")
    if ! echo "$HEALTH_RESPONSE" | grep -q '"queue"'; then
        log_error "Health endpoint exists but doesn't match our controller format"
        log_error "Response: $HEALTH_RESPONSE"
        exit 1
    fi
    log_success "Controller verified"
fi

echo ""

# Step 2: Create test Expo project
log_info "Step 2: Creating test Expo project"
cd "$ORIGINAL_DIR/$TEST_DIR"
mkdir -p test-project
cat > test-project/app.json <<EOF
{
  "expo": {
    "name": "E2E Test App",
    "slug": "e2e-test-app",
    "version": "1.0.0",
    "platforms": ["ios", "android"]
  }
}
EOF

cat > test-project/package.json <<EOF
{
  "name": "e2e-test-app",
  "version": "1.0.0",
  "main": "index.js"
}
EOF

echo 'console.log("Hello from E2E test");' > test-project/index.js

log_success "Test project created"
echo ""

# Step 3: Submit build via API
log_info "Step 3: Submitting build via API"

# Zip project
cd test-project
zip -r ../project.zip . > /dev/null 2>&1
cd ..

# Submit build
SUBMIT_RESPONSE=$(curl -s -X POST \
    -H "X-API-Key: $API_KEY" \
    -F "source=@project.zip" \
    -F "platform=ios" \
    "$CONTROLLER_URL/api/builds/submit")

BUILD_ID=$(echo "$SUBMIT_RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)

if [ -z "$BUILD_ID" ]; then
    log_error "Failed to submit build"
    echo "Response: $SUBMIT_RESPONSE"
    exit 1
fi

log_success "Build submitted with ID: $BUILD_ID"
echo ""

# Step 4: Start mock worker
log_info "Step 4: Starting mock worker"
cd "$ORIGINAL_DIR"
bun test/mock-worker.ts \
    --url "$CONTROLLER_URL" \
    --api-key "$API_KEY" \
    --name "E2E Test Worker" \
    --platform ios \
    --build-delay 2000 > "$ORIGINAL_DIR/$TEST_DIR/worker.log" 2>&1 &
WORKER_PID=$!
cd "$ORIGINAL_DIR/$TEST_DIR"

log_info "Mock worker started (PID: $WORKER_PID)"
sleep 2
echo ""

# Step 5: Wait for worker to pick up and complete build
log_info "Step 5: Waiting for build to complete"

if ! wait_for_build_completion "$BUILD_ID"; then
    log_error "Build did not complete successfully"
    echo ""
    log_info "Worker logs:"
    tail -n 20 "$ORIGINAL_DIR/$TEST_DIR/worker.log" 2>/dev/null || echo "No worker logs found"
    exit 1
fi

echo ""

# Step 6: Verify build status
log_info "Step 6: Verifying build status"
STATUS_RESPONSE=$(curl -s -H "X-API-Key: $API_KEY" "$CONTROLLER_URL/api/builds/$BUILD_ID/status")

status=$(echo "$STATUS_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
if [ "$status" != "completed" ]; then
    log_error "Build status is '$status', expected 'completed'"
    exit 1
fi

log_success "Build status verified: $status"
echo ""

# Step 7: Download build result
log_info "Step 7: Downloading build result"

HTTP_CODE=$(curl -s -w "%{http_code}" -o result.ipa \
    -H "X-API-Key: $API_KEY" \
    "$CONTROLLER_URL/api/builds/$BUILD_ID/download")

if [ "$HTTP_CODE" != "200" ]; then
    log_error "Download failed with HTTP code: $HTTP_CODE"
    exit 1
fi

if [ ! -f "result.ipa" ]; then
    log_error "Downloaded file not found"
    exit 1
fi

FILE_SIZE=$(stat -f%z result.ipa 2>/dev/null || stat -c%s result.ipa 2>/dev/null)
if [ "$FILE_SIZE" -lt 100 ]; then
    log_error "Downloaded file is too small (${FILE_SIZE} bytes)"
    exit 1
fi

log_success "Build downloaded successfully (${FILE_SIZE} bytes)"
echo ""

# Step 8: Verify logs
log_info "Step 8: Verifying build logs"

LOGS_RESPONSE=$(curl -s -H "X-API-Key: $API_KEY" "$CONTROLLER_URL/api/builds/$BUILD_ID/logs")

if ! echo "$LOGS_RESPONSE" | grep -q "Build submitted"; then
    log_error "Build logs missing 'Build submitted' entry"
    exit 1
fi

if ! echo "$LOGS_RESPONSE" | grep -q "completed successfully"; then
    log_error "Build logs missing 'completed successfully' entry"
    exit 1
fi

log_success "Build logs verified"
echo ""

# Step 9: Test concurrent builds
log_info "Step 9: Testing concurrent build submissions"

BUILD_IDS=()
for i in 1 2 3; do
    RESPONSE=$(curl -s -X POST \
        -H "X-API-Key: $API_KEY" \
        -F "source=@project.zip" \
        -F "platform=ios" \
        "$CONTROLLER_URL/api/builds/submit")

    BID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    if [ ! -z "$BID" ]; then
        BUILD_IDS+=("$BID")
        log_info "Submitted build $i: $BID"
    fi
done

log_success "Submitted ${#BUILD_IDS[@]} concurrent builds"
echo ""

# Step 10: Verify queue stats
log_info "Step 10: Verifying queue statistics"

HEALTH_RESPONSE=$(curl -s "$CONTROLLER_URL/health")
PENDING=$(echo "$HEALTH_RESPONSE" | grep -o '"pending":[0-9]*' | cut -d':' -f2)

if [ "$PENDING" -gt 0 ]; then
    log_success "Queue has $PENDING pending builds"
else
    log_warning "Queue has no pending builds (worker may have processed them)"
fi

echo ""

# All tests passed
log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "  All E2E Tests Passed! ✓"
log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Test artifacts available in: $TEST_DIR"
log_info "  - worker.log: Mock worker output"
log_info "  - result.ipa: Downloaded build"
echo ""

exit 0
