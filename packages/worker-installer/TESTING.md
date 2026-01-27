# Testing Guide

Manual testing checklist for the `expo-free-agent` installer.

## Local Development Testing

### 1. Build and Basic Functionality

```bash
cd packages/worker-installer
bun install
bun run build
./dist/cli.js --help
./dist/cli.js --version
```

**Expected**: Help text and version displayed correctly.

### 2. Pre-flight Checks (Dry Run)

```bash
bun run dev --verbose
# Cancel when prompted to continue
```

**Expected**:
- [OK] macOS version detected
- [OK] Apple Silicon detected
- [OK/WARN] Xcode status
- [OK/WARN] Tart status
- [OK/WARN] Disk space reported
- [OK] Memory reported

### 3. Download Logic (Without Installation)

**Note**: Requires a GitHub release to exist first.

```bash
# This will fail until we create a release
bun run dev --verbose
```

**Expected**: Should fail gracefully with message about no release found.

## Creating Test Release

Before full testing, create a test release:

```bash
# Build the Swift app
cd free-agent
swift build -c release

# Package it
cd .build/release
tar -czf FreeAgent.app.tar.gz FreeAgent.app
shasum -a 256 FreeAgent.app.tar.gz > FreeAgent.app.tar.gz.sha256

# Create GitHub release
gh release create v0.1.0-test \
  FreeAgent.app.tar.gz \
  FreeAgent.app.tar.gz.sha256 \
  --title "Test Release v0.1.0" \
  --notes "Test release for installer development" \
  --draft
```

## Full Installation Test

### Prerequisites
- Clean macOS system (or new user account)
- GitHub release exists
- Controller running (or mock endpoint)

### Test: Fresh Installation

```bash
npx expo-free-agent --verbose
```

**Step-by-step verification**:

1. **Banner displays**
   - [ ] Version number shown
   - [ ] Clean formatting

2. **Pre-flight checks run**
   - [ ] All checks display with status
   - [ ] Colors: green (OK), yellow (WARN), red (ERROR)
   - [ ] Details shown for warnings/errors

3. **Tart installation offered (if missing)**
   - [ ] Prompt appears
   - [ ] Installation via Homebrew works
   - [ ] Or gracefully handles if declined

4. **Continue prompt**
   - [ ] User can proceed or cancel
   - [ ] Cancellation exits cleanly

5. **Download phase**
   - [ ] Latest release fetched from GitHub
   - [ ] Progress spinner shows download progress
   - [ ] Version number displayed
   - [ ] Success message

6. **Validation phase**
   - [ ] App bundle structure validated
   - [ ] Code signature checked (warns if unsigned)
   - [ ] Success message

7. **Installation phase**
   - [ ] Copies to /Applications/FreeAgent.app
   - [ ] Success message
   - [ ] File exists and has correct permissions

8. **Configuration prompts**
   - [ ] Controller URL prompt with default
   - [ ] API key prompt (masked input)
   - [ ] Values validated
   - [ ] Can cancel

9. **Connection test**
   - [ ] Attempts to reach controller
   - [ ] Success or warning displayed
   - [ ] Proceeds either way

10. **Worker registration**
    - [ ] POSTs to controller API
    - [ ] Worker ID returned and displayed
    - [ ] Or fails gracefully if endpoint missing

11. **Configuration saved**
    - [ ] File created at ~/Library/Application Support/FreeAgent/config.json
    - [ ] Permissions set to 0600
    - [ ] Content is valid JSON
    - [ ] Contains all required fields

12. **Launch prompt**
    - [ ] Asks to launch app
    - [ ] App opens if accepted
    - [ ] Menu bar icon appears

13. **Login Items prompt**
    - [ ] Asks to add to Login Items
    - [ ] Added to System Settings > Login Items if accepted
    - [ ] Or handles gracefully if fails

14. **Success message**
    - [ ] Next steps displayed
    - [ ] Configuration path shown
    - [ ] Documentation link shown

### Test: Update Existing Installation

```bash
npx expo-free-agent
```

**Expected**:
- [ ] Detects existing installation
- [ ] Shows current version
- [ ] Offers options: Update, Reconfigure, Uninstall, Cancel
- [ ] Update downloads and replaces app
- [ ] Preserves configuration

### Test: Reconfigure

```bash
npx expo-free-agent
# Choose "Reconfigure"
```

**Expected**:
- [ ] Loads existing configuration as defaults
- [ ] Prompts for new controller URL/API key
- [ ] Re-registers with controller
- [ ] Updates config file
- [ ] App not reinstalled

### Test: Uninstall

```bash
npx expo-free-agent
# Choose "Uninstall"
```

**Expected**:
- [ ] Stops running app
- [ ] Removes /Applications/FreeAgent.app
- [ ] Success message
- [ ] Config file remains (user choice to delete manually)

### Test: Force Reinstall

```bash
npx expo-free-agent --force --verbose
```

**Expected**:
- [ ] Skips "already installed" check
- [ ] Stops running app
- [ ] Downloads latest version
- [ ] Replaces existing app
- [ ] Preserves configuration

### Test: Automated Installation

```bash
npx expo-free-agent \
  --controller-url https://test.example.com \
  --api-key sk-test123 \
  --skip-launch \
  --verbose
```

**Expected**:
- [ ] No prompts
- [ ] Uses provided values
- [ ] Skips launch phase
- [ ] Success

## Error Scenario Testing

### Test: No Internet Connection

```bash
# Disable network
npx expo-free-agent --verbose
```

