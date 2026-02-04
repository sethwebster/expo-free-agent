#!/bin/bash
#
# Minimal test to verify stub script execution
#

set -e

echo "=== Minimal Stub Test ==="
echo ""

# Create test mount directory
TEST_MOUNT="/tmp/test-stub-$$"
mkdir -p "$TEST_MOUNT"

# Create simple bootstrap that just writes a file
cat > "$TEST_MOUNT/bootstrap.sh" << 'EOF'
#!/bin/bash
echo "Bootstrap is running!" > /Volumes/My\ Shared\ Files/build-config/bootstrap-ran.txt
echo "Time: $(date)" >> /Volumes/My\ Shared\ Files/build-config/bootstrap-ran.txt
echo '{"status": "ready"}' > /Volumes/My\ Shared\ Files/build-config/vm-ready
EOF

chmod +x "$TEST_MOUNT/bootstrap.sh"

# Clone and start VM
VM_NAME="test-stub-$(date +%s)"
echo "Cloning VM: $VM_NAME"
/opt/homebrew/bin/tart clone expo-free-agent-base-local "$VM_NAME"

echo "Starting VM with mount..."
echo "Mount directory: $TEST_MOUNT"
echo ""

# Start VM with mount - run for 30 seconds
/opt/homebrew/bin/tart run --dir "build-config:$TEST_MOUNT" "$VM_NAME" &
VM_PID=$!

echo "VM started (PID: $VM_PID)"
echo "Waiting for stub to execute bootstrap..."
echo ""

# Wait for evidence of execution
TIMEOUT=30
START_TIME=$(date +%s)

while true; do
  # Check if bootstrap ran
  if [ -f "$TEST_MOUNT/bootstrap-ran.txt" ]; then
    echo "✓ Bootstrap executed!"
    cat "$TEST_MOUNT/bootstrap-ran.txt"
    break
  fi

  # Check if vm-ready exists
  if [ -f "$TEST_MOUNT/vm-ready" ]; then
    echo "✓ VM ready file created!"
    cat "$TEST_MOUNT/vm-ready"
    break
  fi

  ELAPSED=$(($(date +%s) - START_TIME))
  if [ $ELAPSED -gt $TIMEOUT ]; then
    echo "✗ Timeout after ${TIMEOUT}s"
    echo ""
    echo "Contents of mount directory:"
    ls -la "$TEST_MOUNT"
    echo ""

    # Check if VM is running
    if /opt/homebrew/bin/tart list | grep -q "$VM_NAME.*running"; then
      echo "VM is running"
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
/opt/homebrew/bin/tart delete "$VM_NAME"

# Clean mount
rm -rf "$TEST_MOUNT"

echo "Done"