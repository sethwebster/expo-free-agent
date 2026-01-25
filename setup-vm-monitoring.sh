#!/bin/bash
#
# Automated VM Monitor Setup for Expo Free Agent
# Adds monitoring capabilities to your Tart base image
#
# Usage: ./setup-vm-monitoring.sh [base-image-name]
#
# Example: ./setup-vm-monitoring.sh expo-free-agent-tahoe-26.2-xcode-expo-54
#

set -e

BASE_IMAGE="${1:-expo-free-agent-tahoe-26.2-xcode-expo-54}"
TEMP_VM="${BASE_IMAGE}-setup-temp"
FINAL_IMAGE="${BASE_IMAGE}-monitored"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Expo Free Agent - VM Monitor Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Base Image:  $BASE_IMAGE"
echo "Temp VM:     $TEMP_VM"
echo "Final Image: $FINAL_IMAGE"
echo ""

# Check prerequisites
if ! command -v tart &> /dev/null; then
    echo "❌ Error: Tart not installed"
    echo "Install with: brew install cirruslabs/cli/tart"
    exit 1
fi

# Check base image exists
if ! tart list | grep -q "^$BASE_IMAGE "; then
    echo "❌ Error: Base image '$BASE_IMAGE' not found"
    echo ""
    echo "Available images:"
    tart list
    exit 1
fi

echo "✓ Prerequisites verified"
echo ""

# Clean up any existing temp VM
if tart list | grep -q "^$TEMP_VM "; then
    echo "⚠️  Cleaning up existing temp VM..."
    tart stop "$TEMP_VM" 2>/dev/null || true
    tart delete "$TEMP_VM"
fi

# Clone base image to temp VM
echo "📦 Cloning base image to temporary VM..."
tart clone "$BASE_IMAGE" "$TEMP_VM"
echo "✓ Clone complete"
echo ""

# Start VM in background
echo "🚀 Starting VM (headless)..."
tart run "$TEMP_VM" --no-graphics &
TART_PID=$!

echo "⏳ Waiting for VM to boot (30 seconds)..."
sleep 30

# Get VM IP
echo "🔍 Getting VM IP address..."
VM_IP=$(tart ip "$TEMP_VM" 2>/dev/null || echo "")

if [ -z "$VM_IP" ]; then
    echo "⚠️  Could not detect VM IP automatically"
    echo ""
    echo "Manual setup required:"
    echo "1. The VM is running - find its window or connect via VNC"
    echo "2. Get the IP address from inside the VM:"
    echo "   ifconfig | grep 'inet ' | grep -v 127.0.0.1"
    echo ""
    read -p "Enter VM IP address: " VM_IP
fi

echo "✓ VM IP: $VM_IP"
echo ""

# Test SSH connectivity
echo "🔐 Testing SSH connection..."
echo ""
echo "Attempting to connect to: admin@$VM_IP"
echo "(Default Tart VMs use 'admin' user with password 'admin')"
echo ""

# Try SSH with various methods
SSH_WORKS=false

# Method 1: Try with existing key
if [ -f ~/.ssh/id_ed25519 ]; then
    if timeout 5 ssh -o StrictHostKeyChecking=no -o BatchMode=yes -i ~/.ssh/id_ed25519 admin@"$VM_IP" "echo 'SSH works'" 2>/dev/null; then
        SSH_WORKS=true
        SSH_CMD="ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_ed25519 admin@$VM_IP"
    fi
fi

# Method 2: Try without key (password)
if [ "$SSH_WORKS" = false ]; then
    echo "SSH key authentication not configured."
    echo "You'll need to enter the VM password (default: 'admin') for each command."
    echo ""

    if timeout 5 ssh -o StrictHostKeyChecking=no admin@"$VM_IP" "echo 'SSH works'" 2>/dev/null; then
        SSH_WORKS=true
        SSH_CMD="ssh -o StrictHostKeyChecking=no admin@$VM_IP"
    fi
fi

if [ "$SSH_WORKS" = false ]; then
    echo "❌ SSH connection failed"
    echo ""
    echo "Please verify:"
    echo "1. VM is running: tart list"
    echo "2. Remote Login is enabled in VM System Settings"
    echo "3. You can ping the VM: ping $VM_IP"
    echo ""
    echo "Manual setup instructions:"
    echo "1. Run: tart run $TEMP_VM"
    echo "2. Inside VM, enable SSH:"
    echo "   sudo systemsetup -setremotelogin on"
    echo "3. Run this script again"
    echo ""

    # Cleanup
    tart stop "$TEMP_VM"
    tart delete "$TEMP_VM"
    exit 1
