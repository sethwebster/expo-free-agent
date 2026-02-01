#!/bin/bash
set -e

RANDOM_ID=$(uuidgen | cut -d'-' -f1)
VM_NAME="fa-test-${RANDOM_ID}"
VM_SETUP_PATH="$HOME/Development/expo/expo-free-agent/vm-setup"

echo "🚀 Launching test VM: $VM_NAME"
echo "📁 Mount path: free-agent:$VM_SETUP_PATH"
echo ""

# Clone base image
echo "Cloning expo-free-agent-base..."
/opt/homebrew/bin/tart clone expo-free-agent-base "$VM_NAME"

echo "✓ VM cloned successfully"
echo ""

# Run VM with directory mount
echo "Starting VM with directory mount..."
/opt/homebrew/bin/tart run "$VM_NAME" --dir="free-agent:$VM_SETUP_PATH"
