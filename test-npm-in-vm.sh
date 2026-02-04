#!/bin/bash
#
# Quick test to verify npm install works in VM
#

set -e

echo "Starting test VM..."
/opt/homebrew/bin/tart run expo-free-agent-base-local &
TART_PID=$!

sleep 15

echo "Getting VM IP..."
VM_IP=$(/opt/homebrew/bin/tart ip expo-free-agent-base-local)
echo "VM IP: $VM_IP"

echo "Creating test project in VM..."
/opt/homebrew/bin/tart exec expo-free-agent-base-local bash -c "
mkdir -p /tmp/test-project
cd /tmp/test-project

cat > package.json <<'EOF'
{
  \"name\": \"test\",
  \"version\": \"1.0.0\",
  \"dependencies\": {
    \"react\": \"^18.2.0\"
  }
}
EOF

echo 'Running npm install...'
npm install

if [ -d node_modules ]; then
  echo '✓ npm install succeeded!'
  ls -la node_modules/ | head -10
  exit 0
else
  echo '❌ npm install failed - node_modules not created'
  exit 1
fi
"

EXIT_CODE=$?

echo "Stopping VM..."
/opt/homebrew/bin/tart stop expo-free-agent-base-local

if [ $EXIT_CODE -eq 0 ]; then
  echo "✅ Test passed - npm install works in VM"
else
  echo "❌ Test failed - npm install failed"
fi

exit $EXIT_CODE
