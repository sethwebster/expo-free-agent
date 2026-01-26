#!/bin/bash
#
# VM Build Monitor - Secure telemetry from inside Tart VM
# Lives at: /usr/local/bin/vm-monitor.sh inside VM
#
# SECURITY: Reads credentials from file (not visible in ps)
#
# Usage: vm-monitor.sh <creds-file> [interval-seconds]
#
# Creds file format (created by TartVMManager):
#   CONTROLLER_URL=https://...
#   BUILD_ID=abc123
#   WORKER_ID=xyz789
#   API_KEY=secret
#

set -e

CREDS_FILE="$1"
INTERVAL="${2:-30}"

if [ -z "$CREDS_FILE" ]; then
  echo "Usage: $0 <creds-file> [interval-seconds]"
  exit 1
fi

if [ ! -f "$CREDS_FILE" ]; then
  echo "ERROR: Credentials file not found: $CREDS_FILE"
  exit 1
fi

# Source credentials securely (file has 0600 permissions)
source "$CREDS_FILE"

# Validate required variables
if [ -z "$CONTROLLER_URL" ] || [ -z "$BUILD_ID" ] || [ -z "$WORKER_ID" ] || [ -z "$API_KEY" ]; then
  echo "ERROR: Missing required variables in credentials file"
  exit 1
fi

echo "[Monitor] Starting for build $BUILD_ID"
echo "[Monitor] Interval: ${INTERVAL}s"

# Trap signals for clean exit
trap 'echo "[Monitor] Stopped"; exit 0' SIGTERM SIGINT

# Send telemetry event
send_event() {
  local event_type="$1"
  local event_data="$2"

  local payload=$(cat <<EOF
{
  "type": "$event_type",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "data": $event_data
}
EOF
)

  curl -s -X POST \
    "${CONTROLLER_URL}/api/builds/${BUILD_ID}/telemetry" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${API_KEY}" \
    -H "X-Worker-Id: ${WORKER_ID}" \
    -H "X-Build-Id: ${BUILD_ID}" \
    -d "$payload" \
    > /dev/null 2>&1

  if [ $? -eq 0 ]; then
    echo "[Monitor] Event sent: $event_type"
  else
    echo "[Monitor] Failed to send: $event_type"
  fi
}

# Get system metrics
get_metrics() {
  local cpu_usage=$(top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/%//')
  local mem_used=$(vm_stat | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
  local disk_used=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')

  cat <<EOF
{
  "cpu_percent": ${cpu_usage:-0},
  "memory_mb": $((mem_used * 4096 / 1048576)),
  "disk_percent": ${disk_used:-0},
  "processes": $(ps aux | wc -l)
}
EOF
}

# Get build stage from xcodebuild log
get_build_stage() {
  local log_file="/tmp/xcodebuild.log"

  if [ ! -f "$log_file" ]; then
    echo '"initializing"'
    return
  fi

  # Detect build stage from log patterns
  if grep -q "Running script" "$log_file" 2>/dev/null; then
    echo '"building"'
  elif grep -q "Compiling" "$log_file" 2>/dev/null; then
    echo '"compiling"'
  elif grep -q "Linking" "$log_file" 2>/dev/null; then
    echo '"linking"'
  elif grep -q "Creating archive" "$log_file" 2>/dev/null; then
    echo '"archiving"'
  elif grep -q "Exporting" "$log_file" 2>/dev/null; then
    echo '"exporting"'
  else
    echo '"running"'
  fi
}

# Send startup event
send_event "monitor_started" '{}'

# Main loop: send periodic heartbeats with telemetry
COUNTER=0
while true; do
  sleep "$INTERVAL"

  COUNTER=$((COUNTER + 1))

  # Build telemetry payload
  METRICS=$(get_metrics)
  STAGE=$(get_build_stage)

  TELEMETRY=$(cat <<EOF
{
  "heartbeat_count": $COUNTER,
  "stage": $STAGE,
  "metrics": $METRICS,
  "uptime_seconds": $((COUNTER * INTERVAL))
}
EOF
)

  send_event "heartbeat" "$TELEMETRY"
done
