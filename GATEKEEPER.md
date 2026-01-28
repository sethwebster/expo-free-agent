# Gatekeeper Fix Documentation

## Critical Issue Resolved

**Date**: 2026-01-27
**Impact**: Grant-critical - app installation was completely broken
**Status**: ✅ FIXED in v0.1.15 (worker-installer) and v0.1.7 (CLI)

## The Problem

Users installing FreeAgent.app via the npm installer consistently encountered:

```
"FreeAgent.app" is damaged and can't be opened. You should move it to the Trash.
```

This occurred on **every installation**, despite the app being:
- Properly code-signed with Developer ID certificate
- Notarized by Apple
- Stapled with valid notarization ticket
- Containing no restricted entitlements

### System Logs Showed

```
syspolicyd: GK evaluateScanResult: 3
syspolicyd: Prompt shown (1, 0), waiting for response
kernel: ASP: Security policy would not allow process: <pid>
```

## Root Cause Analysis

### Investigation Process

After 5+ failed attempts trying various approaches (removing quarantine attributes, using `spctl --add`, resetting Launch Services database), a comprehensive code review identified the actual issue.

### The Real Problem: npm `tar` Package

The npm `tar` package (used for extracting the `.tar.gz` distribution) was creating **AppleDouble files** (`._*`) during extraction:

```
/tmp/npm-test/FreeAgent.app/Contents/MacOS/._FreeAgent
/tmp/npm-test/FreeAgent.app/Contents/.__CodeSignature
```

These AppleDouble files **corrupted the code signature**, causing:

```bash
$ codesign --verify --deep --strict FreeAgent.app
FreeAgent.app: a sealed resource is missing or invalid
file added: /private/tmp/npm-test/FreeAgent.app/Contents/MacOS/._FreeAgent
```

### Why Our "Fixes" Made It Worse

Our attempts to fix the issue actually made things worse:

1. **Removing quarantine attributes** (`xattr -cr`, `xattr -d com.apple.quarantine`)
   - The quarantine attribute is **required** for Gatekeeper to validate notarization
   - By removing it before first launch, we bypassed Apple's trust validation
   - This triggered the "damaged app" path instead of the notarization flow

2. **Using `spctl --add`**
   - This command is for **unsigned** apps only
   - For notarized apps, it's unnecessary and fails silently
   - Modern macOS ignores this for downloaded apps

3. **Using Node's `cpSync`**
   - May not correctly preserve macOS-specific extended attributes
   - Can corrupt code signatures during copy operations

## The Solution

### Three Critical Changes

#### 1. Use Native `tar` Instead of npm `tar` Package

**File**: `packages/worker-installer/src/download.ts:154-160`

**Before**:
```typescript
import * as tar from 'tar';
// ...
await tar.x({
  file: tarballPath,
  cwd: extractDir
});
```

**After**:
```typescript
import { execFileSync } from 'child_process';
// ...
// CRITICAL: Use native tar instead of npm tar package.
// The npm tar package creates AppleDouble (._*) files that corrupt
// the code signature and break Gatekeeper validation.
// Native tar preserves the bundle integrity correctly.
execFileSync('tar', ['-xzf', tarballPath, '-C', extractDir], {
  stdio: 'pipe'
});
```

**Why**: Native macOS `tar` properly handles HFS+ metadata and doesn't create AppleDouble files.

#### 2. Use `ditto` Instead of `cpSync`

**File**: `packages/worker-installer/src/install.ts:58-77`

**Before**:
```typescript
cpSync(sourcePath, destPath, { recursive: true });
```

**After**:
```typescript
// CRITICAL: Use ditto instead of cpSync to preserve code signature and xattrs.
// Node's cpSync may not correctly preserve macOS-specific metadata required
// for Gatekeeper validation of notarized apps.
execFileSync('ditto', [sourcePath, destPath], { stdio: 'pipe' });

// Verify code signature is intact after copy
try {
  execFileSync('codesign', ['--verify', '--deep', '--strict', destPath], {
    stdio: 'pipe'
  });
} catch (error) {
  throw new Error(
    `Code signature verification failed after installation. The app bundle may be corrupted.`
  );
}
```

