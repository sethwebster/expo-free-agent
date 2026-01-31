# Manual End-to-End OTP Authentication Test

Complete step-by-step commands to verify OTP authentication flow.

## Step 1: Start Controller

```bash
cd /Users/sethwebster/Development/expo/expo-free-agent/packages/controller-elixir
mix phx.server &
CONTROLLER_PID=$!
echo "Controller PID: $CONTROLLER_PID"
sleep 5
```

Verify:
```bash
curl -s http://localhost:4444/api/health | jq .
```

Expected:
```json
{
  "status": "ok",
  "queue": {
    "active": 0,
    "pending": 0
  },
  "storage": {}
}
```

## Step 2: Register Test Worker

```bash
curl -s -X POST http://localhost:4444/api/workers/register \
  -H "Content-Type: application/json" \
  -d '{"name":"test-worker","status":"idle","capabilities":{"platforms":["ios"]}}' \
  > /tmp/worker-register.json

cat /tmp/worker-register.json | jq .

# Extract values
WORKER_ID=$(jq -r '.id' /tmp/worker-register.json)
WORKER_TOKEN=$(jq -r '.access_token' /tmp/worker-register.json)

echo "WORKER_ID=$WORKER_ID"
echo "WORKER_TOKEN=$WORKER_TOKEN"
```

Expected output:
```json
{
  "id": "AbCdEf123456789",
  "message": "Worker registered successfully",
  "status": "registered",
  "access_token": "xyzABC123..."
}
```

## Step 3: Create Test Project

```bash
mkdir -p /tmp/test-expo-project
cat > /tmp/test-expo-project/app.json << 'EOF'
{
  "expo": {
    "name": "test-project",
    "slug": "test-project",
    "version": "1.0.0",
    "ios": {
      "bundleIdentifier": "com.test.project"
    }
  }
}
EOF

echo '{"dependencies":{}}' > /tmp/test-expo-project/package.json
```

## Step 4: Submit Test Build

```bash
cd /Users/sethwebster/Development/expo/expo-free-agent/packages/cli

./dist/index.js submit /tmp/test-expo-project --controller-url http://localhost:4444 \
  > /tmp/submit-output.txt 2>&1

cat /tmp/submit-output.txt

# Extract build ID
BUILD_ID=$(grep "Build ID:" /tmp/submit-output.txt | awk '{print $3}')
echo "BUILD_ID=$BUILD_ID"
```

Expected output:
```
- Preparing project for submission
✔ Project zipped (XXX B)
- Uploading to controller
✔ Build submitted successfully

Build ID: AbCdEfGhIjKlMnOp

Track status: expo-free-agent status AbCdEfGhIjKlMnOp
Download when ready: expo-free-agent download AbCdEfGhIjKlMnOp
```

## Step 5: Worker Polls and Gets Build with OTP

```bash
curl -s http://localhost:4444/api/workers/poll \
  -H "X-Worker-Token: $WORKER_TOKEN" \
  > /tmp/poll-response.json

cat /tmp/poll-response.json | jq .

# Extract OTP
OTP=$(jq -r '.job.otp' /tmp/poll-response.json)
echo "OTP=$OTP"
```

Expected output:
```json
{
  "access_token": "xyzABC123...",
  "job": {
    "id": "AbCdEfGhIjKlMnOp",
    "otp": "abcdef1234567890ABCDEF",
    "source_url": "/api/builds/AbCdEfGhIjKlMnOp/source",
    "platform": "ios",
    "submitted_at": "2026-01-31T14:00:00Z",
    "certs_url": null
  }
}
```

Verify OTP in database:
```bash
cd /Users/sethwebster/Development/expo/expo-free-agent/packages/controller-elixir

psql -d expo_controller_dev -U expo << EOF
SELECT
  id,
  status,
  otp,
  otp_expires_at > NOW() as otp_valid,
  vm_token IS NULL as vm_token_null
FROM builds
WHERE id = '$BUILD_ID';
EOF
```

Expected:
```
 id               | status   | otp                      | otp_valid | vm_token_null
------------------+----------+--------------------------+-----------+---------------
 AbCdEfGhIjKlMnOp | assigned | abcdef1234567890ABCDEF   | t         | t
```

