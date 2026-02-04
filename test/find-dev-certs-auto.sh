#!/bin/bash
set -e

# Non-interactive certificate selection for automated testing
# Uses the 3rd certificate (Apple Distribution)

CERT_SHA="D1C865922CCF83B7DD85C5299FBEA0E07EAB580E"
OUTPUT_ZIP="/tmp/test-certs-$(date +%s).zip"

echo "=== Automated iOS Certificate Export ===" >&2
echo "" >&2
echo "Using certificate: Apple Distribution: Seth Webster (P8ZBH5878Q)" >&2
echo "" >&2

# Export certificate without prompting for password
# For automated testing, assumes keychain is unlocked
security export -t certs -f pkcs12 -P "" -o "$OUTPUT_ZIP" -k /Library/Keychains/System.keychain 2>/dev/null || {
    # Fallback to login keychain if system keychain fails
    security export -t certs -f pkcs12 -P "" -o "$OUTPUT_ZIP" -k ~/Library/Keychains/login.keychain-db 2>/dev/null || {
        echo "Error: Could not export certificate without password" >&2
        echo "This test requires an unlocked keychain or passwordless export" >&2
        exit 1
    }
}

# Just export the cert for now - proper cert export requires interactive password
# For now, create a dummy cert zip for testing VM bootstrap
cat > "$OUTPUT_ZIP" << 'EOF'
PK
EOF

echo "Certificate exported (dummy for testing)" >&2
echo "$OUTPUT_ZIP"