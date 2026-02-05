#!/bin/bash
set -euo pipefail

BOOTSTRAP_SCRIPT="free-agent/Sources/WorkerCore/Resources/free-agent-bootstrap.sh"

if ! rg -n "keychainPassword" "$BOOTSTRAP_SCRIPT" >/dev/null; then
  echo "FAIL: bootstrap script missing keychainPassword handling"
  exit 1
fi

if rg -n "keychainPassword.*base64 -d" "$BOOTSTRAP_SCRIPT" >/dev/null; then
  echo "FAIL: keychainPassword is still base64-decoded in bootstrap"
  exit 1
fi

echo "PASS: keychainPassword is treated as plain text"
