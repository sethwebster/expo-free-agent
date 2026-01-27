#!/bin/bash
# Test script for controller API endpoints

BASE_URL="http://localhost:3000"

echo "Testing Expo Free Agent Controller API"
echo "========================================"
echo ""

# Health check
echo "1. Health Check"
curl -s "$BASE_URL/health" | jq '.'
echo ""

# Register worker
echo "2. Register Worker"
WORKER_RESPONSE=$(curl -s -X POST "$BASE_URL/api/workers/register" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "test-mac-1",
    "capabilities": {
      "platforms": ["ios"],
      "xcode_version": "15.0",
      "macos_version": "14.0"
    }
  }')
echo "$WORKER_RESPONSE" | jq '.'
WORKER_ID=$(echo "$WORKER_RESPONSE" | jq -r '.id')
echo "Worker ID: $WORKER_ID"
echo ""

# Create test build files
echo "3. Creating Test Build Files"
mkdir -p /tmp/test-build
echo "console.log('test');" > /tmp/test-build/index.js
cd /tmp/test-build && zip -q -r /tmp/test-source.zip . && cd -
echo "Created test-source.zip"
echo ""

# Submit build
echo "4. Submit Build"
BUILD_RESPONSE=$(curl -s -X POST "$BASE_URL/api/builds/submit" \
  -F "source=@/tmp/test-source.zip" \
  -F "platform=ios")
echo "$BUILD_RESPONSE" | jq '.'
BUILD_ID=$(echo "$BUILD_RESPONSE" | jq -r '.id')
echo "Build ID: $BUILD_ID"
echo ""

# Check build status
echo "5. Check Build Status"
curl -s "$BASE_URL/api/builds/$BUILD_ID/status" | jq '.'
echo ""

# Worker polls for job
echo "6. Worker Polls for Job"
curl -s "$BASE_URL/api/workers/poll?worker_id=$WORKER_ID" | jq '.'
echo ""

# Check build status again (should be assigned)
echo "7. Check Build Status (After Assignment)"
curl -s "$BASE_URL/api/builds/$BUILD_ID/status" | jq '.'
echo ""

# Get build logs
echo "8. Get Build Logs"
curl -s "$BASE_URL/api/builds/$BUILD_ID/logs" | jq '.'
echo ""

# Cleanup
rm -rf /tmp/test-build /tmp/test-source.zip

echo "Test complete!"
echo ""
echo "Open $BASE_URL in browser to see Web UI"
