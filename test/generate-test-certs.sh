#!/bin/bash

#
# Generate Test Certificates for iOS E2E Testing
#
# Creates self-signed certificates that can be used for testing
# the certificate handling flow (not for real app distribution)
#

set -e

OUTPUT_DIR="${1:-.test-certs}"
CERT_PASSWORD="test-password-12345"
KEYCHAIN_PASSWORD="keychain-test-password"

echo "Generating test certificates in: $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Generate private key
echo "Step 1: Generating private key..."
openssl genrsa -out "$OUTPUT_DIR/private-key.pem" 2048

# Generate certificate signing request
echo "Step 2: Generating certificate signing request..."
openssl req -new -key "$OUTPUT_DIR/private-key.pem" \
    -out "$OUTPUT_DIR/cert.csr" \
    -subj "/C=US/ST=CA/L=SF/O=Test/CN=E2E Test Certificate"

# Generate self-signed certificate
echo "Step 3: Generating self-signed certificate..."
openssl x509 -req -days 365 \
    -in "$OUTPUT_DIR/cert.csr" \
    -signkey "$OUTPUT_DIR/private-key.pem" \
    -out "$OUTPUT_DIR/cert.pem"

# Create PKCS#12 bundle (p12)
echo "Step 4: Creating PKCS#12 bundle..."
openssl pkcs12 -export \
    -out "$OUTPUT_DIR/cert.p12" \
    -inkey "$OUTPUT_DIR/private-key.pem" \
    -in "$OUTPUT_DIR/cert.pem" \
    -password "pass:${CERT_PASSWORD}"

# Create dummy provisioning profile
echo "Step 5: Creating dummy provisioning profile..."
cat > "$OUTPUT_DIR/test.mobileprovision" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Name</key>
    <string>E2E Test Provisioning Profile</string>
    <key>AppIDName</key>
    <string>E2E Test App</string>
    <key>UUID</key>
    <string>$(uuidgen)</string>
    <key>TeamIdentifier</key>
    <array>
        <string>TESTTEAM</string>
    </array>
    <key>ApplicationIdentifierPrefix</key>
    <array>
        <string>TESTTEAM</string>
    </array>
</dict>
</plist>
EOF

# Create credentials JSON for upload
echo "Step 6: Creating credentials JSON..."
cat > "$OUTPUT_DIR/credentials.json" <<EOF
{
  "p12": "$(base64 < "$OUTPUT_DIR/cert.p12")",
  "p12Password": "${CERT_PASSWORD}",
  "keychainPassword": "$(echo -n "${KEYCHAIN_PASSWORD}" | base64)",
  "provisioningProfiles": [
    "$(base64 < "$OUTPUT_DIR/test.mobileprovision")"
  ]
}
EOF

echo ""
echo "✓ Test certificates generated successfully!"
echo ""
echo "Files created:"
echo "  - private-key.pem: Private key"
echo "  - cert.pem: Certificate"
echo "  - cert.p12: PKCS#12 bundle (password: ${CERT_PASSWORD})"
echo "  - test.mobileprovision: Dummy provisioning profile"
echo "  - credentials.json: JSON for API upload"
echo ""
echo "Usage with controller:"
echo "  curl -X POST http://localhost:4444/api/builds/submit \\"
echo "    -H 'X-API-Key: your-api-key' \\"
echo "    -F 'source=@project.zip' \\"
echo "    -F 'platform=ios' \\"
echo "    -F 'certs=@${OUTPUT_DIR}/credentials.json'"
echo ""
echo "⚠️  Note: These are self-signed test certificates."
echo "   They cannot be used for real App Store distribution."
echo ""
