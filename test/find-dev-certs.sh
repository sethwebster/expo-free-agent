#!/bin/bash
#
# find-dev-certs.sh
#
# Interactive script to discover, export, and package iOS developer certificates
# for use in E2E testing with real code signing.
#
# Usage: ./test/find-dev-certs.sh
# Output: Prints path to certs.zip (last line of output)
#

set -e

echo "=== iOS Certificate Finder ===" >&2
echo >&2

# Find all iOS signing identities
IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null | grep -E "iPhone|Apple Development|Apple Distribution" || true)

if [ -z "$IDENTITIES" ]; then
  echo "❌ No iOS signing certificates found in keychain" >&2
  echo "   Please ensure you have iOS development/distribution certificates installed" >&2
  exit 1
fi

# Parse identities into array
IFS=$'\n' read -rd '' -a IDENTITY_ARRAY <<<"$IDENTITIES" || true

echo "Found ${#IDENTITY_ARRAY[@]} iOS signing certificate(s):" >&2
echo >&2

# Display options
for i in "${!IDENTITY_ARRAY[@]}"; do
  echo "  $((i+1))) ${IDENTITY_ARRAY[$i]}" >&2
done
echo >&2

# Prompt user to select
if [ ${#IDENTITY_ARRAY[@]} -eq 1 ]; then
  SELECTED=0
  echo "Using: ${IDENTITY_ARRAY[0]}" >&2
else
  read -p "Select certificate (1-${#IDENTITY_ARRAY[@]}): " CHOICE >&2
  SELECTED=$((CHOICE - 1))

  if [ $SELECTED -lt 0 ] || [ $SELECTED -ge ${#IDENTITY_ARRAY[@]} ]; then
    echo "❌ Invalid selection" >&2
    exit 1
  fi

  echo "Selected: ${IDENTITY_ARRAY[$SELECTED]}" >&2
fi

# Extract certificate identity hash (first column before space)
IDENTITY_HASH=$(echo "${IDENTITY_ARRAY[$SELECTED]}" | awk '{print $1}')
IDENTITY_NAME=$(echo "${IDENTITY_ARRAY[$SELECTED]}" | awk -F'"' '{print $2}')
echo >&2

# Create temp directory for packaging
# Note: Cleanup is handled by the calling script (test-e2e-vm.sh)
TEMP_DIR=$(mktemp -d)

# Generate random password for p12
P12_PASSWORD=$(openssl rand -base64 32)

# Prompt for keychain password upfront
echo "Exporting certificate: $IDENTITY_NAME" >&2
echo "⚠️  Please enter your login keychain password (Never stored.)" >&2
echo >&2

# Read keychain password (disable echo for security)
read -s -p "Keychain password: " KEYCHAIN_PASSWORD >&2
echo >&2
echo >&2

if [ -z "$KEYCHAIN_PASSWORD" ]; then
  echo "❌ No password provided" >&2
  exit 1
fi

# Unlock keychain first
echo "Unlocking keychain..." >&2
if ! security unlock-keychain -p "$KEYCHAIN_PASSWORD" ~/Library/Keychains/login.keychain-db 2>/dev/null; then
  echo "❌ Failed to unlock keychain - incorrect password" >&2
  exit 1
fi

# Export certificate (keychain now unlocked, should not prompt)
echo "Exporting certificate..." >&2
if ! security export -k ~/Library/Keychains/login.keychain-db \
  -t identities \
  -f pkcs12 \
  -P "$P12_PASSWORD" \
  -o "$TEMP_DIR/cert.p12" \
  "$IDENTITY_NAME" 2>&1 | grep -v "security:" >&2; then
  echo "❌ Failed to export certificate" >&2
  exit 1
fi

echo "✓ Certificate exported successfully" >&2
echo >&2

# Find provisioning profiles
echo "Looking for provisioning profiles..." >&2
PROFILES_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"

if [ -d "$PROFILES_DIR" ]; then
  PROFILES=$(find "$PROFILES_DIR" -name "*.mobileprovision" 2>/dev/null || true)

  if [ -n "$PROFILES" ]; then
    PROFILE_COUNT=$(echo "$PROFILES" | wc -l | tr -d ' ')
    echo "✓ Found $PROFILE_COUNT provisioning profile(s)" >&2

    # Copy all profiles (controller can select appropriate one)
    while IFS= read -r profile; do
      cp "$profile" "$TEMP_DIR/"
    done <<< "$PROFILES"
  else
    echo "⚠️  No provisioning profiles found (build may fail if required)" >&2
  fi
else
  echo "⚠️  Provisioning profiles directory not found" >&2
fi

echo >&2

# Write password to file
echo "$P12_PASSWORD" > "$TEMP_DIR/password.txt"

# Create zip archive
echo "Creating certificate bundle..." >&2
cd "$TEMP_DIR"
zip -q -r certs.zip cert.p12 password.txt *.mobileprovision 2>/dev/null || \
  zip -q -r certs.zip cert.p12 password.txt

echo "✓ Certificate bundle created: $TEMP_DIR/certs.zip" >&2
echo >&2

# Output path for E2E script to use (STDOUT, not STDERR)
echo "$TEMP_DIR/certs.zip"
