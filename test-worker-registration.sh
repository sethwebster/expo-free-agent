#!/bin/bash

API_KEY="${CONTROLLER_API_KEY:-test-api-key-for-e2e-testing-minimum-32-chars}"
CONTROLLER_URL="http://localhost:4444"

echo "=== Testing Worker Registration and Polling ==="
echo ""

# Step 1: Register worker (without sending ID - let controller generate)
echo "Step 1: Registering worker..."
REGISTER_RESPONSE=$(curl -s -X POST "${CONTROLLER_URL}/api/workers/register" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${API_KEY}" \
  -d '{
    "name": "Test Worker",
    "capabilities": {"platform": "ios"}
  }')

echo "Registration response: $REGISTER_RESPONSE"
echo ""

# Extract worker ID from response
WORKER_ID=$(echo "$REGISTER_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
echo "Worker ID: '$WORKER_ID'"
echo "Worker ID length: ${#WORKER_ID}"
echo ""

# Step 2: Poll immediately
echo "Step 2: Polling with worker_id=${WORKER_ID}..."
POLL_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X GET "${CONTROLLER_URL}/api/workers/poll?worker_id=${WORKER_ID}" \
  -H "X-API-Key: ${API_KEY}")

# Split response and status
POLL_BODY=$(echo "$POLL_RESPONSE" | sed -e 's/HTTP_STATUS\:.*//g')
POLL_STATUS=$(echo "$POLL_RESPONSE" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')

echo "Poll response status: $POLL_STATUS"
echo "Poll response body: $POLL_BODY"
echo ""

if [ "$POLL_STATUS" = "200" ]; then
  echo "✓ SUCCESS: Worker can poll immediately after registration"
else
  echo "✗ FAILURE: Worker poll returned $POLL_STATUS"
  echo "This indicates the worker ID has been corrupted or database lookup is failing"
fi
