#!/bin/bash

#
# Quick Smoketest - Verifies basic system functionality
# Runs in ~30 seconds
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}▶${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Expo Free Agent - Smoketest"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check Bun installed
log_info "Checking Bun installation..."
if ! command -v bun &> /dev/null; then
    log_error "Bun not found. Install from https://bun.sh"
    exit 1
fi
log_success "Bun $(bun --version) installed"

# Install dependencies
log_info "Installing dependencies..."
if ! bun install > /dev/null 2>&1; then
    log_error "Dependency installation failed"
    exit 1
fi
log_success "Dependencies installed"

# CLI tests
log_info "Running CLI tests..."
cd packages/cli
if ! bun test > /dev/null 2>&1; then
    log_error "CLI tests failed"
    bun test
    exit 1
fi
log_success "CLI tests passed"
cd ../..

# Build CLI
log_info "Building CLI..."
cd packages/cli
if ! bun run build > /dev/null 2>&1; then
    log_error "CLI build failed"
    exit 1
fi
log_success "CLI built successfully"
cd ../..

# Build Free Agent (if on macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    log_info "Building Free Agent..."
    cd free-agent
    if ! swift build -c release > /dev/null 2>&1; then
        log_error "Free Agent build failed"
        swift build -c release
        exit 1
    fi
    log_success "Free Agent built successfully"
    cd ..
else
    log_info "Skipping Free Agent build (macOS only)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}  ✓ Smoketest Passed!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "  • Run full E2E test: ./test-e2e-elixir.sh"
echo "  • Start controller: bun controller (Elixir/Phoenix)"
echo "  • Read setup guide: docs/getting-started/setup-local.md"
echo ""
