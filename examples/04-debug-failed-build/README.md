# Example 4: Debug a Failed Build

Comprehensive guide to diagnosing and fixing build failures.

## Common Build Failures

1. **Dependency issues** - Missing or incompatible packages
2. **Code signing errors** - Invalid certificates or profiles
3. **Configuration errors** - Incorrect app.json or eas.json
4. **Resource exhaustion** - Out of memory or disk space
5. **Network failures** - Unable to download dependencies

## Debugging Workflow

```
Build Failed
    ↓
Get build logs
    ↓
Identify error type
    ↓
Apply fix
    ↓
Retry build
```

## Step 1: Retrieve Build Logs

```bash
# Get logs for specific build
expo-build logs build-abc123

# Or download full logs
expo-build download build-abc123 --logs-only

# View downloaded logs
cat ./expo-builds/build-abc123/build-logs.txt
```

**Key sections to check:**
- `[ERROR]` - Actual error messages
- `[WARN]` - Potential issues
- Exit code (non-zero = failure)

## Step 2: Identify Error Type

### Dependency Resolution Error

**Error in logs:**
```
npm ERR! code ERESOLVE
npm ERR! ERESOLVE unable to resolve dependency tree
npm ERR! Found: react@18.2.0
npm ERR! Could not resolve dependency: peer react@"^17.0.0"
```

**Diagnosis:** Version conflict between dependencies

**Fix:**
```bash
# Option 1: Update conflicting package
npm install package-name@latest

# Option 2: Use legacy peer deps
npm install --legacy-peer-deps

# Option 3: Override in package.json
{
  "overrides": {
    "react": "18.2.0"
  }
}
```

### Code Signing Error

**Error in logs:**
```
error: No certificate for team 'ABC123XYZ' matching 'Apple Distribution'
CodeSign error: code signing is required
```

**Diagnosis:** Missing or expired signing certificate

**Fix:**
```bash
# Check certificate validity
security find-identity -v -p codesigning

# Export from Xcode
# Xcode → Preferences → Accounts → Manage Certificates → Export

# Or regenerate in Apple Developer portal
# developer.apple.com → Certificates → Create new

# Update build submission:
expo-build submit \
  --cert ./new-cert.p12 \
  --provision ./new-profile.mobileprovision
```

### Native Module Build Error

**Error in logs:**
```
Undefined symbols for architecture arm64:
  "_OBJC_CLASS_$_RCTImageLoader"
ld: symbol(s) not found for architecture arm64
```

**Diagnosis:** Missing native dependency or linker error

**Fix:**
```bash
# Install pods (iOS)
cd ios && pod install && cd ..

# Clean and rebuild
cd ios
xcodebuild clean
cd ..

# Or update pods
cd ios && pod update && cd ..

# Resubmit build
expo-build submit --platform ios
```

### Configuration Error

**Error in logs:**
```
Error: app.json: Invalid "ios.bundleIdentifier"
Must match pattern: ^[a-zA-Z0-9.-]+$
```

**Diagnosis:** Invalid configuration in app.json

**Fix:**
```json
{
  "expo": {
    "ios": {
      "bundleIdentifier": "com.company.app"
    }
  }
}
```

### Memory Error

**Error in logs:**
```
FATAL ERROR: Ineffective mark-compacts near heap limit
Allocation failed - JavaScript heap out of memory
```

**Diagnosis:** Build process ran out of memory

**Fix:**
```bash
# Increase Node memory limit
export NODE_OPTIONS="--max-old-space-size=4096"

# Or optimize build:
# - Reduce bundle size
# - Split large files
# - Remove unused dependencies

# Resubmit
expo-build submit
```

### Timeout Error

**Error in logs:**
```
Build exceeded maximum time limit of 30 minutes
Process terminated
```

**Diagnosis:** Build took too long

**Fix:**
```bash
# Increase timeout
expo-build submit --timeout 60

# Or optimize:
# - Use build cache
# - Pre-download dependencies
# - Parallelize tasks
```

## Step 3: Advanced Debugging

### Enable Verbose Logging

```bash
# Submit with verbose output
expo-build submit --verbose

# Shows:
# - Detailed upload progress
# - Build environment details
# - Complete error stack traces
```

### Inspect Build Environment

Add debug script to pre-build:

```bash
#!/bin/bash
# .expo-build/debug.sh

echo "=== Build Environment ==="
echo "Node: $(node --version)"
echo "npm: $(npm --version)"
echo "Bun: $(bun --version)"
echo "Xcode: $(xcodebuild -version)"
echo "Ruby: $(ruby --version)"
echo "CocoaPods: $(pod --version)"

echo "=== System Info ==="
echo "macOS: $(sw_vers -productVersion)"
echo "Arch: $(uname -m)"
echo "Memory: $(sysctl -n hw.memsize | awk '{print $0/1024/1024/1024 " GB"}')"
echo "Disk: $(df -h / | awk 'NR==2 {print $4 " available"}')"

echo "=== Installed Packages ==="
npm list --depth=0

echo "=== Environment Variables ==="
env | grep -i expo
```

