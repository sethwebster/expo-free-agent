#!/bin/bash
#
# Test to verify the mount path is correct in all scripts
# This prevents regression of the "Files" vs "Folders" issue
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "=== Mount Path Consistency Test ==="
echo ""
echo "Verifying all scripts use the correct mount path..."
echo ""

# The correct mount path that Tart VMs actually use
CORRECT_MOUNT_PATH="/Volumes/My Shared Files/build-config"
ERRORS=0
FILES_CHECKED=0

# Function to check a file for mount paths
check_file() {
    local file="$1"
    local filename=$(basename "$file")

    FILES_CHECKED=$((FILES_CHECKED + 1))

    # Check for the correct path
    if grep -q "$CORRECT_MOUNT_PATH" "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $filename uses correct path"
        return 0
    fi

    # Check for the wrong path (Folders instead of Files)
    if grep -q "/Volumes/My Shared Folders/build-config" "$file" 2>/dev/null; then
        echo -e "${RED}✗${NC} $filename uses WRONG path (Folders instead of Files)"
        echo "    Found: '/Volumes/My Shared Folders/build-config'"
        echo "    Should be: '$CORRECT_MOUNT_PATH'"
        ERRORS=$((ERRORS + 1))
        return 1
    fi

    # If file references mount points but doesn't have either path
    if grep -q "/Volumes/My Shared" "$file" 2>/dev/null; then
        echo -e "${RED}✗${NC} $filename has unexpected mount path"
        grep -n "/Volumes/My Shared" "$file" | head -3
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

# Critical files that must have the correct mount path
echo "Checking critical files..."
check_file "vm-setup/free-agent-stub.sh"
check_file "free-agent/Sources/WorkerCore/Resources/free-agent-bootstrap.sh"

# Check test scripts for references
echo ""
echo "Checking test scripts..."
for test_file in test*.sh test/*.sh; do
    if [[ -f "$test_file" ]] && grep -q "/Volumes/My Shared" "$test_file" 2>/dev/null; then
        check_file "$test_file"
    fi
done

# Check VM setup scripts
echo ""
echo "Checking VM setup scripts..."
for setup_file in vm-setup/*.sh; do
    if [[ -f "$setup_file" ]] && grep -q "/Volumes/My Shared" "$setup_file" 2>/dev/null; then
        check_file "$setup_file"
    fi
done

# Check TypeScript/JavaScript files that might reference the mount
echo ""
echo "Checking worker scripts..."
for ts_file in test/*.ts test/*.js; do
    if [[ -f "$ts_file" ]] && grep -q "Volumes.*Shared" "$ts_file" 2>/dev/null; then
        # Check for comments mentioning the path
        if grep -q "Volumes.*Shared.*Files" "$ts_file" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} $(basename "$ts_file") comment references correct path"
        elif grep -q "Volumes.*Shared.*Folders" "$ts_file" 2>/dev/null; then
            echo -e "${RED}✗${NC} $(basename "$ts_file") has outdated comment about mount path"
            grep -n "Volumes.*Shared.*Folders" "$ts_file" | head -3
            ERRORS=$((ERRORS + 1))
        fi
    fi
done

echo ""
echo "======================================="
echo "Files checked: $FILES_CHECKED"

if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}✓ All mount paths are correct!${NC}"
    echo ""
    echo "The mount path '$CORRECT_MOUNT_PATH' is used consistently."
    exit 0
else
    echo -e "${RED}✗ Found $ERRORS files with incorrect mount paths${NC}"
    echo ""
    echo "Fix these files to use: $CORRECT_MOUNT_PATH"
    echo "(Tart mounts appear at 'My Shared Files', not 'My Shared Folders')"
    exit 1
fi