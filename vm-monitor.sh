#!/bin/bash
#
# VM Build Monitor - Runs inside Tart VM during build
# Sends heartbeats to controller to prove build is progressing
#
# Usage: ./vm-monitor.sh <controller-url> <build-id> <worker-id> <api-key>
#
# Example:
#   ./vm-monitor.sh https://builds.example.com abc123 worker456 my-api-key &
#   MONITOR_PID=$!
#   # ... run build ...
#   kill $MONITOR_PID
#

set -e

CONTROLLER_URL="$1"
BUILD_ID="$2"
WORKER_ID="$3"
API_KEY="$4"
INTERVAL="${5:-30}"  # Send heartbeat every 30 seconds

if [ -z "$CONTROLLER_URL" ] || [ -z "$BUILD_ID" ] || [ -z "$WORKER_ID" ] || [ -z "$API_KEY" ]; then
  echo "Usage: $0 <controller-url> <build-id> <worker-id> <api-key> [interval-seconds]"
  exit 1
fi

echo "[VM Monitor] Starting for build $BUILD_ID"
echo "[VM Monitor] Sending heartbeats every ${INTERVAL}s to $CONTROLLER_URL"

# Function to send heartbeat
send_heartbeat() {
  local progress="${1:-0}"

  curl -s -X POST \
    "${CONTROLLER_URL}/api/builds/${BUILD_ID}/heartbeat?worker_id=${WORKER_ID}" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${API_KEY}" \
    -d "{\"progress\": ${progress}}" \
    > /dev/null 2>&1

  if [ $? -eq 0 ]; then
    echo "[VM Monitor] Heartbeat sent (progress: ${progress}%)"
  else
    echo "[VM Monitor] Failed to send heartbeat"
  fi
}

# Trap signals to send final heartbeat before exit
trap 'echo "[VM Monitor] Stopping..."; exit 0' SIGTERM SIGINT

# Send initial heartbeat
send_heartbeat 0

# Loop: send heartbeat every N seconds
COUNTER=0
while true; do
  sleep "$INTERVAL"

  # Estimate progress based on time (very rough)
  # Real builds should calculate actual progress
  COUNTER=$((COUNTER + 1))
  PROGRESS=$((COUNTER * 5))
  if [ $PROGRESS -gt 99 ]; then
    PROGRESS=99
  fi

  send_heartbeat "$PROGRESS"
done