**Why**: `ditto` is Apple's tool specifically designed to copy files while preserving:
- Code signatures
- Extended attributes
- Resource forks
- ACLs and file flags

#### 3. Remove ALL Quarantine Manipulation

**Files**:
- `packages/worker-installer/src/install.ts:74-77`
- `cli/src/commands/start.ts:23-27`
- `cli/src/commands/worker.ts:65-68`

**Removed**:
```typescript
// BAD - Breaks notarization validation
execSync(`xattr -cr "${destPath}"`, { stdio: 'ignore' });
execSync(`xattr -d com.apple.quarantine "${destPath}"`, { stdio: 'ignore' });
execSync(`spctl --add "${destPath}"`, { stdio: 'ignore' });
execSync(`lsregister -u "${destPath}"`, { stdio: 'ignore' });
```

**Now**:
```typescript
// DO NOT remove quarantine attributes - Gatekeeper needs them to validate notarization.
// DO NOT run spctl --add - it's for unsigned apps, not notarized ones.
// DO NOT run lsregister - it's unrelated to Gatekeeper.
// The app is properly notarized; macOS will handle first-launch validation automatically.
```

**Why**: macOS Gatekeeper uses the quarantine attribute to:
1. Detect first launch of downloaded apps
2. Trigger notarization ticket validation
3. Auto-remove quarantine after successful validation
4. Allow subsequent launches without prompts

## Verification

### Before Fix

```bash
$ npm tar extraction
  → Creates ._FreeAgent and .__CodeSignature files

$ codesign --verify FreeAgent.app
  → FreeAgent.app: a sealed resource is missing or invalid

$ spctl --assess FreeAgent.app
  → FreeAgent.app: rejected

$ open FreeAgent.app
  → "FreeAgent.app is damaged and can't be opened"
```

### After Fix

```bash
$ native tar extraction
  → No AppleDouble files created

$ codesign --verify --deep --strict FreeAgent.app
  → FreeAgent.app: valid on disk
  → FreeAgent.app: satisfies its Designated Requirement

$ spctl --assess --type execute --verbose FreeAgent.app
  → FreeAgent.app: accepted
  → source=Notarized Developer ID

$ find FreeAgent.app -name "._*"
  → (no output - no AppleDouble files)

$ open FreeAgent.app
  → ✅ Launches successfully without any dialogs
```

## Technical Deep Dive

### How macOS Notarization Works

1. **Developer uploads app to Apple** for notarization
2. **Apple scans app** for malware and policy violations
3. **Notarization ticket is generated** and returned to developer
4. **Developer staples ticket** to app bundle using `xcrun stapler staple`
5. **User downloads app**, macOS adds `com.apple.quarantine` xattr
6. **User launches app**:
   - Gatekeeper sees quarantine attribute
   - Reads stapled notarization ticket
   - Validates ticket with Apple (first launch only)
   - Auto-removes quarantine on success
   - Launches app

### What We Were Doing Wrong

By removing the quarantine attribute before first launch, we:
- Skipped the notarization validation flow
- Made Gatekeeper treat it as a potentially modified app
- Triggered the "damaged app" security rejection

### AppleDouble Files Explained

AppleDouble is a file format for storing macOS metadata on non-HFS+ filesystems:
- Main file: `filename`
- Metadata file: `._filename`

The npm `tar` package creates these when extracting on macOS, but they:
- Add files not in the original code signature
- Cause signature verification to fail
- Trigger Gatekeeper rejection

Native `tar` handles macOS metadata natively without AppleDouble files.

## Dependencies Removed

The fix allowed us to remove these dependencies:

**packages/worker-installer/package.json**:
```json
{
  "dependencies": {
    "tar": "^7.4.3"  // ← REMOVED
  }
}
```

Package size reduced: **526.7 kB → 371.0 kB** (-30%)

## Testing Checklist

To verify a notarized app distribution works correctly:

### 1. Clean Test Environment
```bash
rm -rf /Applications/FreeAgent.app
rm -rf ~/.npm/_npx
```

### 2. Install App
```bash
npx @sethwebster/expo-free-agent-worker@latest
```

