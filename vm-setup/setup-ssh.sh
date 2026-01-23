#!/bin/bash

# setup-ssh.sh
# Generate SSH keys for VM communication

set -e

SSH_DIR="$HOME/.ssh"
KEY_NAME="free_agent_ed25519"
KEY_PATH="$SSH_DIR/$KEY_NAME"

echo "Setting up SSH keys for Free Agent VM communication"
echo ""

# Create .ssh directory if doesn't exist
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Generate SSH key pair if doesn't exist
if [ -f "$KEY_PATH" ]; then
    echo "SSH key already exists at: $KEY_PATH"
    echo "Skipping key generation."
else
    echo "Generating SSH key pair..."
    ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "free-agent-vm"
    chmod 600 "$KEY_PATH"
    chmod 644 "$KEY_PATH.pub"
    echo "✓ SSH key pair generated"
fi

echo ""
echo "Public key location: $KEY_PATH.pub"
echo "Private key location: $KEY_PATH"
echo ""
echo "Public key content:"
cat "$KEY_PATH.pub"
echo ""
echo "====================================="
echo "Next Steps:"
echo "====================================="
echo ""
echo "1. Boot your VM"
echo ""
echo "2. Inside the VM, add this public key to authorized_keys:"
echo "   sudo mkdir -p /Users/builder/.ssh"
echo "   sudo nano /Users/builder/.ssh/authorized_keys"
echo "   # Paste the public key above"
echo "   sudo chown -R builder:staff /Users/builder/.ssh"
echo "   sudo chmod 700 /Users/builder/.ssh"
echo "   sudo chmod 600 /Users/builder/.ssh/authorized_keys"
echo ""
echo "3. Test SSH connection:"
echo "   ssh -i $KEY_PATH builder@192.168.64.2"
echo ""
