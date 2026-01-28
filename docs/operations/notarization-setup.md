# Notarization Setup for Free Agent

Your app is now **properly signed** with your Developer ID certificate! ✅

To distribute it to other machines, you need to **notarize** it with Apple.

## One-Time Setup

### 1. Generate App-Specific Password

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in with your Apple ID
3. Go to **Security** → **App-Specific Passwords**
4. Click **Generate an app-specific password**
5. Name it: `expo-free-agent-notarization`
6. **Copy the password** (you'll need it in the next step)

### 2. Store Credentials in Keychain

```bash
xcrun notarytool store-credentials "expo-free-agent" \
  --apple-id "YOUR_APPLE_ID_EMAIL" \
  --team-id "P8ZBH5878Q" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

Replace:
- `YOUR_APPLE_ID_EMAIL` - Your Apple ID email
- `YOUR_APP_SPECIFIC_PASSWORD` - The password from step 1

This stores your credentials securely in your macOS keychain.

## Notarize the Build

Once credentials are stored, run:

```bash
cd free-agent

# Submit for notarization (takes 1-5 minutes)
xcrun notarytool submit FreeAgent.app.tar.gz \
  --keychain-profile "expo-free-agent" \
  --wait

# If successful, staple the ticket
tar -xzf FreeAgent.app.tar.gz
xcrun stapler staple FreeAgent.app
tar -czf FreeAgent.app.tar.gz FreeAgent.app

echo "✅ Ready for distribution!"
```

## Verify It Worked

```bash
# Check signature
codesign --verify --deep --strict FreeAgent.app

# Check notarization
xcrun stapler validate FreeAgent.app

# Test Gatekeeper acceptance
spctl --assess --type execute --verbose FreeAgent.app
```

Should see: `accepted source=Notarized Developer ID`

## Upload for Distribution

Once notarized, upload `FreeAgent.app.tar.gz` to:

```bash
# Option 1: GitHub Release (recommended)
gh release create v0.1.0 FreeAgent.app.tar.gz

# Option 2: Cloudflare Pages
# Upload to your Pages project
```

Then update the download URL in `packages/worker-installer/src/download.ts`

## Troubleshooting

### Check notarization status
```bash
xcrun notarytool history --keychain-profile "expo-free-agent"
```

### View submission logs
```bash
xcrun notarytool log SUBMISSION_ID --keychain-profile "expo-free-agent"
```

### Common errors:
- **"Invalid credentials"** - Regenerate app-specific password
- **"Notarization failed"** - Check logs for details (usually missing hardened runtime)
- **"Team ID not found"** - Use your team ID: `P8ZBH5878Q`

## Quick Script

Save this as `notarize.sh`:

```bash
#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "🚀 Notarizing Free Agent..."

xcrun notarytool submit FreeAgent.app.tar.gz \
  --keychain-profile "expo-free-agent" \
  --wait

echo "📌 Stapling notarization ticket..."
tar -xzf FreeAgent.app.tar.gz
xcrun stapler staple FreeAgent.app
tar -czf FreeAgent.app.tar.gz FreeAgent.app

echo "✅ Notarization complete!"
echo ""
echo "Next: Upload FreeAgent.app.tar.gz to GitHub Releases"
```

Then run:
```bash
chmod +x free-agent/notarize.sh
./free-agent/notarize.sh
```
