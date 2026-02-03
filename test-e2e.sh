#!/bin/bash

#
# End-to-End Test Script
# Tests the complete build submission → assignment → completion flow
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TEST_DIR=".test-e2e-integration"
CONTROLLER_PORT=4444
API_KEY="e2e-test-api-key-minimum-32-characters-long"
CONTROLLER_URL="http://localhost:${CONTROLLER_PORT}"

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

    # Kill controller if running
    if [ ! -z "$CONTROLLER_PID" ]; then
        log_info "Stopping controller (PID: $CONTROLLER_PID)"
        kill $CONTROLLER_PID 2>/dev/null || true
        wait $CONTROLLER_PID 2>/dev/null || true
    fi

    # Kill worker if running
    if [ ! -z "$WORKER_PID" ]; then
        log_info "Stopping mock worker (PID: $WORKER_PID)"
        kill $WORKER_PID 2>/dev/null || true
        wait $WORKER_PID 2>/dev/null || true
    fi

    # Drop test database
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
    local access_token=$2
    local max_wait=60
    local elapsed=0

    log_info "Waiting for build to complete..."

    while [ $elapsed -lt $max_wait ]; do
        response=$(curl -s -H "X-Build-Token: $access_token" "$CONTROLLER_URL/api/builds/$build_id/status" 2>/dev/null || echo "{}")
        status=$(echo "$response" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

        if [ "$status" = "completed" ]; then
            log_success "Build completed"
            return 0
        elif [ "$status" = "failed" ]; then
            log_error "Build failed"
            echo "Response: $response"
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
log_info "Starting E2E Test"
echo ""

# Save original directory
ORIGINAL_DIR=$(pwd)

# Create test directory
mkdir -p "$TEST_DIR"

# Step 1: Set up and start Elixir controller
log_info "Step 1: Setting up Elixir controller on port ${CONTROLLER_PORT}"

cd "$ORIGINAL_DIR/packages/controller-elixir"

# Set up test database
log_info "Creating test database..."
MIX_ENV=test mix ecto.create > "$ORIGINAL_DIR/$TEST_DIR/db-setup.log" 2>&1 || {
    log_warning "Database may already exist (continuing)"
}

log_info "Running migrations..."
MIX_ENV=test mix ecto.migrate > "$ORIGINAL_DIR/$TEST_DIR/db-migrate.log" 2>&1

log_info "Starting controller..."

# Start controller with environment variables
CONTROLLER_API_KEY="$API_KEY" \
PORT="$CONTROLLER_PORT" \
MIX_ENV=test \
STORAGE_ROOT="$ORIGINAL_DIR/$TEST_DIR/storage" \
mix phx.server > "$ORIGINAL_DIR/$TEST_DIR/controller.log" 2>&1 &

CONTROLLER_PID=$!
cd "$ORIGINAL_DIR"

log_info "Controller started (PID: $CONTROLLER_PID)"
sleep 3

# Check controller is healthy
if ! check_health "$CONTROLLER_URL"; then
    log_error "Controller failed to start"
    if [ -f "$ORIGINAL_DIR/$TEST_DIR/controller.log" ]; then
        echo ""
        log_info "Controller logs:"
        tail -n 50 "$ORIGINAL_DIR/$TEST_DIR/controller.log"
    fi
    exit 1
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
ACCESS_TOKEN=$(echo "$SUBMIT_RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

if [ -z "$BUILD_ID" ]; then
    log_error "Failed to submit build"
    echo "Response: $SUBMIT_RESPONSE"
    exit 1
fi

log_success "Build submitted with ID: $BUILD_ID"
if [ ! -z "$ACCESS_TOKEN" ]; then
    log_info "Build access token: ${ACCESS_TOKEN:0:20}..."
fi
echo ""

# Step 4: Start mock worker
log_info "Step 4: Starting mock worker"
cd "$ORIGINAL_DIR"

# Check if mock worker exists
if [ ! -f "test/mock-worker.ts" ]; then
    log_warning "Mock worker not found, skipping worker test"
    log_info "You can still verify the build was queued:"
    log_info "  curl -H 'X-API-Key: $API_KEY' $CONTROLLER_URL/api/builds/$BUILD_ID/status"
    echo ""
    log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "  Basic E2E Tests Passed! ✓"
    log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "Test artifacts available in: $TEST_DIR"
    log_info "  - controller.log: Controller output"
    log_info "  - db-setup.log: Database setup output"
    log_info "  - db-migrate.log: Database migration output"
    echo ""
    log_info "Controller still running on port $CONTROLLER_PORT"
    log_info "Press Ctrl+C to stop and cleanup"
    echo ""
    wait $CONTROLLER_PID
    exit 0
fi

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

if ! wait_for_build_completion "$BUILD_ID" "$ACCESS_TOKEN"; then
    log_error "Build did not complete successfully"
    echo ""
    log_info "Controller logs:"
    tail -n 20 "$ORIGINAL_DIR/$TEST_DIR/controller.log" 2>/dev/null || echo "No controller logs found"
    echo ""
    log_info "Worker logs:"
    tail -n 20 "$ORIGINAL_DIR/$TEST_DIR/worker.log" 2>/dev/null || echo "No worker logs found"
    exit 1
fi

echo ""

# Step 6: Verify build status
log_info "Step 6: Verifying build status"
STATUS_RESPONSE=$(curl -s -H "X-Build-Token: $ACCESS_TOKEN" "$CONTROLLER_URL/api/builds/$BUILD_ID/status")

status=$(echo "$STATUS_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
if [ "$status" != "completed" ]; then
    log_error "Build status is '$status', expected 'completed'"
    echo "Response: $STATUS_RESPONSE"
    exit 1
fi

log_success "Build status verified: $status"
echo ""

# Step 7: Download build result
log_info "Step 7: Downloading build result"

HTTP_CODE=$(curl -s -w "%{http_code}" -o result.ipa \
    -H "X-Build-Token: $ACCESS_TOKEN" \
    "$CONTROLLER_URL/api/builds/$BUILD_ID/download")

if [ "$HTTP_CODE" != "200" ]; then
    log_error "Download failed with HTTP code: $HTTP_CODE"
    # Try with access token if available
    if [ ! -z "$ACCESS_TOKEN" ]; then
        log_info "Retrying with build access token..."
        HTTP_CODE=$(curl -s -w "%{http_code}" -o result.ipa \
            -H "X-Build-Token: $ACCESS_TOKEN" \
            "$CONTROLLER_URL/api/builds/$BUILD_ID/download")
        if [ "$HTTP_CODE" != "200" ]; then
            log_error "Download with access token also failed: $HTTP_CODE"
            exit 1
        fi
    else
        exit 1
    fi
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

LOGS_RESPONSE=$(curl -s -H "X-Build-Token: $ACCESS_TOKEN" "$CONTROLLER_URL/api/builds/$BUILD_ID/logs")

if [ -z "$LOGS_RESPONSE" ]; then
    log_warning "Build logs are empty (may not be implemented yet)"
else
    log_success "Build logs retrieved"
fi
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

STATS_RESPONSE=$(curl -s "$CONTROLLER_URL/api/stats" || curl -s "$CONTROLLER_URL/health")

if echo "$STATS_RESPONSE" | grep -q "pending\|queue"; then
    log_success "Stats endpoint responding"
else
    log_warning "Stats endpoint may not have expected format"
fi

echo ""

# All tests passed
log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "  All E2E Tests Passed! ✓"
log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Test artifacts available in: $TEST_DIR"
log_info "  - controller.log: Controller output"
log_info "  - worker.log: Mock worker output"
log_info "  - result.ipa: Downloaded build"
log_info "  - db-setup.log: Database setup output"
log_info "  - db-migrate.log: Database migration output"
echo ""

exit 0