### 3. Verify Code Signature
```bash
codesign --verify --deep --strict /Applications/FreeAgent.app
# Should output nothing (success)
```

### 4. Check for AppleDouble Files
```bash
find /Applications/FreeAgent.app -name "._*" -o -name ".DS_Store"
# Should output nothing
```

### 5. Test Gatekeeper Assessment
```bash
spctl --assess --type execute --verbose /Applications/FreeAgent.app
# Should output: "accepted" and "source=Notarized Developer ID"
```

### 6. Launch App
```bash
open /Applications/FreeAgent.app
```

**Expected**: App launches immediately without any dialogs.

### 7. Check System Logs (Optional)
```bash
log show --predicate 'subsystem == "com.apple.syspolicyd"' --info --last 5m | grep -i "FreeAgent"
```

**Expected**: No "Prompt shown" or "damaged" messages.

## Key Learnings

### ✅ Do This

1. **Use native macOS tools** for app distribution:
   - Native `tar` for extraction
   - `ditto` for copying
   - `codesign` for verification

2. **Never manipulate quarantine attributes** on notarized apps
   - Let Gatekeeper handle the validation flow
   - Trust the notarization process

3. **Verify signatures after every operation**:
   - After extraction
   - After copying
   - Before distribution

4. **Test in clean environment**:
   - Always test with fresh installation
   - Clear npx cache between tests
   - Check system logs for Gatekeeper messages

### ❌ Don't Do This

1. **Don't use npm packages for macOS-specific operations**:
   - npm `tar` creates AppleDouble files
   - Node's `fs` may not preserve xattrs correctly

2. **Don't remove quarantine attributes programmatically**:
   - `xattr -cr` breaks notarization validation
   - `xattr -d com.apple.quarantine` bypasses security

3. **Don't use `spctl --add` on notarized apps**:
   - It's for unsigned apps only
   - Modern macOS ignores it for downloads
   - Requires sudo (fails silently)

4. **Don't swallow errors silently**:
   - Log all security-related operations
   - Fail loudly on signature verification errors
   - Don't use `|| true` on critical commands

## Related Issues

### If You See "damaged app" Again

1. **Check for AppleDouble files**:
   ```bash
   find /Applications/FreeAgent.app -name "._*"
   ```

2. **Verify code signature**:
   ```bash
   codesign --verify --deep --strict --verbose /Applications/FreeAgent.app
   ```

3. **Check extraction method**:
   - Are you using native `tar` or npm `tar`?
   - Are you using `ditto` or `cpSync`?

4. **Check for quarantine removal**:
   - Remove any `xattr -cr` calls
   - Remove any `xattr -d com.apple.quarantine` calls

### If Gatekeeper Still Prompts

1. **Check notarization ticket**:
   ```bash
   xcrun stapler validate /Applications/FreeAgent.app
   ```

2. **Check signing certificate**:
   ```bash
   codesign -dv --verbose=4 /Applications/FreeAgent.app
   ```

3. **Check for restricted entitlements**:
   ```bash
   codesign -d --entitlements :- /Applications/FreeAgent.app
   ```

4. **Clear Gatekeeper cache** (last resort):
   ```bash
   sudo spctl --master-disable
   sudo spctl --master-enable
   ```

## References

- [Apple TN3127: Inside Code Signing](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing)
- [Apple: Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Gatekeeper Documented Behavior](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web)

## Version History

- **v0.1.15** (worker-installer): Native tar extraction, ditto copying, no quarantine manipulation
- **v0.1.7** (CLI): Removed quarantine manipulation from launch commands
- **v0.1.14** (worker-installer): ❌ Attempted spctl --add (failed)
- **v0.1.13** (worker-installer): ❌ Attempted lsregister reset (failed)
- **v0.1.12** (app): Removed restricted VM entitlements
- Earlier versions: Various failed attempts to fix via quarantine removal

## Contributors

- Root cause analysis: neckbeard-code-reviewer agent
- Implementation: Claude (Sonnet 4.5)
- Verification: Seth Webster

---

**Last Updated**: 2026-01-27
**Status**: Production-ready ✅