## Step 6: Create VM Configuration File

```bash
mkdir -p /tmp/vm-test-config

cat > /tmp/vm-test-config/build-config.json << EOF
{
  "buildId": "$BUILD_ID",
  "controllerUrl": "http://192.168.64.1:4444",
  "otp": "$OTP"
}
EOF

echo "=== Config file created ==="
cat /tmp/vm-test-config/build-config.json | jq .
```

Expected:
```json
{
  "buildId": "AbCdEfGhIjKlMnOp",
  "controllerUrl": "http://192.168.64.1:4444",
  "otp": "abcdef1234567890ABCDEF"
}
```

## Step 7: Start VM with Mounted Config

```bash
cd /Users/sethwebster/Development/expo/expo-free-agent/vm-setup

# Clone latest image
/opt/homebrew/bin/tart clone ghcr.io/sethwebster/expo-free-agent-base:0.1.26 test-e2e-vm

# Start VM with config mounted
/opt/homebrew/bin/tart run test-e2e-vm --no-graphics --dir "/tmp/vm-test-config:ro" &
VM_PID=$!
echo "VM started with PID: $VM_PID"

# Wait for VM to boot
echo "Waiting for VM to boot..."
sleep 15

# Get VM IP
VM_IP=$(/opt/homebrew/bin/tart ip test-e2e-vm)
echo "VM IP: $VM_IP"
```

Expected:
```
VM started with PID: 12345
Waiting for VM to boot...
VM IP: 192.168.64.41
```

## Step 8: Verify Config File Mounted in VM

```bash
echo "=== Checking mounted config ==="
/opt/homebrew/bin/tart exec test-e2e-vm ls -la '/Volumes/My Shared Files/'

echo ""
echo "=== Config file contents ==="
/opt/homebrew/bin/tart exec test-e2e-vm cat '/Volumes/My Shared Files/build-config.json'
```

Expected:
```
total 2
drwxr-xr-x@ 3 admin  staff   96 Jan 31 14:00 .
drwxr-xr-x  4 root   wheel  128 Jan 31 14:00 ..
-rw-r--r--@ 1 admin  staff  133 Jan 31 14:00 build-config.json

{
  "buildId": "AbCdEfGhIjKlMnOp",
  "controllerUrl": "http://192.168.64.1:4444",
  "otp": "abcdef1234567890ABCDEF"
}
```

## Step 9: Test Controller Accessibility from VM

```bash
echo "=== Testing controller health from VM ==="
/opt/homebrew/bin/tart exec test-e2e-vm curl -s --max-time 5 http://192.168.64.1:4444/api/health | jq .
```

Expected:
```json
{
  "status": "ok",
  "queue": {
    "active": 1,
    "pending": 0
  },
  "storage": {}
}
```

## Step 10: Test OTP Authentication from VM

Create test script:
```bash
cat > /tmp/test-otp-auth.sh << 'TESTSCRIPT'
#!/bin/bash
CONFIG_FILE="/Volumes/My Shared Files/build-config.json"

echo "=== OTP Authentication Test ==="

# Parse config
BUILD_ID=$(jq -r '.buildId' "$CONFIG_FILE")
CONTROLLER_URL=$(jq -r '.controllerUrl' "$CONFIG_FILE")
OTP=$(jq -r '.otp' "$CONFIG_FILE")

echo "Build ID: $BUILD_ID"
echo "Controller: $CONTROLLER_URL"
echo "OTP: ${OTP:0:10}..."

# Authenticate
AUTH_URL="${CONTROLLER_URL}/api/builds/${BUILD_ID}/authenticate"
echo "Auth URL: $AUTH_URL"

HTTP_CODE=$(curl -w "%{http_code}" -o /tmp/auth-response.json \
  -X POST \
  -H "Content-Type: application/json" \
  -d "{\"otp\":\"$OTP\"}" \
  --silent \
  --max-time 30 \
  "$AUTH_URL" 2>&1 | tail -n 1)

echo "HTTP Status: $HTTP_CODE"

if [[ "$HTTP_CODE" == "200" ]]; then
    echo "✓ Authentication succeeded!"
    echo "Response:"
    cat /tmp/auth-response.json | jq .
    VM_TOKEN=$(jq -r '.vm_token' /tmp/auth-response.json)
    echo ""
    echo "VM Token: ${VM_TOKEN:0:20}..."
    rm /tmp/auth-response.json
    exit 0
else
    echo "✗ Authentication failed"
    echo "Response:"
    cat /tmp/auth-response.json 2>/dev/null
    rm /tmp/auth-response.json 2>/dev/null
    exit 1
fi
TESTSCRIPT

chmod +x /tmp/test-otp-auth.sh

# Copy to VM and run
ENCODED=$(base64 < /tmp/test-otp-auth.sh)
/opt/homebrew/bin/tart exec test-e2e-vm bash -c "echo '$ENCODED' | base64 --decode > /tmp/test-otp-auth.sh && chmod +x /tmp/test-otp-auth.sh && bash /tmp/test-otp-auth.sh"
```