**Expected**:
- [ ] Download fails with clear error message
- [ ] Suggests troubleshooting steps
- [ ] Exits cleanly

### Test: Controller Unreachable

```bash
npx expo-free-agent \
  --controller-url https://nonexistent.example.com \
  --api-key sk-test
```

**Expected**:
- [ ] Connection test fails
- [ ] Warning displayed
- [ ] Configuration saved anyway
- [ ] Installation completes

### Test: Invalid API Key

```bash
npx expo-free-agent \
  --controller-url https://real-controller.com \
  --api-key invalid
```

**Expected**:
- [ ] Registration fails with 401/403
- [ ] Error message displayed
- [ ] Configuration saved anyway
- [ ] User can fix and retry

### Test: Insufficient Disk Space

```bash
# Create large file to fill disk
dd if=/dev/zero of=~/large-file bs=1g count=50
npx expo-free-agent --verbose
```

**Expected**:
- [ ] Pre-flight check warns about disk space
- [ ] User can choose to proceed
- [ ] Installation may fail if truly insufficient

### Test: Missing Xcode

```bash
# Temporarily rename Xcode
sudo mv /Applications/Xcode.app /Applications/Xcode.app.bak
npx expo-free-agent --verbose
sudo mv /Applications/Xcode.app.bak /Applications/Xcode.app
```

**Expected**:
- [ ] Pre-flight check warns about Xcode
- [ ] Provides installation instructions
- [ ] Allows proceeding without Xcode
- [ ] Installation completes

### Test: Cancelled Installation

```bash
npx expo-free-agent --verbose
# Press Ctrl+C during download
```

**Expected**:
- [ ] Cleanup temporary files
- [ ] Exit cleanly
- [ ] No partial installation

## Configuration File Testing

### Verify Config Structure

```bash
npx expo-free-agent \
  --controller-url https://test.com \
  --api-key sk-test

# Check config
cat ~/Library/Application\ Support/FreeAgent/config.json | jq .
```

**Expected**:
```json
{
  "controllerURL": "https://test.com",
  "apiKey": "sk-test",
  "workerID": "worker-abc123",
  "deviceName": "Your MacBook Pro",
  "pollIntervalSeconds": 30,
  "maxCPUPercent": 70,
  "maxMemoryGB": 8,
  "maxConcurrentBuilds": 1,
  "vmDiskSizeGB": 50,
  "reuseVMs": false,
  "cleanupAfterBuild": true,
  "autoStart": true,
  "onlyWhenIdle": false,
  "buildTimeoutMinutes": 120
}
```

### Verify File Permissions

```bash
ls -la ~/Library/Application\ Support/FreeAgent/config.json
```

**Expected**: `-rw-------` (600 permissions, owner-only)

## CLI Options Testing

### Test: Help

```bash
npx expo-free-agent --help
```

**Expected**: Usage information displayed

### Test: Version

```bash
npx expo-free-agent --version
```

**Expected**: `0.1.0`

### Test: Verbose Mode

```bash
npx expo-free-agent --verbose
```

**Expected**: More detailed output throughout process

### Test: Skip Launch

```bash
npx expo-free-agent --skip-launch
```

**Expected**: App not launched or added to Login Items

## Integration Testing

### Test: End-to-End with Real Controller

1. Start controller: `bun --cwd packages/controller dev`
2. Run installer: `npx expo-free-agent --verbose`
3. Verify worker shows up in controller dashboard
4. Submit a build job
5. Verify worker picks it up

### Test: Multiple Workers

1. Install on Machine A
2. Install on Machine B with same controller
3. Verify both workers registered
4. Submit multiple builds
5. Verify load distribution

## Performance Testing

### Test: Download Speed

```bash
time npx expo-free-agent --verbose
```

**Expected**: Download completes in reasonable time (< 2 minutes for ~30MB)

### Test: Installation Speed

**Expected**: Total installation time < 5 minutes on good connection

## Security Testing

### Test: API Key Not Logged

```bash
npx expo-free-agent \
  --controller-url https://test.com \
  --api-key sk-supersecret \
  --verbose 2>&1 | grep sk-supersecret
```

**Expected**: No matches (API key never appears in logs)

### Test: Config File Permissions

```bash
npx expo-free-agent \
  --controller-url https://test.com \
  --api-key sk-test

# Try to read as different user
sudo -u nobody cat ~/Library/Application\ Support/FreeAgent/config.json
```

**Expected**: Permission denied

## Cleanup After Testing

```bash
# Remove test installation
npx expo-free-agent
# Choose "Uninstall"

# Or manually
rm -rf /Applications/FreeAgent.app
rm -rf ~/Library/Application\ Support/FreeAgent

# Remove from Login Items
osascript -e 'tell application "System Events" to delete login item "FreeAgent"'
```

## Automated Testing

### Unit Tests (Future)

```bash
cd packages/worker-installer
bun test
```

**Tests needed**:
- Pre-flight check functions
- Configuration file management
- URL validation
- API key validation

### E2E Tests (Future)

```bash
cd packages/worker-installer
bun test:e2e
```

**Tests needed**:
- Full installation flow with mock release
- Update flow
- Uninstall flow
- Error scenarios

## Reporting Issues

When reporting bugs, include:
- macOS version: `sw_vers`
- Architecture: `uname -m`
- Installer version: `npx expo-free-agent --version`
- Full verbose output: `npx expo-free-agent --verbose 2>&1 | tee install.log`
- Config file (redact API key): `cat ~/Library/Application\ Support/FreeAgent/config.json`
