# Example 1: Build iOS App for TestFlight

Complete end-to-end guide to building an Expo app and uploading to TestFlight.

## Prerequisites

- Expo Free Agent controller running
- Worker connected
- Apple Developer account
- App Store Connect app created
- Xcode installed (on worker Mac)

## Step 1: Configure Expo Project

```bash
# Create new Expo app (or use existing)
npx create-expo-app@latest MyTestFlightApp
cd MyTestFlightApp
```

### Update app.json

```json
{
  "expo": {
    "name": "My TestFlight App",
    "slug": "my-testflight-app",
    "version": "1.0.0",
    "ios": {
      "bundleIdentifier": "com.yourcompany.mytestflightapp",
      "buildNumber": "1"
    }
  }
}
```

## Step 2: Configure Build Credentials

Create `eas.json` for build configuration:

```json
{
  "build": {
    "production": {
      "ios": {
        "distribution": "store",
        "credentialsSource": "local"
      }
    }
  }
}
```

## Step 3: Export Certificates

Export your distribution certificate and provisioning profile from Xcode:

```bash
# Create credentials directory
mkdir -p ./credentials/ios

# Export from Xcode:
# 1. Open Xcode → Preferences → Accounts
# 2. Select your Apple ID → Manage Certificates
# 3. Right-click Distribution certificate → Export
# 4. Save as: credentials/ios/dist-cert.p12

# Export provisioning profile:
# 1. Open ~/Library/MobileDevice/Provisioning Profiles/
# 2. Find profile for your app (check bundle ID)
# 3. Copy to: credentials/ios/profile.mobileprovision
```

## Step 4: Set Environment Variables

```bash
# Set certificate password
export EXPO_IOS_DIST_P12_PASSWORD="your-certificate-password"

# Set Apple credentials for upload
export EXPO_APPLE_ID="your@apple.id"
export EXPO_APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
```

