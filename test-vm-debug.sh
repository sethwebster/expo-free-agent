#!/bin/bash
# Debug script to test VM bootstrap with ability to login

set -e

echo "=== VM Bootstrap Debug Test ==="
echo ""
echo "This test will:"
echo "1. Clone a test VM"
echo "2. Create a test mount directory"
echo "3. Start VM with mount and graphics"
echo "4. Allow you to login and debug"
echo ""

# Clone VM
VM_NAME="test-debug-$(date +%s)"
echo "Cloning VM: $VM_NAME"
/opt/homebrew/bin/tart clone expo-free-agent-base-local "$VM_NAME"

# Create test mount directory with a modified bootstrap that doesn't change password
TEST_MOUNT="/tmp/test-mount-$$"
mkdir -p "$TEST_MOUNT"

# Create the no-password-reset flag file
touch "$TEST_MOUNT/no-password-reset"
echo "Created no-password-reset flag to skip password randomization"

# Create a debug bootstrap script
cat > "$TEST_MOUNT/bootstrap.sh" << 'EOF'
#!/bin/bash
set -e

# Debug version - logs to verify bootstrap runs
echo "[DEBUG] Bootstrap script is running!" | tee /tmp/bootstrap-ran.txt
echo "[DEBUG] Mount is working!" | tee -a /tmp/bootstrap-ran.txt
echo "[DEBUG] Current directory: $(pwd)" | tee -a /tmp/bootstrap-ran.txt
echo "[DEBUG] Mount contents:" | tee -a /tmp/bootstrap-ran.txt
ls -la "/Volumes/My Shared Files/build-config/" | tee -a /tmp/bootstrap-ran.txt

# Write status file so we know it worked
echo "Bootstrap started at $(date)" > "/Volumes/My Shared Files/build-config/bootstrap-started"
EOF

chmod +x "$TEST_MOUNT/bootstrap.sh"

# Create build-config.json (minimal)
cat > "$TEST_MOUNT/build-config.json" << EOF
{
  "build_id": "test-debug",
  "controller_url": "http://192.168.64.1:4445",
  "platform": "ios"
}
EOF

echo ""
echo "Starting VM with graphics..."
echo "Mount will be at: /Volumes/My Shared Files/build-config"
echo ""
echo "To debug inside the VM:"
echo "  Username: admin"
echo "  Password: admin"
echo ""
echo "Check these things:"
echo "  1. sudo launchctl list | grep expo"
echo "  2. ls -la '/Volumes/My Shared Files/'"
echo "  3. cat /tmp/free-agent-stub.log"
echo "  4. cat /tmp/bootstrap-ran.txt"
echo "  5. sudo /usr/local/bin/free-agent-stub.sh"
echo ""

# Start VM with mount and graphics
/opt/homebrew/bin/tart run --graphics --dir "build-config:$TEST_MOUNT" "$VM_NAME"

echo ""
echo "Cleaning up..."
/opt/homebrew/bin/tart delete "$VM_NAME"
rm -rf "$TEST_MOUNT"
echo "Done!"