Expected output:
```
=== OTP Authentication Test ===
Build ID: AbCdEfGhIjKlMnOp
Controller: http://192.168.64.1:4444
OTP: abcdef1234...
Auth URL: http://192.168.64.1:4444/api/builds/AbCdEfGhIjKlMnOp/authenticate
HTTP Status: 200
✓ Authentication succeeded!
Response:
{
  "vm_token": "xyzVMtoken123456...",
  "vm_token_expires_at": "2026-01-31T16:00:00Z"
}

VM Token: xyzVMtoken123456...
```

## Step 11: Verify VM Token in Database

```bash
cd /Users/sethwebster/Development/expo/expo-free-agent/packages/controller-elixir

psql -d expo_controller_dev -U expo << EOF
SELECT
  id,
  vm_token IS NOT NULL as has_vm_token,
  vm_token_expires_at,
  vm_token_expires_at > NOW() as token_valid,
  EXTRACT(EPOCH FROM (vm_token_expires_at - NOW()))/3600 as hours_until_expiry
FROM builds
WHERE id = '$BUILD_ID';
EOF
```

Expected:
```
 id               | has_vm_token | vm_token_expires_at      | token_valid | hours_until_expiry
------------------+--------------+--------------------------+-------------+--------------------
 AbCdEfGhIjKlMnOp | t            | 2026-01-31 16:00:00+00   | t           | 1.99...
```

## Step 12: Extract VM Token and Test Source Download

```bash
cd /Users/sethwebster/Development/expo/expo-free-agent/packages/controller-elixir

VM_TOKEN=$(psql -d expo_controller_dev -U expo -t -c "SELECT vm_token FROM builds WHERE id = '$BUILD_ID';" | xargs)
echo "VM_TOKEN=$VM_TOKEN"
echo "VM Token (first 20 chars): ${VM_TOKEN:0:20}..."
```

Test source download:
```bash
echo "=== Testing source download with VM token ==="
curl -v http://192.168.64.1:4444/api/builds/$BUILD_ID/source \
  -H "X-VM-Token: $VM_TOKEN" \
  -o /tmp/test-source.zip 2>&1 | grep -E "< HTTP|< content-type|< content-length"

echo ""
echo "=== Verifying downloaded file ==="
ls -lh /tmp/test-source.zip
unzip -t /tmp/test-source.zip
rm /tmp/test-source.zip
```

Expected:
```
< HTTP/1.1 200 OK
< content-type: application/zip
< content-length: 373

-rw-r--r--  1 user  staff   373B Jan 31 14:05 /tmp/test-source.zip
Archive:  /tmp/test-source.zip
    testing: app.json                 OK
    testing: package.json             OK
No errors detected in compressed data of /tmp/test-source.zip.
```

## Step 13: Test Certificate Download (Expected 404)

```bash
echo "=== Testing certificate download (no certs uploaded) ==="
curl -v http://192.168.64.1:4444/api/builds/$BUILD_ID/certs \
  -H "X-VM-Token: $VM_TOKEN" \
  2>&1 | grep -E "< HTTP|error"
```

Expected:
```
< HTTP/1.1 404 Not Found
{"error":"No certificates found for this build"}
```

## Step 14: Test Build Token for Status