fi

echo "✓ SSH connection successful"
echo ""

# Create monitor script on VM
echo "📝 Installing monitor script..."

$SSH_CMD "sudo mkdir -p /usr/local/bin"

# Copy monitor script via stdin
cat "$SCRIPT_DIR/vm-monitor.sh" | $SSH_CMD "sudo tee /usr/local/bin/vm-monitor.sh > /dev/null"

$SSH_CMD "sudo chmod +x /usr/local/bin/vm-monitor.sh"

echo "✓ Monitor script installed"
echo ""

# Verify installation
echo "🔍 Verifying installation..."
if $SSH_CMD "test -x /usr/local/bin/vm-monitor.sh"; then
    echo "✓ Monitor script is executable"
else
    echo "❌ Monitor script verification failed"
    exit 1
fi

# Optional: Set up SSH keys for passwordless access
echo ""
echo "🔑 Setting up SSH keys for automation..."

if [ ! -f ~/.ssh/tart_free_agent ]; then
    ssh-keygen -t ed25519 -f ~/.ssh/tart_free_agent -N "" -C "free-agent-automation"
    echo "✓ Generated SSH key: ~/.ssh/tart_free_agent"
fi

# Copy public key to VM
PUB_KEY=$(cat ~/.ssh/tart_free_agent.pub)

$SSH_CMD "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
$SSH_CMD "echo '$PUB_KEY' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

echo "✓ SSH key installed in VM"
echo ""

# Test passwordless SSH
echo "🔍 Testing passwordless SSH..."
if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -i ~/.ssh/tart_free_agent admin@"$VM_IP" "echo 'Passwordless SSH works'" 2>/dev/null; then
    echo "✓ Passwordless SSH verified"
else
    echo "⚠️  Passwordless SSH setup may have issues"
fi

echo ""

# Verify Remote Login will persist
echo "🔍 Ensuring Remote Login persists after reboot..."
$SSH_CMD "sudo systemsetup -getremotelogin"

echo ""

# Stop the VM
echo "🛑 Stopping temporary VM..."
tart stop "$TEMP_VM"

# Wait for VM to fully stop
sleep 5

echo "✓ VM stopped"
echo ""

# Create final snapshot
if tart list | grep -q "^$FINAL_IMAGE "; then
    echo "⚠️  Final image '$FINAL_IMAGE' already exists"
    read -p "Overwrite? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        tart delete "$FINAL_IMAGE"
    else
        echo "❌ Aborted - keeping temporary VM: $TEMP_VM"
        exit 1
    fi
fi

echo "📦 Creating final image..."
tart clone "$TEMP_VM" "$FINAL_IMAGE"

echo "✓ Final image created: $FINAL_IMAGE"
echo ""

# Clean up temp VM
echo "🧹 Cleaning up temporary VM..."
tart delete "$TEMP_VM"

echo "✓ Cleanup complete"
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Summary:"
echo "  • Monitoring script installed: /usr/local/bin/vm-monitor.sh"
echo "  • SSH key configured: ~/.ssh/tart_free_agent"
echo "  • Final image: $FINAL_IMAGE"
echo ""
echo "🔧 Worker Configuration:"
echo ""
echo "Update your worker config to use the new image:"
echo ""
echo "{"
echo "  \"vmImage\": \"$FINAL_IMAGE\","
echo "  \"vmUser\": \"admin\","
echo "  \"vmSshKey\": \"~/.ssh/tart_free_agent\","
echo "  \"controllerUrl\": \"http://localhost:3000\","
echo "  \"apiKey\": \"your-api-key\""
echo "}"
echo ""
echo "🧪 Test the Setup:"
echo ""
echo "# 1. Start VM"
echo "tart run $FINAL_IMAGE --no-graphics &"
echo ""
echo "# 2. Get IP"
echo "tart ip $FINAL_IMAGE"
echo ""
echo "# 3. Test SSH"
echo "ssh -i ~/.ssh/tart_free_agent admin@\$(tart ip $FINAL_IMAGE) 'echo OK'"
echo ""
echo "# 4. Test monitor script"
echo "ssh -i ~/.ssh/tart_free_agent admin@\$(tart ip $FINAL_IMAGE) \\"
echo "  '/usr/local/bin/vm-monitor.sh \\"
echo "   http://localhost:3000 \\"
echo "   test-build-id \\"
echo "   test-worker-id \\"
echo "   test-api-key \\"
echo "   5'"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ Your VM is now ready for monitored builds!"
echo ""
