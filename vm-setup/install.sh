#!/bin/bash
#
# Expo Free Agent VM Bootstrap Installer
#
# Public installer script that sets up VM agent scripts.
# Can be run inside any VM to install/update the agent system.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/sethwebster/expo-free-agent/main/vm-setup/install.sh | bash
#
# Or with specific version:
#   curl -fsSL https://raw.githubusercontent.com/sethwebster/expo-free-agent/main/vm-setup/install.sh | VERSION=0.1.22 bash
#

set -e
set -o pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Configuration
VERSION="${VERSION:-latest}"
BASE_URL="https://github.com/sethwebster/expo-free-agent/releases/${VERSION}/download"
SCRIPTS_URL="${BASE_URL}/vm-scripts.tar.gz"
INSTALL_DIR="/usr/local/bin"
VERSION_FILE="/usr/local/etc/free-agent-version"
TEMP_DIR="/tmp/free-agent-install-$$"

log_info "=== Expo Free Agent VM Bootstrap Installer ==="
log_info "Version: $VERSION"
log_info "Source: $SCRIPTS_URL"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    log_error "Don't run this script as root. It will use sudo when needed."
    exit 1
fi

# Check if running inside macOS VM
if [ "$(uname)" != "Darwin" ]; then
    log_error "This script must be run inside a macOS VM"
    exit 1
fi

# Check dependencies
log_step "Checking dependencies..."
MISSING_DEPS=()

if ! command -v curl &> /dev/null; then
    MISSING_DEPS+=("curl")
fi

if ! command -v jq &> /dev/null; then
    MISSING_DEPS+=("jq")
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    log_warn "Missing dependencies: ${MISSING_DEPS[*]}"
    log_info "Installing via Homebrew..."

    if ! command -v brew &> /dev/null; then
        log_error "Homebrew not found. Please install Homebrew first:"
        log_error "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi

    for dep in "${MISSING_DEPS[@]}"; do
        log_info "Installing $dep..."
        brew install "$dep"
    done
fi

log_info "✓ Dependencies installed"

# Download scripts
log_step "Downloading VM agent scripts..."
mkdir -p "$TEMP_DIR"
trap "rm -rf $TEMP_DIR" EXIT

if ! curl -L -f -s -S \
    --max-time 60 \
    --retry 3 \
    --retry-delay 5 \
    -o "$TEMP_DIR/vm-scripts.tar.gz" \
    "$SCRIPTS_URL"; then
    log_error "Failed to download scripts from $SCRIPTS_URL"
    log_error ""
    log_error "If you're installing from an unreleased version, make sure:"
    log_error "  1. The GitHub release exists"
    log_error "  2. vm-scripts.tar.gz is uploaded to the release"
    log_error ""
    log_error "For latest release: VERSION=latest (default)"
    log_error "For specific version: VERSION=v0.1.22"
    exit 1
fi

log_info "✓ Scripts downloaded"

# Extract scripts
log_step "Extracting scripts..."
cd "$TEMP_DIR"
tar -xzf vm-scripts.tar.gz

# Verify all required scripts exist
REQUIRED_SCRIPTS=(
    "free-agent-auto-update"
    "free-agent-vm-bootstrap"
    "free-agent-run-job"
    "vm-monitor.sh"
    "install-signing-certs"
    "VERSION"
)

for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ ! -f "$TEMP_DIR/$script" ]; then
        log_error "Missing script in package: $script"
        exit 1
    fi
done

log_info "✓ All scripts present"

# Install scripts
log_step "Installing scripts to $INSTALL_DIR..."

for script in free-agent-auto-update free-agent-vm-bootstrap free-agent-run-job vm-monitor.sh install-signing-certs; do
    log_info "Installing $script..."
    sudo cp "$TEMP_DIR/$script" "$INSTALL_DIR/"
    sudo chmod +x "$INSTALL_DIR/$script"
done

log_info "✓ Scripts installed"

# Install version file
log_step "Installing version file..."
sudo mkdir -p /usr/local/etc
sudo cp "$TEMP_DIR/VERSION" "$VERSION_FILE"
INSTALLED_VERSION=$(cat "$VERSION_FILE")
log_info "✓ Version: $INSTALLED_VERSION"

# Install LaunchDaemon
log_step "Installing LaunchDaemon..."

# Create LaunchDaemon plist
sudo tee /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist > /dev/null << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.expo.free-agent.bootstrap</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/free-agent-auto-update</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/free-agent-bootstrap.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/free-agent-bootstrap.log</string>
    <key>WorkingDirectory</key>
    <string>/tmp</string>
    <key>AbandonProcessGroup</key>
    <false/>
    <key>SessionCreate</key>
    <false/>
    <key>KeepAlive</key>
    <false/>
    <key>ExitTimeOut</key>
    <integer>300</integer>
    <key>UserName</key>
    <string>admin</string>
    <key>GroupName</key>
    <string>staff</string>
    <key>ThrottleInterval</key>
    <integer>0</integer>
</dict>
</plist>
EOF

sudo chown root:wheel /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist
sudo chmod 644 /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist

log_info "✓ LaunchDaemon installed"

# Load LaunchDaemon
log_step "Loading LaunchDaemon..."
if sudo launchctl load /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist 2>/dev/null; then
    log_info "✓ LaunchDaemon loaded"
else
    log_warn "LaunchDaemon load failed (may already be loaded or will auto-load on next boot)"
fi

# Verification
log_step "Verifying installation..."

VERIFICATION_FAILED=false

# Check scripts exist and are executable
for script in free-agent-auto-update free-agent-vm-bootstrap free-agent-run-job vm-monitor.sh install-signing-certs; do
    if [ ! -x "$INSTALL_DIR/$script" ]; then
        log_error "Script not executable: $script"
        VERIFICATION_FAILED=true
    fi
done

# Check LaunchDaemon
if [ ! -f /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist ]; then
    log_error "LaunchDaemon plist not found"
    VERIFICATION_FAILED=true
fi

# Check version file
if [ ! -f "$VERSION_FILE" ]; then
    log_error "Version file not found"
    VERIFICATION_FAILED=true
fi

if [ "$VERIFICATION_FAILED" = true ]; then
    log_error "Verification failed - see errors above"
    exit 1
fi

log_info "✓ All files verified"

# Success!
echo ""
log_info "=== Installation Complete ==="
log_info "VM agent scripts installed successfully"
log_info "Version: $INSTALLED_VERSION"
echo ""
log_info "The bootstrap system will activate on next VM boot with env vars:"
log_info "  BUILD_ID, WORKER_ID, API_KEY, CONTROLLER_URL"
echo ""
log_info "To test the installation:"
log_info "  sudo shutdown -h now"
log_info "  # Then start VM with test env vars"
echo ""
log_info "Scripts are located at:"
log_info "  $INSTALL_DIR/free-agent-*"
log_info "  $INSTALL_DIR/vm-monitor.sh"
log_info "  $INSTALL_DIR/install-signing-certs"
echo ""
log_info "Logs will appear at:"
log_info "  /tmp/free-agent-auto-update.log"
log_info "  /tmp/free-agent-bootstrap.log"
