#!/bin/bash
# Expo Free Agent - Setup Verification Script
# Checks prerequisites and suggests fixes

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Expo Free Agent - Setup Verification${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

ERRORS=0
WARNINGS=0

# Helper functions
check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((ERRORS++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

# Check 1: Operating System
echo -e "${BLUE}[1/8]${NC} Checking operating system..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    check_pass "macOS detected"

    # Check macOS version
    MACOS_VERSION=$(sw_vers -productVersion)
    MAJOR_VERSION=$(echo $MACOS_VERSION | cut -d. -f1)

    if [ "$MAJOR_VERSION" -ge 13 ]; then
        check_pass "macOS version: $MACOS_VERSION (supported)"
    else
        check_warn "macOS version: $MACOS_VERSION (may have issues, recommend 13+)"
    fi
else
    check_fail "Not running on macOS (required for worker)"
    echo "         Controller can run on Linux, but worker requires macOS"
fi
echo ""

# Check 2: Bun
echo -e "${BLUE}[2/8]${NC} Checking Bun..."
if command -v bun &> /dev/null; then
    BUN_VERSION=$(bun --version)
    check_pass "Bun installed: v$BUN_VERSION"
else
    check_fail "Bun not installed"
    echo "         Install: curl -fsSL https://bun.sh/install | bash"
fi
echo ""

# Check 3: Node (optional but recommended)
echo -e "${BLUE}[3/8]${NC} Checking Node.js..."
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    check_pass "Node.js installed: $NODE_VERSION"
else
    check_warn "Node.js not installed (optional, but useful for npm packages)"
    echo "         Install: brew install node"
fi
echo ""

# Check 4: Git
echo -e "${BLUE}[4/8]${NC} Checking Git..."
if command -v git &> /dev/null; then
    GIT_VERSION=$(git --version | awk '{print $3}')
    check_pass "Git installed: v$GIT_VERSION"
else
    check_fail "Git not installed"
    echo "         Install: brew install git"
fi
echo ""

# Check 5: Apple Virtualization Support
echo -e "${BLUE}[5/8]${NC} Checking virtualization support..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    # Check if we're on Apple Silicon or Intel with VT-x
    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]]; then
        check_pass "Apple Silicon detected (native virtualization support)"
    elif [[ "$ARCH" == "x86_64" ]]; then
        check_warn "Intel Mac detected (virtualization supported but slower)"
    else
        check_warn "Unknown architecture: $ARCH"
    fi
else
    check_warn "Skipping (not on macOS)"
fi
echo ""

# Check 6: Disk Space
echo -e "${BLUE}[6/8]${NC} Checking available disk space..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    AVAILABLE_GB=$(df -h / | awk 'NR==2 {print $4}' | sed 's/Gi//')
    AVAILABLE_NUM=$(echo $AVAILABLE_GB | sed 's/[^0-9.]//g')

    if (( $(echo "$AVAILABLE_NUM > 50" | bc -l) )); then
        check_pass "Available space: ${AVAILABLE_GB}B (sufficient)"
    elif (( $(echo "$AVAILABLE_NUM > 20" | bc -l) )); then
        check_warn "Available space: ${AVAILABLE_GB}B (recommend 50GB+ for builds)"
    else
        check_fail "Available space: ${AVAILABLE_GB}B (insufficient, need 20GB+ minimum)"
    fi
else
    check_warn "Skipping (not on macOS)"
fi
echo ""

# Check 7: Port Availability
echo -e "${BLUE}[7/8]${NC} Checking port availability..."
if lsof -Pi :3000 -sTCP:LISTEN -t >/dev/null 2>&1; then
    check_warn "Port 3000 already in use"
    echo "         Process: $(lsof -Pi :3000 -sTCP:LISTEN | tail -n 1 | awk '{print $1}')"
    echo "         Stop it or configure controller to use different port"
else
    check_pass "Port 3000 available"
fi
echo ""

# Check 8: Environment Variables
echo -e "${BLUE}[8/8]${NC} Checking environment configuration..."
if [ -n "$EXPO_CONTROLLER_API_KEY" ]; then
    check_pass "EXPO_CONTROLLER_API_KEY set"
else
    check_warn "EXPO_CONTROLLER_API_KEY not set (required for builds)"
    echo "         Set after starting controller: export EXPO_CONTROLLER_API_KEY=\"...\""
fi

if [ -n "$EXPO_CONTROLLER_URL" ]; then
    check_pass "EXPO_CONTROLLER_URL set: $EXPO_CONTROLLER_URL"
else
    check_warn "EXPO_CONTROLLER_URL not set (will use default: http://localhost:3000)"
fi
echo ""

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Verification Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed!${NC}"
    echo ""
    echo "You're ready to start:"
    echo "  1. bun controller          # Start controller"
    echo "  2. Export API key from controller output"
    echo "  3. open FreeAgent.app      # Start worker"
    echo ""
    echo "Or follow: docs/getting-started/5-minute-start.md"
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ ${WARNINGS} warning(s)${NC}"
    echo ""
    echo "Setup is functional but could be improved."
    echo "Review warnings above and fix if needed."
    echo ""
    echo "Continue with: docs/getting-started/5-minute-start.md"
else
    echo -e "${RED}❌ ${ERRORS} error(s), ${WARNINGS} warning(s)${NC}"
    echo ""
    echo "Please fix errors above before continuing."
    echo ""
    echo "Need help? See: docs/getting-started/setup-local.md"
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