**Note:** Generate app-specific password at [appleid.apple.com](https://appleid.apple.com)

## Step 5: Submit Build

```bash
# Submit to Free Agent
expo-build submit \
  --platform ios \
  --profile production \
  --cert credentials/ios/dist-cert.p12 \
  --provision credentials/ios/profile.mobileprovision
```

**Expected output:**
```
📦 Bundling source code...
✓ Source bundled (15.2 MB)

📤 Uploading to controller...
✓ Upload complete

🎯 Build submitted!
   Build ID: build-abc123
   Job ID: job-xyz789

⏳ Waiting for worker assignment...
✓ Assigned to worker: worker-mac-mini-01

🔨 Building iOS app...
   [=====>                    ] 25% Resolving dependencies...
   [=========>                ] 45% Building native modules...
   [===============>          ] 75% Creating archive...
   [======================>   ] 95% Signing with certificate...
   [==========================] 100% Complete!

✅ Build completed in 12m 34s

📥 Downloading artifacts...
   ✓ MyTestFlightApp.ipa (54.2 MB)
   ✓ build-manifest.json (2 KB)
   ✓ build-logs.txt (245 KB)

💾 Saved to: ./expo-builds/build-abc123/
```

## Step 6: Verify Build

```bash
# Check the downloaded IPA
ls -lh ./expo-builds/build-abc123/

# Verify signing
codesign -dvv ./expo-builds/build-abc123/MyTestFlightApp.ipa

# Expected:
# Identifier=com.yourcompany.mytestflightapp
# Authority=Apple Distribution: Your Name (TEAM_ID)
```

## Step 7: Upload to TestFlight

### Option A: Using Transporter App

1. Open **Transporter** app (install from Mac App Store)
2. Drag `MyTestFlightApp.ipa` into Transporter
3. Click **Deliver**
4. Wait for upload to complete (~2-5 minutes)

### Option B: Using Command Line

```bash
# Install Transporter CLI
brew install --cask transporter

# Upload IPA
xcrun altool --upload-app \
  --type ios \
  --file ./expo-builds/build-abc123/MyTestFlightApp.ipa \
  --apiKey YOUR_API_KEY \
  --apiIssuer YOUR_ISSUER_ID

# Or use app-specific password:
xcrun altool --upload-app \
  --type ios \
  --file ./expo-builds/build-abc123/MyTestFlightApp.ipa \
  --username "$EXPO_APPLE_ID" \
  --password "$EXPO_APPLE_APP_SPECIFIC_PASSWORD"
```

**Expected output:**
```
2024-01-28 10:15:23.456 altool[1234:5678] No errors uploading './MyTestFlightApp.ipa'.
```

### Option C: Using Fastlane

```bash
# Install fastlane
brew install fastlane

# Create Appfile
cat > fastlane/Appfile <<EOF
apple_id "$EXPO_APPLE_ID"
app_identifier "com.yourcompany.mytestflightapp"
EOF

# Upload to TestFlight
fastlane pilot upload \
  --ipa ./expo-builds/build-abc123/MyTestFlightApp.ipa \
  --skip_waiting_for_build_processing
```

## Step 8: Configure TestFlight

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Select your app
3. Go to **TestFlight** tab
4. Wait for processing (5-15 minutes)
5. Once processed, click **Provide Export Compliance Information**
6. Answer questions (usually "No" for most apps)
7. Add internal or external testers
8. Testers receive email invitation

## Step 9: Monitor TestFlight Status

```bash
# Check upload status
fastlane pilot builds --app_identifier com.yourcompany.mytestflightapp

# Expected output:
# +---------+------------+----------+
# | Version | Build      | Status   |
# +---------+------------+----------+
# | 1.0.0   | 1          | Ready    |
# +---------+------------+----------+
```

## Troubleshooting

### Build Failed: Code Signing Error

**Error:**
```
error: No certificate for team 'TEAM_ID' matching 'Apple Distribution' found
```

**Solution:**
```bash
# Verify certificate is valid
security find-identity -v -p codesigning

# Check certificate is in keychain
openssl pkcs12 -in credentials/ios/dist-cert.p12 -nokeys -passin pass:YOUR_PASSWORD

# Ensure provisioning profile matches bundle ID
grep -A 1 "application-identifier" credentials/ios/profile.mobileprovision
```

### Build Failed: Provisioning Profile Expired

**Error:**
```
error: Provisioning profile has expired
```

**Solution:**
1. Go to [developer.apple.com](https://developer.apple.com/account/resources/profiles/list)
2. Regenerate provisioning profile
3. Download new profile
4. Replace `credentials/ios/profile.mobileprovision`
5. Resubmit build

### Upload Failed: Invalid Bundle

**Error:**
```
ERROR ITMS-90xxx: "Invalid Bundle"
```

**Solution:**
```bash
# Verify IPA structure
unzip -l MyTestFlightApp.ipa

# Check Info.plist
unzip -p MyTestFlightApp.ipa Payload/MyTestFlightApp.app/Info.plist | plutil -p -

# Common issues:
# - Missing CFBundleVersion
# - Invalid bundle identifier
# - Missing required architectures
```

### TestFlight Processing Stuck

**Issue:** Build stuck in "Processing" for >30 minutes

**Solution:**
1. Check App Store Connect status page
2. Wait up to 2 hours (Apple processing can be slow)
3. If still stuck after 2 hours, contact Apple Developer Support
4. Resubmit build if necessary

## Complete Script

Save as `build-and-upload.sh`:

```bash
#!/bin/bash
set -e

echo "🚀 Building for TestFlight..."

# 1. Submit build
expo-build submit \
  --platform ios \
  --profile production \
  --cert credentials/ios/dist-cert.p12 \
  --provision credentials/ios/profile.mobileprovision

# 2. Wait for build ID (from output)
BUILD_ID=$(expo-build list --latest --format json | jq -r '.id')

# 3. Wait for completion
expo-build wait $BUILD_ID

# 4. Download artifacts
expo-build download $BUILD_ID

# 5. Upload to TestFlight
echo "📤 Uploading to TestFlight..."
xcrun altool --upload-app \
  --type ios \
  --file ./expo-builds/$BUILD_ID/*.ipa \
  --username "$EXPO_APPLE_ID" \
  --password "$EXPO_APPLE_APP_SPECIFIC_PASSWORD"

echo "✅ Upload complete! Check App Store Connect."
```

Make executable and run:

```bash
chmod +x build-and-upload.sh
./build-and-upload.sh
```

## Next Steps

- **Add Beta Testers:** [TestFlight Guide](https://developer.apple.com/testflight/)
- **Monitor Crashes:** [App Store Connect Crashes](https://appstoreconnect.apple.com)
- **Automate Builds:** Set up CI/CD with this workflow
- **Production Release:** Submit for App Store review

## Resources

- [Apple TestFlight Documentation](https://developer.apple.com/testflight/)
- [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi)
- [Fastlane Pilot](https://docs.fastlane.tools/actions/pilot/)
- [Transporter Documentation](https://help.apple.com/itc/transporteruserguide/)

---

**Time to complete:** ~20 minutes (excluding TestFlight processing)
**Skill level:** Intermediate
