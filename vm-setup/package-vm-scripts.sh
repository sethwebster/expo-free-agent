#!/bin/bash
#
# package-vm-scripts.sh
#
# Packages VM scripts for distribution with GitHub releases.
# Creates vm-scripts.tar.gz with all agent scripts.
#
# Usage: ./package-vm-scripts.sh [output-dir]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$(cd "${1:-.}" && pwd)"

SCRIPTS=(
    "free-agent-auto-update"
    "free-agent-vm-bootstrap"
    "free-agent-run-job"
    "vm-monitor.sh"
    "install-signing-certs"
    "VERSION"
)

echo "Packaging VM scripts..."

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy scripts
for script in "${SCRIPTS[@]}"; do
    if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
        echo "ERROR: Missing script: $script"
        exit 1
    fi
    cp "$SCRIPT_DIR/$script" "$TEMP_DIR/"
    echo "  ✓ $script"
done

# Create tarball in output directory (not in temp!)
cd "$TEMP_DIR"
TARBALL_PATH="$(cd "$OUTPUT_DIR" && pwd)/vm-scripts.tar.gz"
tar -czf "$TARBALL_PATH" ./*

echo "✓ Package created: $TARBALL_PATH"
echo ""
echo "Upload this file to GitHub releases with the same tag as the app bundle."
echo "Example: gh release upload v0.1.22 vm-scripts.tar.gz"
