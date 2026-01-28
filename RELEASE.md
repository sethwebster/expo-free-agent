# Expo Free Agent - Release Process

## Quick Release (Repeatable)

### Local Release

```bash
cd free-agent
./release.sh 0.1.1
```

This single command:
1. ✅ Cleans previous builds
2. ✅ Builds Swift package
3. ✅ Creates app bundle
4. ✅ Code signs with your Developer ID
5. ✅ Creates tarball
6. ✅ Notarizes with Apple (or skips if not configured)

**Output**: `FreeAgent.app.tar.gz` - Ready for distribution

### Automated Release (GitHub Actions)

```bash
# Tag and push
git tag v0.1.1
git push origin v0.1.1
```

GitHub Actions will:
1. ✅ Build on macOS runner
2. ✅ Sign with certificate from secrets
3. ✅ Notarize with Apple
4. ✅ Create GitHub Release
5. ✅ Upload `FreeAgent.app.tar.gz` as asset

## One-Time Setup

### 1. Local Notarization Setup

Only needed once on your machine:

```bash
# Generate app-specific password at appleid.apple.com
# Then store credentials:
xcrun notarytool store-credentials "expo-free-agent" \
  --apple-id "your@email.com" \
  --team-id "P8ZBH5878Q" \
  --password "your-app-specific-password"
```

### 2. GitHub Actions Setup

Add these secrets to your repo (Settings → Secrets → Actions):

#### Required Secrets:

**CODESIGN_IDENTITY**
```
3EEF2BA2381B410F2F058155E088C178D6DD3ECA
```

**APPLE_CERTIFICATE_BASE64**
```bash
# Export your Developer ID certificate
security find-identity -v -p codesigning
# Open Keychain Access → My Certificates
# Right-click "Developer ID Application: Your Name"
# Export as .p12 with password
# Then encode:
base64 -i certificate.p12 | pbcopy
```

**APPLE_CERTIFICATE_PASSWORD**
```
<password you used when exporting .p12>
```

**KEYCHAIN_PASSWORD**
```
<any secure random string for temporary keychain>
```

**APPLE_ID**
```
your@email.com
```

**APPLE_TEAM_ID**
```
P8ZBH5878Q
```

**APPLE_APP_PASSWORD**
```
<app-specific password from appleid.apple.com>
```

## Release Workflow

### Patch Release (0.1.0 → 0.1.1)

```bash
# Local test
cd free-agent
./release.sh 0.1.1

# If successful, tag and push
git tag v0.1.1
git push origin v0.1.1
```

### Minor Release (0.1.x → 0.2.0)

```bash
# Update version in scripts if needed
cd free-agent
./release.sh 0.2.0

git tag v0.2.0
git push origin v0.2.0
```

### Manual Trigger (No Tag)

Go to GitHub Actions → Build Free Agent → Run workflow
- Enter version: `0.1.1`
- Click "Run workflow"

**Note**: Manual runs don't create GitHub releases, only upload artifacts.

## Version Management

Versions are passed as arguments to `release.sh`:

```bash
./release.sh 0.1.0  # Default
./release.sh 0.2.0  # Custom version
./release.sh 1.0.0  # Major release
```

### Base VM Image Versioning

The worker app uses a base VM image that must be versioned alongside app releases.

**Image naming**: `ghcr.io/sethwebster/expo-free-agent-base:VERSION`

**When to push a new base image**:
- Major/minor releases (0.1.x → 0.2.0, 0.2.x → 1.0.0)
- When VM dependencies change (Xcode, Expo SDK, system packages)
- Not needed for patch releases unless VM changed

**Push versioned base image**:

```bash
# Set auth (use gh token with write:packages scope)
export TART_REGISTRY_USERNAME=sethwebster
export TART_REGISTRY_PASSWORD="$(gh auth token)"

# Push with version tag AND :latest
/opt/homebrew/bin/tart push expo-free-agent-tahoe-26.2-xcode-expo-54 \
  ghcr.io/sethwebster/expo-free-agent-base:0.1.16 \
  ghcr.io/sethwebster/expo-free-agent-base:latest
```

**Then update code to reference versioned image**:

1. `free-agent/Sources/FreeAgent/main.swift:24`
2. `free-agent/Sources/FreeAgent/SettingsView.swift:47`
3. `free-agent/Sources/BuildVM/TartVMManager.swift:19`
4. `free-agent/Sources/WorkerCore/WorkerService.swift:220`
5. `packages/controller/.env.example:10`
6. `packages/controller/src/domain/Config.ts`

