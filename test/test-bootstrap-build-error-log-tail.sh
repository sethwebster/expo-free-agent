#!/bin/bash
set -euo pipefail

BOOTSTRAP_SCRIPT="free-agent/Sources/WorkerCore/Resources/free-agent-bootstrap.sh"

if ! rg -n "build-error" "$BOOTSTRAP_SCRIPT" >/dev/null; then
  echo "FAIL: bootstrap script missing build-error handling"
  exit 1
fi

if ! rg -n "log_tail" "$BOOTSTRAP_SCRIPT" >/dev/null; then
  echo "FAIL: build-error does not include log_tail"
  exit 1
fi

echo "PASS: build-error includes log_tail"
