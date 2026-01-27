# Expo Free Agent - Distribution Guide

## Requirements for Distribution

To distribute Free Agent to other machines, you need:

1. **Apple Developer Account** ($99/year)
2. **Developer ID Application Certificate**
3. **App Notarization** (required for macOS)

## Why These Are Required

**Code Signing**: macOS Gatekeeper blocks unsigned apps from running on other machines.

**Notarization**: Since macOS 10.15+, all distributed apps must be notarized by Apple.

**Entitlements**: Free Agent requires hypervisor access (`com.apple.vm.hypervisor`) which requires proper signing.

## Current State

- ✅ App builds and runs locally
- ⚠️ **Ad-hoc signed** - won't work on other machines
- ❌ Not notarized
- ✅ arm64 architecture (Apple Silicon)
- ❌ No Intel (x86_64) build yet

## Building for Local Development

```bash
cd free-agent
swift build -c release
.build/release/FreeAgent
```

This creates an ad-hoc signed binary that works **only on your machine**.

## Building for Distribution

### 1. Get Apple Developer Certificate

1. Join [Apple Developer Program](https://developer.apple.com/programs/)
2. Create a **Developer ID Application** certificate:
   - Open Xcode → Settings → Accounts
   - Select your Apple ID → Manage Certificates
   - Click "+" → Developer ID Application
3. Note your Team ID (found in Membership section)

### 2. Set Up Environment

```bash
# Find your signing identity
security find-identity -v -p codesigning

# Set environment variable
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

### 3. Build Signed Release

```bash
cd free-agent
./build-release.sh
```

This creates:
- `FreeAgent.app` - Signed app bundle
- `FreeAgent.app.tar.gz` - Distribution tarball

### 4. Notarize with Apple

```bash
# Submit for notarization
xcrun notarytool submit FreeAgent.app.tar.gz \
  --apple-id YOUR_APPLE_ID \
  --team-id YOUR_TEAM_ID \
  --password APP_SPECIFIC_PASSWORD \
  --wait

# Check status
xcrun notarytool history --apple-id YOUR_APPLE_ID --password APP_SPECIFIC_PASSWORD

# Once approved, staple the ticket
tar -xzf FreeAgent.app.tar.gz
xcrun stapler staple FreeAgent.app
tar -czf FreeAgent.app.tar.gz FreeAgent.app
```

**App-Specific Password**: Generate at [appleid.apple.com](https://appleid.apple.com) → Security → App-Specific Passwords

### 5. Verify Distribution

```bash
# Verify signature
codesign --verify --deep --strict FreeAgent.app

# Verify Gatekeeper will allow it
spctl --assess --type execute --verbose FreeAgent.app

# Verify notarization
stapler validate FreeAgent.app
```

Should see:
- `accepted source=Notarized Developer ID`

### 6. Upload for Distribution

Upload `FreeAgent.app.tar.gz` to:
- GitHub Releases
- Cloudflare Pages (current: `https://7ce3428f.expo-free-agent.pages.dev/`)
- Your own hosting

Update `packages/worker-installer/src/download.ts`:
```typescript
const DOWNLOAD_URL = 'https://your-cdn.com/FreeAgent.app.tar.gz';
```

## GitHub Actions (Automated)

The repo includes `.github/workflows/build-free-agent.yml` for automated builds on tag push.

**Required Secrets**:
- `APPLE_CERTIFICATE_BASE64` - Your Developer ID cert exported as base64
- `APPLE_CERTIFICATE_PASSWORD` - Password for the cert
- `KEYCHAIN_PASSWORD` - Temporary keychain password
- `CODESIGN_IDENTITY` - Full identity string
- `APPLE_ID` - Your Apple ID email
- `APPLE_TEAM_ID` - Your team ID
- `APPLE_APP_PASSWORD` - App-specific password

**Trigger a build**:
```bash
git tag v0.1.0
git push origin v0.1.0
```

## Universal Binary (arm64 + x86_64)

To support both Apple Silicon and Intel:

```bash
# Build both architectures
swift build -c release --arch arm64
swift build -c release --arch x86_64

# Create universal binary
lipo -create \
  .build/arm64-apple-macosx/release/FreeAgent \
  .build/x86_64-apple-macosx/release/FreeAgent \
  -output .build/universal/FreeAgent
```

**Note**: Swift Package Manager doesn't fully support universal binaries yet. May need Xcode project.

## Troubleshooting

### "App is damaged and can't be opened"
- App not notarized or signature invalid
- Solution: Notarize or remove quarantine: `xattr -dr com.apple.quarantine FreeAgent.app`

### "Developer cannot be verified"
- App signed but not notarized
- Solution: Complete notarization steps above

### "Operation not permitted" for hypervisor
- Missing entitlements or unsigned
- Solution: Sign with proper Developer ID and include entitlements

### Notarization fails
- Check logs: `xcrun notarytool log SUBMISSION_ID --apple-id YOUR_ID --password PASSWORD`
- Common issues:
  - Missing hardened runtime (`--options runtime`)
  - Invalid entitlements
  - Unsigned frameworks/binaries within app

## Cost Breakdown

- **Apple Developer Program**: $99/year (required)
- **Code signing**: Included
- **Notarization**: Free (included with developer account)
- **Total**: $99/year

## For Open Source Distribution

If you want others to contribute without paying $99:

1. **Maintainer signs releases** - Only release manager needs certificate
2. **CI builds for testing** - Ad-hoc sign for contributors (local only)
3. **Official releases only** - Signed/notarized builds via GitHub Releases

## Next Steps

1. Get Apple Developer certificate
2. Run `./build-release.sh` with `CODESIGN_IDENTITY` set
3. Notarize the app
4. Upload to hosting
5. Test installer: `npx @sethwebster/expo-free-agent-worker`

---

**TL;DR**: Current binary won't work on other machines. Need Apple Developer account ($99/year) for proper signing and notarization.