```bash
cd /Users/sethwebster/Development/expo/expo-free-agent/packages/controller-elixir

BUILD_TOKEN=$(psql -d expo_controller_dev -U expo -t -c "SELECT access_token FROM builds WHERE id = '$BUILD_ID';" | xargs)
echo "BUILD_TOKEN=$BUILD_TOKEN"
```

Test status endpoint:
```bash
cd /Users/sethwebster/Development/expo/expo-free-agent/packages/cli

./dist/index.js status $BUILD_ID
```

Expected:
```
Build ID: AbCdEfGhIjKlMnOp
Status: assigned
Platform: ios
Submitted: 2026-01-31T14:00:00Z
```

Or test directly:
```bash
curl -s http://localhost:4444/api/builds/$BUILD_ID \
  -H "X-Build-Token: $BUILD_TOKEN" \
  | jq '{id: .id, status: .status, platform: .platform}'
```

## Step 15: Test Authentication Boundaries

### Test 1: Worker token CANNOT access VM endpoints
```bash
echo "=== Test: Worker token on VM endpoint (should fail) ==="
curl -s http://localhost:4444/api/builds/$BUILD_ID/source \
  -H "X-Worker-Token: $WORKER_TOKEN" \
  | jq .
```

Expected:
```json
{
  "error": "Authentication required. Provide X-VM-Token header"
}
```

### Test 2: Build token CANNOT access VM endpoints
```bash
echo "=== Test: Build token on VM endpoint (should fail) ==="
curl -s http://localhost:4444/api/builds/$BUILD_ID/source \
  -H "X-Build-Token: $BUILD_TOKEN" \
  | jq .
```

Expected:
```json
{
  "error": "Authentication required. Provide X-VM-Token header"
}
```

### Test 3: VM token CANNOT access build status
```bash
echo "=== Test: VM token on build endpoint (should fail) ==="
curl -s http://localhost:4444/api/builds/$BUILD_ID \
  -H "X-VM-Token: $VM_TOKEN" \
  | jq .
```

Expected:
```json
{
  "error": "Authentication required. Provide X-Build-Token header"
}
```

### Test 4: No token fails everywhere
```bash
echo "=== Test: No token (should fail) ==="
curl -s http://localhost:4444/api/builds/$BUILD_ID | jq .
```

Expected:
```json
{
  "error": "Authentication required. Provide X-Build-Token header"
}
```

## Step 16: Test OTP Expiry

```bash
echo "=== Expiring OTP in database ==="
cd /Users/sethwebster/Development/expo/expo-free-agent/packages/controller-elixir

psql -d expo_controller_dev -U expo << EOF
UPDATE builds
SET otp_expires_at = NOW() - INTERVAL '1 minute'
WHERE id = '$BUILD_ID';

SELECT id, otp, otp_expires_at, otp_expires_at < NOW() as expired
FROM builds
WHERE id = '$BUILD_ID';
EOF
```

Test with expired OTP:
```bash
echo "=== Testing with expired OTP ==="
curl -s -X POST http://192.168.64.1:4444/api/builds/$BUILD_ID/authenticate \
  -H "Content-Type: application/json" \
  -d "{\"otp\":\"$OTP\"}" \
  | jq .
```

Expected:
```json
{
  "error": "OTP expired"
}
```

## Step 17: Test Invalid OTP

```bash
echo "=== Testing with invalid OTP ==="
curl -s -X POST http://192.168.64.1:4444/api/builds/$BUILD_ID/authenticate \
  -H "Content-Type: application/json" \
  -d '{"otp":"invalid-otp-123456789"}' \
  | jq .
```

Expected:
```json
{
  "error": "Invalid OTP"
}
```

## Step 18: Cleanup

```bash
echo "=== Cleaning up ==="

# Stop and delete test VM
/opt/homebrew/bin/tart stop test-e2e-vm
/opt/homebrew/bin/tart delete test-e2e-vm

# Clean up config
rm -rf /tmp/vm-test-config
rm -f /tmp/test-otp-auth.sh
rm -f /tmp/worker-register.json
rm -f /tmp/poll-response.json
rm -f /tmp/submit-output.txt

# Unregister worker
curl -s -X POST http://localhost:4444/api/workers/$WORKER_ID/unregister \
  -H "X-Worker-Token: $WORKER_TOKEN" \
  | jq .

# Stop controller (optional)
# kill $CONTROLLER_PID

echo "✓ Cleanup complete"
```

