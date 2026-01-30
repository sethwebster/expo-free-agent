#!/bin/bash

echo "=== Testing Worker Registration and Polling Flow ==="
echo ""

# Check controller is running
if ! lsof -ti:4444 > /dev/null; then
  echo "ERROR: Elixir controller not running on port 4444"
  exit 1
fi

# Clean state
rm -f ~/Library/Application\ Support/FreeAgent/config.json
echo "✓ Cleared config file"
echo ""

# Monitor controller logs for next 10 seconds and capture worker registration
echo "Starting FreeAgent worker..."
echo "Monitoring controller logs for registration and polling..."
echo ""

# Start log monitoring in background
(cd /Users/sethwebster/Development/expo/elixir-controller-migration/packages/controller-elixir && \
  iex -S mix 2>&1 | grep -E "(Registering|registered|Poll|worker_id)" &)

LOG_PID=$!
sleep 2

# Start FreeAgent worker
cd /Users/sethwebster/Development/expo/elixir-controller-migration/free-agent
swift run FreeAgent &
WORKER_PID=$!

# Wait for registration to complete
sleep 5

# Check config file
if [ -f ~/Library/Application\ Support/FreeAgent/config.json ]; then
  WORKER_ID=$(cat ~/Library/Application\ Support/FreeAgent/config.json | python3 -c "import sys, json; print(json.load(sys.stdin).get('workerID', 'nil'))")
  echo ""
  echo "=== Results ==="
  echo "Worker ID saved to config: '$WORKER_ID'"
  echo "Worker ID length: ${#WORKER_ID}"

  if [ "$WORKER_ID" != "nil" ] && [ ${#WORKER_ID} -eq 21 ]; then
    echo "✓ SUCCESS: Worker registered with valid nanoid"
  else
    echo "✗ FAILURE: Invalid worker ID format"
  fi
else
  echo "✗ FAILURE: Config file not created"
fi

# Cleanup
kill $WORKER_PID 2>/dev/null
kill $LOG_PID 2>/dev/null

echo ""
echo "Test complete"
