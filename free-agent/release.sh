#!/bin/bash
set -e

# Expo Free Agent - Complete Release Pipeline
# Builds, signs, notarizes, and prepares for distribution

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
APP_NAME="FreeAgent"
BUNDLE_ID="com.expo.freeagent"
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-3EEF2BA2381B410F2F058155E088C178D6DD3ECA}"
NOTARIZE_PROFILE="expo-free-agent"

# Parse version from argument or use default
VERSION="${1:-0.1.0}"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Expo Free Agent Release Pipeline v${VERSION}${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Verify signing identity exists
if ! security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY"; then
    echo -e "${RED}❌ Error: Signing identity not found${NC}"
    echo "Expected: $SIGNING_IDENTITY"
    exit 1
fi

# Verify notarization credentials exist (unless skipping)
if [ "${SKIP_NOTARIZE}" != "1" ]; then
    if ! xcrun notarytool history --keychain-profile "$NOTARIZE_PROFILE" &>/dev/null; then
        echo -e "${YELLOW}⚠️  Warning: Notarization profile not found${NC}"
        echo "Setup required: xcrun notarytool store-credentials \"$NOTARIZE_PROFILE\" --apple-id YOUR_ID --team-id P8ZBH5878Q --password APP_PASSWORD"
        echo ""
        echo "Options:"
        echo "  1. Set up notarization (recommended for distribution)"
        echo "  2. Skip notarization (SKIP_NOTARIZE=1 ./release.sh)"
        echo ""
        read -p "Continue without notarization? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
        SKIP_NOTARIZE=1
    fi
fi

# Step 1: Clean
echo -e "${GREEN}[1/6]${NC} Cleaning previous builds..."
rm -rf .build/release .build/app ${APP_NAME}.app ${APP_NAME}.app.tar.gz
echo "      ✓ Cleaned"
echo ""

# Step 2: Build
echo -e "${GREEN}[2/6]${NC} Building Swift package (arm64)..."
swift build -c release --arch arm64 2>&1 | grep -E "(Building|Build complete|error:)" || true
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi
echo "      ✓ Build complete"
echo ""

# Step 3: Create app bundle
echo -e "${GREEN}[3/6]${NC} Creating app bundle..."
mkdir -p .build/app/${APP_NAME}.app/Contents/{MacOS,Resources}
cp .build/release/${APP_NAME} .build/app/${APP_NAME}.app/Contents/MacOS/
cp Info.plist .build/app/${APP_NAME}.app/Contents/

# Copy resources manually (no SPM resource bundle)
# Create FreeAgent_FreeAgent.bundle structure in Contents/Resources/
mkdir -p .build/app/${APP_NAME}.app/Contents/Resources/FreeAgent_FreeAgent.bundle/Resources
if [ -d "Sources/FreeAgent/Resources" ]; then
    cp -r Sources/FreeAgent/Resources/* .build/app/${APP_NAME}.app/Contents/Resources/FreeAgent_FreeAgent.bundle/Resources/
    echo "      ✓ Copied resources to FreeAgent_FreeAgent.bundle"
fi

# Update version
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" .build/app/${APP_NAME}.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" .build/app/${APP_NAME}.app/Contents/Info.plist

echo "      ✓ Bundle created"
echo ""

# Step 4: Code sign
echo -e "${GREEN}[4/6]${NC} Code signing..."
xattr -cr .build/app/${APP_NAME}.app
codesign --force --deep --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --entitlements ${APP_NAME}.entitlements \
    .build/app/${APP_NAME}.app

# Verify signature
codesign --verify --deep --strict .build/app/${APP_NAME}.app
echo "      ✓ Signed with: $SIGNING_IDENTITY"
echo ""

# Step 5: Create archive for notarization
echo -e "${GREEN}[5/6]${NC} Creating distribution archive..."
cp -r .build/app/${APP_NAME}.app ./

# Create zip for notarization (required by Apple)
ditto -c -k --keepParent ${APP_NAME}.app ${APP_NAME}.app.zip
ZIP_SIZE=$(du -sh ${APP_NAME}.app.zip | cut -f1)
echo "      ✓ Created ${APP_NAME}.app.zip (${ZIP_SIZE})"
echo ""

# Step 6: Notarize
if [ "${SKIP_NOTARIZE}" = "1" ]; then
    echo -e "${YELLOW}[6/6] Skipping notarization${NC}"
    echo "      ⚠️  App will show security warning on other machines"
    echo ""
else
    echo -e "${GREEN}[6/6]${NC} Notarizing with Apple..."
    echo "      This may take 1-5 minutes..."

    if xcrun notarytool submit ${APP_NAME}.app.zip \
        --keychain-profile "$NOTARIZE_PROFILE" \
        --wait 2>&1 | tee /tmp/notarize.log; then

        echo "      ✓ Notarization accepted"

        # Staple the ticket
        echo "      Stapling ticket..."
        xcrun stapler staple ${APP_NAME}.app

        echo "      ✓ Ticket stapled"
    else
        echo -e "${RED}      ✗ Notarization failed${NC}"
        echo ""
        echo "Check logs for details:"
        cat /tmp/notarize.log
        exit 1
    fi
    echo ""
fi

# Step 7: Create final tarball for distribution
echo -e "${GREEN}[7/7]${NC} Creating final distribution tarball..."
tar -czf ${APP_NAME}.app.tar.gz ${APP_NAME}.app
TAR_SIZE=$(du -sh ${APP_NAME}.app.tar.gz | cut -f1)
echo "      ✓ Created ${APP_NAME}.app.tar.gz (${TAR_SIZE})"
echo ""

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Release complete!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Archive (zip): ${APP_NAME}.app.zip (${ZIP_SIZE})"
echo "Artifact:      ${APP_NAME}.app.tar.gz (${TAR_SIZE})"
echo "Version:      ${VERSION}"
echo "Architecture: arm64 (Apple Silicon)"
if [ "${SKIP_NOTARIZE}" = "1" ]; then
    echo "Notarized:    No - Local use only"
else
    echo "Notarized:    Yes ✓"
fi
echo ""

# Verification
echo "Verification:"
if [ "${SKIP_NOTARIZE}" = "1" ]; then
    spctl --assess --type execute --verbose ${APP_NAME}.app 2>&1 | head -1 || true
else
    echo "  $(spctl --assess --type execute --verbose ${APP_NAME}.app 2>&1 | head -1)"
    echo "  $(xcrun stapler validate ${APP_NAME}.app 2>&1 | head -1)"
fi
echo ""

# Next steps
echo "Next steps:"
if [ "${SKIP_NOTARIZE}" = "1" ]; then
    echo "  1. Set up notarization: see ../docs/operations/notarization-setup.md"
    echo "  2. Run: ./release.sh ${VERSION}"
else
    echo "  1. Test locally: open ${APP_NAME}.app"
    echo "  2. Upload to GitHub: gh release create v${VERSION} ${APP_NAME}.app.tar.gz"
    echo "  3. Update download URL in packages/worker-installer/src/download.ts"
fi
echo ""