---

## Quick Test Script

Save this as `test-e2e.sh` for rapid testing:

```bash
#!/bin/bash
set -e

export BUILD_ID WORKER_ID WORKER_TOKEN OTP VM_TOKEN BUILD_TOKEN

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }
info() { echo -e "${YELLOW}→ $1${NC}"; }

info "Step 1: Register worker"
WORKER_RESPONSE=$(curl -s -X POST http://localhost:4444/api/workers/register \
  -H "Content-Type: application/json" \
  -d '{"name":"test-worker","status":"idle","capabilities":{"platforms":["ios"]}}')
WORKER_ID=$(echo $WORKER_RESPONSE | jq -r '.id')
WORKER_TOKEN=$(echo $WORKER_RESPONSE | jq -r '.access_token')
[[ -n "$WORKER_ID" ]] && pass "Worker registered: $WORKER_ID" || fail "Worker registration failed"

info "Step 2: Submit build"
cd /Users/sethwebster/Development/expo/expo-free-agent/packages/cli
BUILD_OUTPUT=$(./dist/index.js submit /tmp/test-expo-project --controller-url http://localhost:4444 2>&1)
BUILD_ID=$(echo "$BUILD_OUTPUT" | grep "Build ID:" | awk '{print $3}')
[[ -n "$BUILD_ID" ]] && pass "Build submitted: $BUILD_ID" || fail "Build submission failed"

info "Step 3: Worker poll"
POLL_RESPONSE=$(curl -s http://localhost:4444/api/workers/poll -H "X-Worker-Token: $WORKER_TOKEN")
OTP=$(echo $POLL_RESPONSE | jq -r '.job.otp')
[[ -n "$OTP" && "$OTP" != "null" ]] && pass "OTP received: ${OTP:0:10}..." || fail "OTP not generated"

info "Step 4: Create VM config"
mkdir -p /tmp/vm-test-config
cat > /tmp/vm-test-config/build-config.json << EOF
{"buildId":"$BUILD_ID","controllerUrl":"http://192.168.64.1:4444","otp":"$OTP"}
EOF
pass "Config created"

info "Step 5: Test OTP auth"
AUTH_RESPONSE=$(curl -s -X POST http://192.168.64.1:4444/api/builds/$BUILD_ID/authenticate \
  -H "Content-Type: application/json" -d "{\"otp\":\"$OTP\"}")
VM_TOKEN=$(echo $AUTH_RESPONSE | jq -r '.vm_token')
[[ -n "$VM_TOKEN" && "$VM_TOKEN" != "null" ]] && pass "VM token issued: ${VM_TOKEN:0:20}..." || fail "OTP auth failed"

info "Step 6: Test VM token for source download"
HTTP_CODE=$(curl -s -w "%{http_code}" -o /tmp/test-source.zip \
  http://192.168.64.1:4444/api/builds/$BUILD_ID/source \
  -H "X-VM-Token: $VM_TOKEN")
[[ "$HTTP_CODE" == "200" ]] && pass "Source downloaded successfully" || fail "Source download failed (HTTP $HTTP_CODE)"
rm -f /tmp/test-source.zip

info "Step 7: Test token scoping"
FAIL_RESPONSE=$(curl -s http://localhost:4444/api/builds/$BUILD_ID/source \
  -H "X-Worker-Token: $WORKER_TOKEN")
[[ "$(echo $FAIL_RESPONSE | jq -r '.error')" =~ "Authentication required" ]] && \
  pass "Worker token correctly rejected for VM endpoint" || \
  fail "Worker token incorrectly accepted for VM endpoint"

info "Cleanup"
rm -rf /tmp/vm-test-config
curl -s -X POST http://localhost:4444/api/workers/$WORKER_ID/unregister \
  -H "X-Worker-Token: $WORKER_TOKEN" > /dev/null
pass "Cleanup complete"

echo ""
echo -e "${GREEN}=== ALL TESTS PASSED ===${NC}"
```

Make executable and run:
```bash
chmod +x test-e2e.sh
./test-e2e.sh
```