**Verify image is public and pullable**:

```bash
/opt/homebrew/bin/tart pull ghcr.io/sethwebster/expo-free-agent-base:0.1.16
```

### VM Agent Scripts Distribution

The VM agent scripts (bootstrap, run-job, monitor) have an auto-update system that downloads the latest version from GitHub releases.

**When to release VM scripts**:
- Every release (they auto-update, so always ship latest)
- When any script in `vm-setup/` changes

**Package and upload scripts**:

```bash
# Package scripts
cd vm-setup
./package-vm-scripts.sh

# Upload to same release as FreeAgent.app
gh release upload v0.1.22 vm-scripts.tar.gz
```

**How auto-update works**:
1. VM boots and runs `/usr/local/bin/free-agent-auto-update`
2. Script downloads `vm-scripts.tar.gz` from latest release
3. Compares with `/usr/local/etc/free-agent-version`
4. Updates scripts if newer
5. Execs bootstrap script

**Scripts included in package**:
- `free-agent-vm-bootstrap` - Certificate fetching and security lockdown
- `free-agent-run-job` - Build execution
- `vm-monitor.sh` - Heartbeat and telemetry
- `install-signing-certs` - Certificate installation
- `VERSION` - Current version number

**Note**: Auto-update is non-fatal. If it fails, VM continues with existing scripts.

## Verification

After release, verify the build works:

```bash
# Download from GitHub Release
curl -L -o FreeAgent.app.tar.gz \
  https://github.com/YOUR_ORG/expo-free-agent/releases/download/v0.1.0/FreeAgent.app.tar.gz

# Extract and test
tar -xzf FreeAgent.app.tar.gz

# Verify signature
codesign --verify --deep --strict FreeAgent.app

# Verify notarization
xcrun stapler validate FreeAgent.app

# Verify Gatekeeper acceptance
spctl --assess --type execute --verbose FreeAgent.app
```

Should see: `accepted source=Notarized Developer ID`

## Distribution

Once released, update the download URL:

**packages/worker-installer/src/download.ts**:
```typescript
const DOWNLOAD_URL = process.env.FREEAGENT_DOWNLOAD_URL ||
  'https://github.com/YOUR_ORG/expo-free-agent/releases/latest/download/FreeAgent.app.tar.gz';
```

## Troubleshooting

### Notarization Fails

```bash
# Check recent submissions
xcrun notarytool history --keychain-profile "expo-free-agent"

# Get detailed logs
xcrun notarytool log SUBMISSION_ID --keychain-profile "expo-free-agent"
```

Common issues:
- Missing hardened runtime: Fixed in `release.sh` (`--options runtime`)
- Invalid entitlements: Check `FreeAgent.entitlements`
- Unsigned binaries: All binaries signed in `release.sh`

### GitHub Actions Fails

- Check secrets are set correctly
- Verify certificate hasn't expired
- Check GitHub Actions logs for specific error

### Duplicate Certificates

If you see "ambiguous" error:

```bash
# List all certificates
security find-identity -v -p codesigning

# Delete old/duplicate ones in Keychain Access
# Or use specific hash in CODESIGN_IDENTITY
```

## Skip Notarization (Testing)

For local testing without notarization:

```bash
SKIP_NOTARIZE=1 ./release.sh 0.1.0
```

**Warning**: This build won't work on other machines (Gatekeeper will block it).

## Rollback

To rollback a release:

```bash
# Delete tag locally and remotely
git tag -d v0.1.1
git push origin :refs/tags/v0.1.1

# Delete GitHub Release manually in web UI
# or use gh CLI:
gh release delete v0.1.1
```

## Summary

**For each release**:
1. Update VERSION in `vm-setup/VERSION` to match release version
2. `./release.sh X.Y.Z` (local build + test)
3. `cd vm-setup && ./package-vm-scripts.sh` (package VM scripts)
4. `git tag vX.Y.Z && git push origin vX.Y.Z` (trigger CI)
5. Wait for GitHub Release to be created
6. `gh release upload vX.Y.Z vm-scripts.tar.gz` (upload VM scripts)
7. Test download and installation

That's it! Fully repeatable, automated process.
