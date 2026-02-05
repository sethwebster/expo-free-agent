#!/bin/bash
#
# diagnostics.sh
#
# VM diagnostics script for Expo Free Agent.
# Writes a comprehensive debug snapshot to /tmp/free-agent-diagnostics.log
#

set -euo pipefail

LOG_FILE="/tmp/free-agent-diagnostics.log"
MOUNT_POINT="/Volumes/My Shared Files/build-config"

log_section() {
    echo "" | tee -a "$LOG_FILE"
    echo "===== $1 =====" | tee -a "$LOG_FILE"
}

log_kv() {
    echo "$1: $2" | tee -a "$LOG_FILE"
}

exec >>"$LOG_FILE" 2>&1

echo "Expo Free Agent - VM Diagnostics"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "================================="

log_section "System"
log_kv "User" "$(whoami)"
log_kv "UID" "$(id -u)"
log_kv "GID" "$(id -g)"
log_kv "Uname" "$(uname -a)"
log_kv "macOS" "$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
log_kv "Uptime" "$(uptime)"

log_section "Environment"
log_kv "HOME" "${HOME:-}"
log_kv "PATH" "${PATH:-}"
log_kv "SHELL" "${SHELL:-}"
log_kv "PWD" "$(pwd)"

log_section "Disk"
df -h

log_section "Mounts"
mount

log_section "Build Config Mount"
log_kv "Mount Point" "$MOUNT_POINT"
if [ -d "$MOUNT_POINT" ]; then
    ls -la "$MOUNT_POINT"
else
    echo "Mount point not found"
fi

log_section "Build Config Files"
for f in build-config.json bootstrap-complete progress.json build-error build-complete; do
    if [ -f "$MOUNT_POINT/$f" ]; then
        echo "--- $MOUNT_POINT/$f ---"
        cat "$MOUNT_POINT/$f"
    fi
done

log_section "Logs"
if [ -f /tmp/free-agent-bootstrap.log ]; then
    echo "--- /tmp/free-agent-bootstrap.log (tail) ---"
    tail -n 200 /tmp/free-agent-bootstrap.log
fi
if [ -f /tmp/free-agent-stub.log ]; then
    echo "--- /tmp/free-agent-stub.log (tail) ---"
    tail -n 200 /tmp/free-agent-stub.log
fi

log_section "Build Log"
if [ -f /var/log/build.log ]; then
    echo "--- /var/log/build.log (tail) ---"
    tail -n 200 /var/log/build.log
else
    echo "No build log found at /var/log/build.log"
fi

log_section "Processes (top 30)"
ps aux | head -n 31

log_section "Process Snapshot (build tools)"
pgrep -fl "xcodebuild|node|npm|expo|swift|clang" || echo "No matching build tool processes"

log_section "Xcode"
if command -v xcodebuild >/dev/null 2>&1; then
    xcodebuild -version
else
    echo "xcodebuild not found"
fi
if command -v xcode-select >/dev/null 2>&1; then
    xcode-select -p
fi
if command -v xcrun >/dev/null 2>&1; then
    xcrun --find xcodebuild || true
fi

log_section "Keychain Identities"
security find-identity -v -p codesigning || true

log_section "Provisioning Profiles"
ls -la "$HOME/Library/MobileDevice/Provisioning Profiles" || true

log_section "Network"
if [ -f "$MOUNT_POINT/build-config.json" ]; then
    CONTROLLER_URL=$(python3 - <<'PY'
import json, sys
path = "/Volumes/My Shared Files/build-config/build-config.json"
try:
    with open(path, "r") as f:
        data = json.load(f)
    print(data.get("controller_url", ""))
except Exception:
    print("")
PY
)
    if [ -n "$CONTROLLER_URL" ]; then
        log_kv "Controller URL" "$CONTROLLER_URL"
        curl -sS "$CONTROLLER_URL/health" || true
    fi
fi

log_section "Done"
echo "Diagnostics complete. Log saved to $LOG_FILE"

cat "$LOG_FILE"
