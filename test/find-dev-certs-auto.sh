#!/bin/bash
set -e

# Non-interactive certificate selection for automated testing

OUTPUT_ZIP="/tmp/test-certs-$(date +%s).zip"
TEMP_DIR="$(mktemp -d)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
BUNDLE_ID_OVERRIDE="${BUNDLE_ID:-}"
TEAM_ID="P8ZBH5878Q"

# Optional project dir arg
if [ -n "${1:-}" ]; then
    PROJECT_DIR="$1"
fi

APP_JSON="$PROJECT_DIR/app.json"
APP_CONFIG_TS="$PROJECT_DIR/app.config.ts"
APP_CONFIG_JS="$PROJECT_DIR/app.config.js"

get_bundle_id_from_expo_config() {
    local cmd=""
    if [ -x "$PROJECT_DIR/node_modules/.bin/expo" ]; then
        cmd="$PROJECT_DIR/node_modules/.bin/expo"
    elif command -v bunx >/dev/null 2>&1; then
        cmd="bunx --yes expo"
    elif command -v npx >/dev/null 2>&1; then
        cmd="npx --yes expo"
    else
        echo "" 
        return 0
    fi

    (cd "$PROJECT_DIR" && $cmd config --json 2>/dev/null) | \
        node -e "const fs=require('fs'); const p=JSON.parse(fs.readFileSync(0,'utf8')); console.log(p?.expo?.ios?.bundleIdentifier||'');"
}

decode_profile_json() {
    local profile="$1"
    local tmp=""

    if command -v openssl >/dev/null 2>&1; then
        tmp="$(mktemp)"
        if openssl smime -inform der -verify -noverify -in "$profile" -out "$tmp" >/dev/null 2>&1; then
            plutil -convert json -o - "$tmp" 2>/dev/null || true
            rm -f "$tmp"
            return
        fi
        rm -f "$tmp"
    fi

    security cms -D -i "$profile" 2>/dev/null | plutil -convert json -o - - 2>/dev/null || true
}

if [ -n "$BUNDLE_ID_OVERRIDE" ]; then
    BUNDLE_ID="$BUNDLE_ID_OVERRIDE"
elif [ -f "$APP_JSON" ]; then
    BUNDLE_ID=$(node -e "const fs=require('fs'); const p=JSON.parse(fs.readFileSync(process.argv[1],'utf8')); console.log(p.expo?.ios?.bundleIdentifier||'');" "$APP_JSON")
elif [ -f "$APP_CONFIG_TS" ] || [ -f "$APP_CONFIG_JS" ]; then
    BUNDLE_ID=$(get_bundle_id_from_expo_config)
else
    echo "Error: app.json or app.config.ts/js not found in $PROJECT_DIR" >&2
    exit 1
fi
if [ -z "$BUNDLE_ID" ]; then
    echo "Error: ios.bundleIdentifier not found in app config for $PROJECT_DIR" >&2
    exit 1
fi

echo "=== Automated iOS Certificate Export ===" >&2
echo "" >&2
echo "Using App Store profile for bundle ID: $BUNDLE_ID" >&2
echo "Bundle ID: $BUNDLE_ID" >&2
echo "" >&2

# Find the single matching App Store profile for the bundle ID
PROFILE_PATH=""
PROFILE_METHOD="app-store"
for profile in ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision; do
    if [ -f "$profile" ]; then
        json=$(decode_profile_json "$profile")
        if [ -z "$json" ]; then
            continue
        fi

        appid=$(echo "$json" | node -e "const p=JSON.parse(require('fs').readFileSync(0,'utf8')); console.log(p?.Entitlements?.['application-identifier']||'');")
        task_allow=$(echo "$json" | node -e "const p=JSON.parse(require('fs').readFileSync(0,'utf8')); console.log(Boolean(p?.Entitlements?.['get-task-allow']));")
        has_devices=$(echo "$json" | node -e "const p=JSON.parse(require('fs').readFileSync(0,'utf8')); console.log(Array.isArray(p?.ProvisionedDevices));")
        all_devices=$(echo "$json" | node -e "const p=JSON.parse(require('fs').readFileSync(0,'utf8')); console.log(Boolean(p?.ProvisionsAllDevices));")

        if [ "$appid" = "${TEAM_ID}.${BUNDLE_ID}" ]; then
            if [ "$task_allow" = "false" ] && [ "$has_devices" = "false" ] && [ "$all_devices" = "false" ]; then
                PROFILE_PATH="$profile"
                PROFILE_METHOD="app-store"
                break
            fi
            if [ -z "$PROFILE_PATH" ]; then
                PROFILE_PATH="$profile"
                PROFILE_METHOD="development"
            fi
        fi
    fi
done

if [ -z "$PROFILE_PATH" ]; then
    echo "Error: No provisioning profile found for $BUNDLE_ID" >&2
    exit 1
fi

echo "✓ Found provisioning profile: $(basename "$PROFILE_PATH") ($PROFILE_METHOD)" >&2

# Extract matching certificate fingerprint from profile
CERT_SHA=$(decode_profile_json "$PROFILE_PATH" | node -e "
const p=JSON.parse(require('fs').readFileSync(0,'utf8'));
const certs=p?.DeveloperCertificates||[];
if (!certs.length) { process.exit(1); }
const buf=Buffer.from(certs[0], 'base64');
const crypto=require('crypto');
console.log(crypto.createHash('sha1').update(buf).digest('hex').toUpperCase());
 " || true)

if [ -z "$CERT_SHA" ]; then
    echo "Error: Failed to extract certificate fingerprint from profile" >&2
    exit 1
fi

# Export matching certificate without prompting for password
# For automated testing, assumes keychain is unlocked
security export -t identities -f pkcs12 -P "" -o "$TEMP_DIR/cert.p12" -k /Library/Keychains/System.keychain "$CERT_SHA" 2>/dev/null || {
    security export -t identities -f pkcs12 -P "" -o "$TEMP_DIR/cert.p12" -k ~/Library/Keychains/login.keychain-db "$CERT_SHA" 2>/dev/null || {
        echo "Error: Could not export certificate without password" >&2
        echo "This test requires an unlocked keychain or passwordless export" >&2
        exit 1
    }
}

cp "$PROFILE_PATH" "$TEMP_DIR/profile.mobileprovision"

# Create cert bundle with empty password and provisioning profile
echo "" > "$TEMP_DIR/password.txt"

cd "$TEMP_DIR"
zip -q -r "$OUTPUT_ZIP" cert.p12 password.txt profile.mobileprovision 2>/dev/null || {
    echo "Error: Failed to create certificate bundle" >&2
    exit 1
}

echo "Certificate bundle created with 1 provisioning profile" >&2
echo "$OUTPUT_ZIP"

rm -rf "$TEMP_DIR"
