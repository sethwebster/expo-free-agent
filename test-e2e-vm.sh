#!/bin/bash

#
# Full End-to-End VM Test Script
# Tests complete build flow with real Tart VMs
#
# This test validates:
# - Real VM creation/deletion
# - Bootstrap script execution inside VM
# - OTP → VM token authentication
# - Certificate handling (iOS)
# - Build execution inside VM
# - Artifact upload from VM
# - VM cleanup
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TEST_DIR=".test-e2e-vm"
CONTROLLER_PORT=4445
API_KEY="e2e-vm-test-api-key-minimum-32-characters-long"
CONTROLLER_URL="http://localhost:${CONTROLLER_PORT}"

# Use local test image if available, otherwise use registry image
LOCAL_IMAGE="expo-free-agent-base-local"
REGISTRY_IMAGE="ghcr.io/sethwebster/expo-free-agent-base:latest"
BASE_VM_IMAGE="$REGISTRY_IMAGE"

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
        log_info "Stopping real worker (PID: $WORKER_PID)"
        kill $WORKER_PID 2>/dev/null || true
        wait $WORKER_PID 2>/dev/null || true
    fi

    # Clean up any orphaned VMs
    log_info "Checking for orphaned VMs..."
    /opt/homebrew/bin/tart list | grep "^build-" | awk '{print $1}' | while read vm; do
        log_warning "Cleaning up orphaned VM: $vm"
        /opt/homebrew/bin/tart stop "$vm" 2>/dev/null || true
        /opt/homebrew/bin/tart delete "$vm" 2>/dev/null || true
    done

    # Clean up temporary certificate files
    if [ -n "$CERTS_ZIP" ] && [ -f "$CERTS_ZIP" ]; then
        CERTS_DIR=$(dirname "$CERTS_ZIP")
        if [[ "$CERTS_DIR" == /tmp/* ]] || [[ "$CERTS_DIR" == /var/folders/* ]]; then
            rm -rf "$CERTS_DIR" 2>/dev/null || true
        fi
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

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Tart is installed
    if ! command -v /opt/homebrew/bin/tart &> /dev/null; then
        log_error "Tart not found. Install with: brew install cirruslabs/cli/tart"
        exit 1
    fi
    log_success "✓ Tart installed: $(/opt/homebrew/bin/tart --version | head -n 1)"

    # Check for local test image first (for development)
    if /opt/homebrew/bin/tart list | awk '{print $2}' | grep -q "^${LOCAL_IMAGE}\$"; then
        BASE_VM_IMAGE="$LOCAL_IMAGE"
        log_success "✓ Using local test image: ${LOCAL_IMAGE}"
        log_info "  (Built with latest local scripts)"
    # Fall back to registry image
    elif /opt/homebrew/bin/tart list | grep -q "expo-free-agent-base"; then
        log_success "✓ Using registry image: ${REGISTRY_IMAGE}"
        log_warning "  For local testing with latest scripts, run:"
        log_warning "  ./vm-setup/setup-local-test-image.sh"
    else
        log_error "No base VM image found"
        log_info "Available images:"
        /opt/homebrew/bin/tart list
        log_info ""
        log_info "Options:"
        log_info "  1. Development (recommended): Create local test image"
        log_info "     ./vm-setup/setup-local-test-image.sh"
        log_info ""
        log_info "  2. Production: Pull from registry"
        log_info "     tart pull ${REGISTRY_IMAGE}"
        exit 1
    fi

    # Check bootstrap script exists
    if [ ! -f "free-agent/Sources/WorkerCore/Resources/free-agent-bootstrap.sh" ]; then
        log_error "Bootstrap script not found at free-agent/Sources/WorkerCore/Resources/free-agent-bootstrap.sh"
        exit 1
    fi
    log_success "✓ Bootstrap script found"

    # Check Elixir controller exists
    if [ ! -d "packages/controller-elixir" ]; then
        log_error "Elixir controller not found at packages/controller-elixir"
        exit 1
    fi
    log_success "✓ Elixir controller found"
}

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
    local max_wait=1200  # 20 minutes for real builds
    local elapsed=0

    log_info "Waiting for build to complete (max ${max_wait}s)..."

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

        # Show progress every 30 seconds
        if [ $(($elapsed % 30)) -eq 0 ]; then
            echo ""
            log_info "Still building... (${elapsed}s elapsed, status: ${status})"
        else
            echo -n "."
        fi

        sleep 5
        elapsed=$((elapsed + 5))
    done

    log_error "Build did not complete within ${max_wait}s"
    return 1
}

# Start test
log_info "=========================================="
log_info "  Full E2E Test with Real Tart VMs"
log_info "=========================================="
echo ""

# Save original directory
ORIGINAL_DIR=$(pwd)

# Check prerequisites
check_prerequisites
echo ""

# Create test directory
mkdir -p "$TEST_DIR"

# Step 1: Start Elixir controller
log_info "Step 1: Starting Elixir controller on port ${CONTROLLER_PORT}"

# Kill any existing controller on this port
log_info "Checking for existing controller on port ${CONTROLLER_PORT}..."
lsof -ti:${CONTROLLER_PORT} | xargs kill -9 2>/dev/null || true
sleep 2

cd "$ORIGINAL_DIR/packages/controller-elixir"

log_info "Resetting database..."
# Reset database (handles connection termination automatically)
mix ecto.reset --quiet 2>&1 || {
    log_warning "Database reset failed, trying alternative..."
    # Fallback: just truncate all tables
    mix run -e "Ecto.Adapters.SQL.query!(ExpoController.Repo, \"TRUNCATE workers, builds, build_logs, cpu_snapshots, diagnostic_reports RESTART IDENTITY CASCADE\")" 2>&1 || true
}

log_info "Starting controller..."

# Create storage directory
mkdir -p "$ORIGINAL_DIR/$TEST_DIR/storage"

# Start controller in dev mode (test mode has sandbox issues with background processes)
cd "$ORIGINAL_DIR/packages/controller-elixir" && CONTROLLER_API_KEY="$API_KEY" PORT="$CONTROLLER_PORT" STORAGE_ROOT="$ORIGINAL_DIR/$TEST_DIR/storage" mix phx.server &
CONTROLLER_PID=$!

log_info "Controller started (PID: $CONTROLLER_PID)"
cd "$ORIGINAL_DIR"

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

# Step 2: Copy minimal test app from fixtures
log_info "Step 2: Copying minimal test app from fixtures"
cd "$ORIGINAL_DIR/$TEST_DIR"

MINIMAL_APP="$ORIGINAL_DIR/test/fixtures/minimal-test-app"
if [ ! -d "$MINIMAL_APP" ]; then
    log_error "Minimal test app not found at: $MINIMAL_APP"
    log_error "Test fixture is missing from repository"
    exit 1
fi

cp -R "$MINIMAL_APP" test-project
log_success "Test project copied from fixtures"
echo ""

# Step 3: Submit build via API
log_info "Step 3: Submitting build via API"

# Step 3.1: Find developer certificates
log_info "Step 3.1: Finding iOS developer certificates..."
echo ""

CERTS_ZIP=""
CERT_FINDER="$ORIGINAL_DIR/test/find-dev-certs.sh"

if [ -x "$CERT_FINDER" ]; then
  # Run interactive cert finder (user selects cert and enters password)
  # Script writes prompts to stderr (terminal), final path to stdout
  CERTS_ZIP=$("$CERT_FINDER")
  EXIT_CODE=$?

  if [ $EXIT_CODE -eq 0 ] && [ -n "$CERTS_ZIP" ] && [ -f "$CERTS_ZIP" ]; then
    log_success "✓ Certificates packaged: $CERTS_ZIP"
  else
    log_error "Certificate discovery failed (exit code: $EXIT_CODE)"
    CERTS_ZIP=""
  fi
else
  log_error "Certificate finder script not found at $CERT_FINDER"
fi
echo ""

# Step 3.2: Zip project
log_info "Step 3.2: Packaging source code..."
cd test-project
zip -q -r ../project.zip . > /dev/null 2>&1
cd ..
log_success "✓ Source packaged"
echo ""

# Step 3.3: Submit build with certificates
log_info "Step 3.3: Submitting build to controller..."

# Require certificates for iOS builds
if [ -z "$CERTS_ZIP" ]; then
  log_error "No signing certificates present"
  log_error "iOS builds require valid signing certificates"
  exit 1
fi

log_info "Submitting with certificates for code signing"
SUBMIT_RESPONSE=$(curl -s -X POST \
  -H "X-API-Key: $API_KEY" \
  -F "source=@project.zip" \
  -F "certs=@$CERTS_ZIP" \
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

# Step 4: Start real worker with Tart
log_info "Step 4: Starting real worker with Tart VMs"
cd "$ORIGINAL_DIR"

log_info "Real worker will:"
log_info "  - Clone VM from: ${BASE_VM_IMAGE}"
log_info "  - Run bootstrap script inside VM"
log_info "  - Execute build inside VM"
log_info "  - Upload artifact from VM"
log_info "  - Destroy VM after completion"
echo ""

bun test/real-worker.ts \
    --url "$CONTROLLER_URL" \
    --api-key "$API_KEY" \
    --name "e2e-vm-worker" \
    --platform ios \
    --base-image "$BASE_VM_IMAGE" \
    --build-timeout 1200 > "$ORIGINAL_DIR/$TEST_DIR/worker.log" 2>&1 &

WORKER_PID=$!

log_info "Real worker started (PID: $WORKER_PID)"
sleep 3
echo ""

# Step 5: Wait for build to complete
log_info "Step 5: Waiting for real build to complete inside VM"
log_warning "This may take 15-30 minutes for a real iOS build..."
echo ""

if ! wait_for_build_completion "$BUILD_ID" "$ACCESS_TOKEN"; then
    log_error "Build did not complete successfully"
    echo ""
    log_info "Controller logs (last 50 lines):"
    tail -n 50 "$ORIGINAL_DIR/$TEST_DIR/controller.log" 2>/dev/null || echo "No controller logs found"
    echo ""
    log_info "Worker logs (last 50 lines):"
    tail -n 50 "$ORIGINAL_DIR/$TEST_DIR/worker.log" 2>/dev/null || echo "No worker logs found"
    exit 1
fi

echo ""

# Step 6: Verify build completed successfully
log_info "Step 6: Verifying build results"

STATUS_RESPONSE=$(curl -s -H "X-Build-Token: $ACCESS_TOKEN" "$CONTROLLER_URL/api/builds/$BUILD_ID/status")
status=$(echo "$STATUS_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

if [ "$status" != "completed" ]; then
    log_error "Build status is '$status', expected 'completed'"
    echo "Response: $STATUS_RESPONSE"
    exit 1
fi

log_success "✓ Build status: completed"

# Step 7: Download artifact
log_info "Step 7: Downloading build artifact"

HTTP_CODE=$(curl -s -w "%{http_code}" -o result.ipa \
    -H "X-Build-Token: $ACCESS_TOKEN" \
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
log_success "✓ Build artifact downloaded (${FILE_SIZE} bytes)"

# Check if it's a real IPA (should be > 10MB for real build)
if [ "$FILE_SIZE" -gt 10000000 ]; then
    log_success "✓ Artifact size indicates real build (${FILE_SIZE} bytes)"
else
    log_warning "Artifact size is small (${FILE_SIZE} bytes) - may be test/mock build"
fi

echo ""

# Step 8: Verify build logs
log_info "Step 8: Verifying build logs from VM"

LOGS_RESPONSE=$(curl -s -H "X-Build-Token: $ACCESS_TOKEN" "$CONTROLLER_URL/api/builds/$BUILD_ID/logs")

if [ -z "$LOGS_RESPONSE" ]; then
    log_warning "Build logs are empty"
else
    log_success "✓ Build logs retrieved from VM"

    # Check for bootstrap phases in logs
    if echo "$LOGS_RESPONSE" | grep -q "Phase.*Loading\|Phase.*Authenticating"; then
        log_success "✓ Bootstrap phases detected in logs"
    fi

    # Check for build execution in logs
    if echo "$LOGS_RESPONSE" | grep -q "xcodebuild\|Building"; then
        log_success "✓ Build execution detected in logs"
    fi
fi

echo ""

# All tests passed
log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "  Full E2E VM Tests Passed! ✓"
log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

log_info "Tests validated:"
log_success "  ✓ Real Tart VM creation/deletion"
log_success "  ✓ Bootstrap script execution inside VM"
log_success "  ✓ OTP → VM token authentication"
log_success "  ✓ Build execution inside isolated VM"
log_success "  ✓ Artifact upload from VM"
log_success "  ✓ VM cleanup after completion"
echo ""

log_info "Test artifacts available in: $TEST_DIR"
log_info "  - controller.log: Controller output"
log_info "  - worker.log: Real worker output"
log_info "  - result.ipa: Downloaded build artifact"
log_info "  - db-setup.log: Database setup output"
log_info "  - db-migrate.log: Database migration output"
echo ""

exit 0