### Reproduce Locally

```bash
# Clone build environment
git clone https://github.com/your-repo/app.git
cd app

# Use exact Node version
nvm use $(cat .nvmrc)

# Install exact dependencies
npm ci

# Run build locally
npx eas build --platform ios --local
```

### Check Worker Status

```bash
# Via controller web UI
open http://controller:3000

# Check worker health
curl http://controller:3000/api/workers

# Expected response:
# {
#   "workers": [{
#     "id": "worker-001",
#     "status": "online",
#     "builds": 0,
#     "lastSeen": "2024-01-28T10:15:23Z"
#   }]
# }
```

## Step 4: Common Fixes

### Fix: Missing .gitignore

**Problem:** Uploading `node_modules/` increases build time and fails

**Solution:**

```bash
# Create .gitignore
cat > .gitignore <<EOF
node_modules/
.expo/
dist/
build/
*.log
.DS_Store
EOF

# Remove from git
git rm -r --cached node_modules/
git commit -m "Remove node_modules"
```

### Fix: Stale Dependencies

**Problem:** `package-lock.json` out of sync with `package.json`

**Solution:**

```bash
# Remove lockfile and node_modules
rm package-lock.json
rm -rf node_modules/

# Reinstall
npm install

# Commit new lockfile
git add package-lock.json
git commit -m "Update dependencies"
```

### Fix: Platform-Specific Code

**Problem:** iOS-specific code breaking Android build

**Solution:**

```javascript
// Before (breaks on Android)
import { NativeModules } from 'react-native';
const { AppleModule } = NativeModules;

// After (platform check)
import { Platform, NativeModules } from 'react-native';
const AppleModule = Platform.OS === 'ios' ? NativeModules.AppleModule : null;
```

### Fix: Expo Config Plugin Issues

**Problem:** Custom config plugin causing build failure

**Solution:**

```bash
# Prebuild to inspect generated native code
npx expo prebuild --platform ios

# Check ios/ directory
cat ios/MyApp/Info.plist

# Fix plugin in app.json
{
  "expo": {
    "plugins": [
      [
        "expo-custom-plugin",
        {
          "option": "value"
        }
      ]
    ]
  }
}
```

## Step 5: Debug Checklist

Before retrying build:

```
- [ ] Build logs reviewed
- [ ] Error message identified
- [ ] Root cause determined
- [ ] Fix applied locally
- [ ] Local build succeeds
- [ ] Dependencies updated
- [ ] Configuration validated
- [ ] Tests pass
- [ ] Ready to retry
```

## Step 6: Retry Build

```bash
# Clean retry
expo-build submit --clean

# With fixes
git add .
git commit -m "Fix: [description of fix]"
expo-build submit
```

## Step 7: Monitor Progress

```bash
# Watch build in real-time
expo-build tail build-abc123

# Expected output:
# [10:15:23] Installing dependencies...
# [10:16:45] Building native code...
# [10:18:12] Signing application...
# [10:19:30] ✅ Build complete!
```

## Debugging Tools

### Local Debugging

```bash
# Metro bundler with debugging
npx expo start --dev-client

# Run on simulator
npx expo run:ios

# View logs
npx react-native log-ios
```

### Remote Debugging

```bash
# Connect to worker VM (if enabled)
ssh worker@worker-ip

# View build logs in real-time
tail -f /tmp/build-abc123/logs.txt

# Check processes
ps aux | grep eas
```

## Pro Tips

1. **Always check logs first** - Don't guess, read the error
2. **Google the exact error** - Usually someone else hit it
3. **Reproduce locally** - Faster iteration than remote builds
4. **Keep builds small** - Exclude unnecessary files
5. **Version lock dependencies** - Use exact versions in package.json
6. **Test incrementally** - Don't change 10 things at once
7. **Document fixes** - Future you will thank you

## Common Error Patterns

| Error Pattern | Likely Cause | Quick Fix |
|---------------|--------------|-----------|
| `ERESOLVE` | Dependency conflict | `npm install --legacy-peer-deps` |
| `CodeSign error` | Cert/profile issue | Regenerate certificates |
| `Undefined symbols` | Missing native dep | `pod install` |
| `heap out of memory` | Large bundle | Increase `NODE_OPTIONS` |
| `timeout` | Slow build | Increase timeout or optimize |
| `permission denied` | File permissions | `chmod +x script.sh` |

## When to Escalate

Contact support if:
- Error persists after 3 retry attempts
- Error message is completely unclear
- Worker appears hung (no progress for >10 minutes)
- Suspect infrastructure issue (not code-related)

## Resources

- [Troubleshooting Guide](../../docs/operations/troubleshooting.md)
- [Error Reference](../../docs/reference/errors.md)
- [Build Logs Explained](../../docs/operations/build-logs.md)
- [Expo Troubleshooting](https://docs.expo.dev/build-reference/troubleshooting/)

---

**Time to fix:** 10 minutes - 2 hours (depends on issue)
**Skill level:** Intermediate to Advanced
