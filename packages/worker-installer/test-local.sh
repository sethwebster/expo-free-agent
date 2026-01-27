#!/bin/bash
# Local testing script for expo-free-agent installer
# This simulates the installer flow without actually downloading or installing

set -e

echo "🧪 Testing expo-free-agent installer locally"
echo "==========================================="
echo ""

# Check if we're in the right directory
if [ ! -f "package.json" ]; then
  echo "❌ Error: Must be run from packages/worker-installer directory"
  exit 1
fi

# Build the package
echo "📦 Building package..."
bun run build

if [ ! -f "dist/cli.js" ]; then
  echo "❌ Error: Build failed, dist/cli.js not found"
  exit 1
fi

echo "✅ Build successful"
echo ""

# Check if executable
if [ ! -x "dist/cli.js" ]; then
  echo "🔧 Making CLI executable..."
  chmod +x dist/cli.js
fi

# Display help
echo "📖 Showing help output:"
echo "------------------------"
./dist/cli.js --help
echo ""

# Check version
echo "📊 Checking version:"
echo "--------------------"
./dist/cli.js --version
echo ""

echo "✅ All tests passed!"
echo ""
echo "To test installation (will show real system checks):"
echo "  bun run dev --verbose"
echo ""
echo "To link for local npx testing:"
echo "  bun link"
echo "  npx expo-free-agent --help"
