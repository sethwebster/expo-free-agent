#!/bin/bash
#
# Quick test to verify VM bootstrap works with our setup
#

set -e

echo "=== VM Bootstrap Check ==="
echo ""

# Create test mount directory
TEST_MOUNT="/tmp/test-bootstrap-$$"
mkdir -p "$TEST_MOUNT"

# Copy bootstrap script
echo "Copying bootstrap script..."
cp free-agent/Sources/WorkerCore/Resources/free-agent-bootstrap.sh "$TEST_MOUNT/bootstrap.sh"
chmod +x "$TEST_MOUNT/bootstrap.sh"

# Create minimal config
cat > "$TEST_MOUNT/build-config.json" << EOF
{
  "build_id": "test-$(date +%s)",
  "controller_url": "http://192.168.64.1:4445",
  "platform": "ios",
  "otp": "test-otp"
}
EOF

# Clone and start VM
VM_NAME="test-bootstrap-$(date +%s)"
echo "Cloning VM: $VM_NAME"
/opt/homebrew/bin/tart clone expo-free-agent-base-local "$VM_NAME"

echo ""
echo "Starting VM with mount..."
echo "Mount will be at: /Volumes/My Shared Files/build-config"
echo ""

# Start VM in background
/opt/homebrew/bin/tart run --dir "build-config:$TEST_MOUNT" "$VM_NAME" &
VM_PID=$!

echo "VM started (PID: $VM_PID)"
echo "Waiting for bootstrap..."
echo ""

# Wait for vm-ready file
TIMEOUT=60
START_TIME=$(date +%s)

while true; do
  if [ -f "$TEST_MOUNT/vm-ready" ]; then
    echo "✓ Bootstrap completed!"
    cat "$TEST_MOUNT/vm-ready"
    break
  fi

  ELAPSED=$(($(date +%s) - START_TIME))
  if [ $ELAPSED -gt $TIMEOUT ]; then
    echo "✗ Bootstrap timeout after ${TIMEOUT}s"

    # Check if bootstrap started
    if [ -f "$TEST_MOUNT/bootstrap-started" ]; then
      echo "Bootstrap started but didn't complete:"
      cat "$TEST_MOUNT/bootstrap-started"
    else
      echo "Bootstrap never started - stub may have failed"
    fi

    # Check VM is running
    if /opt/homebrew/bin/tart list | grep -q "$VM_NAME.*running"; then
      echo "VM is still running"

      # Try to get VM IP and check logs
      VM_IP=$(/opt/homebrew/bin/tart ip "$VM_NAME" 2>/dev/null || echo "unknown")
      echo "VM IP: $VM_IP"
    else
      echo "VM is not running!"
    fi

    break
  fi

  printf "."
  sleep 1
done

echo ""
echo "Cleaning up..."

# Stop VM
kill $VM_PID 2>/dev/null || true
sleep 2
/opt/homebrew/bin/tart stop "$VM_NAME" 2>/dev/null || true
/opt/homebrew/bin/tart delete "$VM_NAME" 2>/dev/null || true

# Clean mount
rm -rf "$TEST_MOUNT"

echo "Done"