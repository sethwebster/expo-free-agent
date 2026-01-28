# Code Review: Gatekeeper Bypass Strategy

**Date**: 2026-01-27
**Reviewer**: Claude Code Review
**Files Reviewed**:
- `/Users/sethwebster/Development/expo/expo-free-agent/packages/worker-installer/src/install.ts`
- `/Users/sethwebster/Development/expo/expo-free-agent/cli/src/commands/start.ts`
- `/Users/sethwebster/Development/expo/expo-free-agent/cli/src/commands/worker.ts`
- `/Users/sethwebster/Development/expo/expo-free-agent/packages/worker-installer/src/download.ts`
- `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/build-release.sh`

---

## Executive Summary

**The app IS properly signed and notarized.** Verified on disk:
```
Authority=Developer ID Application: Seth Webster (P8ZBH5878Q)
Notarization Ticket=stapled
spctl assessment: accepted, source=Notarized Developer ID
```

The problem is NOT the app signature. The problem is the **distribution and installation flow** which corrupts or bypasses the notarization trust chain.

---

## Red Critical Issues

### 1. FUNDAMENTAL MISUNDERSTANDING: Quarantine Is Not The Enemy

**Location**: All three files - `install.ts:61-68`, `start.ts:24-34`, `worker.ts:65-75`

**Problem**: You're removing quarantine BEFORE Gatekeeper can validate notarization.

The quarantine attribute (`com.apple.quarantine`) is **required** for the notarization flow to work correctly. When Gatekeeper sees a quarantined file, it:
1. Checks if notarization ticket is stapled
2. If yes, validates against Apple's servers
3. If valid, **automatically removes quarantine** and allows execution

By removing quarantine programmatically BEFORE first launch, you're:
- Telling macOS "trust me, this is safe" without proof
- Triggering a DIFFERENT Gatekeeper path that requires manual user approval
- Making the notarization ticket worthless

**Impact**: Critical - This is why your app appears "damaged" despite being properly notarized.

**Solution**: DO NOT remove quarantine. Let Gatekeeper handle it naturally on first launch.

```typescript
// WRONG - What you're doing
execSync(`xattr -cr "${destPath}"`, { stdio: 'ignore' });
execSync(`xattr -d com.apple.quarantine "${destPath}" 2>/dev/null || true`, { stdio: 'ignore' });

// RIGHT - Do nothing. Gatekeeper handles notarized apps automatically.
// The ONLY case to remove quarantine is for unsigned/unnotarized dev builds.
```

### 2. `spctl --add` DOES NOT WORK HOW YOU THINK

**Location**: `install.ts:80-85`, `start.ts:29`, `worker.ts:70`

**Problem**: `spctl --add` is for adding **UNSIGNED** apps to a local whitelist. For notarized apps:
- It's unnecessary (Gatekeeper already trusts notarized apps)
- It requires admin privileges (fails silently without sudo)
- It doesn't persist across macOS updates
- Modern macOS versions (Catalina+) largely ignore this for downloaded apps

**Impact**: This command does nothing useful and may interfere with proper assessment.

**Solution**: Remove entirely. Notarized apps don't need this.

### 3. TARBALL EXTRACTION DESTROYS NOTARIZATION

**Location**: `download.ts:150-159`

**Problem**: The `tar` library may not preserve extended attributes including:
- `com.apple.quarantine` (expected on downloaded files)
- Resource forks
- Code signature data (if stored in xattrs)

When you extract with standard `tar.x()`, macOS sees a "newly created" file without provenance, triggering stricter checks.

**Impact**: Critical - This likely strips the notarization context.

**Solution**: Use native `tar` with `-p` (preserve) and verify xattrs post-extraction:
```bash
tar -xpzf archive.tar.gz
```

Or use macOS's Archive Utility which properly handles code-signed bundles.

### 4. NPM/NODE DOWNLOAD ADDS QUARANTINE WITHOUT PROVENANCE

**Location**: `download.ts:24-89`

**Problem**: When you download via `fetch()` in Node.js:
- The downloaded tarball gets quarantine attribute
- But it has NO connection to the original notarization
- When extracted, the app is "orphaned" from its notarization chain

**Impact**: The app loses its provenance chain from Apple's notarization servers.

**Solution**:
1. Download should preserve URL provenance in quarantine attribute
2. OR download via `curl` which properly sets quarantine metadata:
```bash
curl -L -O --xattr https://example.com/FreeAgent.app.tar.gz
```

### 5. SILENT ERROR SWALLOWING HIDES ROOT CAUSE

**Location**: Every `try/catch` block in `install.ts`, `start.ts`, `worker.ts`

**Problem**: You're catching errors and continuing, which means:
- You don't know which commands fail
- You don't know WHY they fail
- You can't diagnose the real issue

```typescript
// WRONG
try {
  execSync(`spctl --add "${destPath}"`, { stdio: 'ignore' });
} catch (error) {
  // Ignore errors - may require user approval or sudo
}
```

**Impact**: You've been debugging blind for 5+ iterations.

**Solution**: Log errors at minimum, fail loudly on critical operations:
```typescript
try {
  execSync(`spctl --add "${destPath}"`, { stdio: 'pipe' });
} catch (error) {
  console.warn(`spctl --add failed: ${error.message}`);
  // Continue only if this is truly optional
}
```

---

## Yellow Architecture Concerns

### 1. Quarantine Removal In 3 Different Places

**Location**: `install.ts`, `start.ts`, `worker.ts`

**Problem**: The same quarantine removal logic is duplicated in 3 files. This is:
- A DRY violation
- Maintenance burden (update one, forget others)
- Sign of unclear responsibility (who owns quarantine handling?)

**Solution**: Centralize in a single `gatekeeperUtils.ts`:
```typescript
export function prepareAppForLaunch(appPath: string): void {
  // Single source of truth for all Gatekeeper handling
}
```

### 2. `lsregister -u` Is Cargo Cult Programming

**Location**: `install.ts:87-92`, `start.ts:31`, `worker.ts:72`

**Problem**: `lsregister -u` unregisters an app from Launch Services. This is used when:
- Changing bundle identifiers
- Fixing corrupted associations

It has NOTHING to do with Gatekeeper or quarantine. You're running it hoping it helps, but it doesn't.

**Impact**: Wasted time, confusing debugging.

**Solution**: Remove. It's not related to your problem.

### 3. Chmod On Executable Is Usually Unnecessary

**Location**: `install.ts:70-78`

**Problem**: If the app was signed and packaged correctly, the executable permissions are preserved. Running `chmod 0o755` suggests the tarball or extraction is stripping permissions.

**Impact**: This is a symptom, not a solution. Fix the root cause.

**Solution**: Investigate WHY permissions are lost in the first place.

---

## Green DRY Opportunities

### 1. Quarantine Handling Duplicated 3x

Consolidate into shared utility:
```typescript
// packages/shared/src/gatekeeper.ts
export async function launchNotarizedApp(appPath: string): Promise<void> {
  // Single implementation
}
```

### 2. App Path Constants Duplicated

`/Applications/FreeAgent.app` appears in multiple files. Extract to config.

---

## Blue Maintenance Improvements

### 1. Add Verbose Mode For Debugging

```typescript
const verbose = process.env.FREEAGENT_VERBOSE === '1';

function log(msg: string) {
  if (verbose) console.log(`[gatekeeper] ${msg}`);
}
```

### 2. Add Pre-Installation Verification

Before copying to /Applications, verify the source app:
```typescript
function verifySourceApp(appPath: string): void {
  const result = execSync(`spctl --assess --type execute --verbose "${appPath}"`, { encoding: 'utf-8' });
  if (!result.includes('Notarized Developer ID')) {
    throw new Error(`App is not properly notarized: ${result}`);
  }
}
```

### 3. Add Post-Installation Verification

After installation, check what Gatekeeper sees:
```typescript
function verifyInstalledApp(appPath: string): void {
  const result = execSync(`spctl --assess --type execute --verbose "${appPath}"`, { encoding: 'utf-8' });
  console.log('Gatekeeper assessment:', result);
}
```

---

## White Nitpicks

### 1. Redundant Quarantine Removal

```typescript
execSync(`xattr -cr "${destPath}"`, { stdio: 'ignore' });
execSync(`xattr -d com.apple.quarantine "${destPath}" 2>/dev/null || true`, { stdio: 'ignore' });
```

`xattr -cr` already removes ALL xattrs recursively, including quarantine. The second command is redundant.

### 2. Shell Injection Risk

```typescript
execSync(`xattr -cr "${destPath}"`);
```

If `destPath` contains shell metacharacters, this is exploitable. Use `execFileSync` instead:
```typescript
execFileSync('xattr', ['-cr', destPath]);
```

---

## Checkmark Strengths

1. **Proper code signing**: The app IS properly signed with Developer ID and notarized
2. **Retry logic**: Download has exponential backoff retry
3. **Signature verification**: `verifyCodeSignature()` exists in download.ts
4. **Clean build script**: `build-release.sh` properly handles hardened runtime and entitlements

---

## THE ACTUAL FIX

Your problem is NOT Gatekeeper. Your problem is the **distribution chain**:

1. App is notarized (GOOD)
2. Downloaded via npm/fetch (LOSES PROVENANCE)
3. Extracted via Node's tar (MAY STRIP XATTRS)
4. Quarantine removed before first launch (BREAKS TRUST CHAIN)
5. Gatekeeper sees unknown binary, shows "damaged" dialog

### Correct Approach for Notarized Apps

**Option A: Trust the Notarization**
```typescript
export function installApp(sourcePath: string, force: boolean = false): void {
  // ... copy app to /Applications ...

  // DO NOT remove quarantine
  // DO NOT run spctl --add
  // DO NOT run lsregister

  // Just copy and let macOS handle first launch
}
```

On first launch, macOS will:
1. See quarantine attribute
2. Check notarization ticket (stapled)
3. Validate with Apple servers
4. Auto-remove quarantine
5. Launch app

**Option B: Use macOS Native Tools For Download**

Replace Node fetch with `curl`:
```typescript
execSync(`curl -L --xattr -o "${downloadPath}" "${url}"`);
```

The `--xattr` flag preserves extended attributes including proper quarantine metadata.

**Option C: DMG Distribution**

Instead of tarball, use a DMG:
- DMG files trigger proper Gatekeeper flow
- User drags to /Applications (macOS handles quarantine correctly)
- No programmatic quarantine manipulation needed

### Unresolved Questions

1. Does the npm tarball have the notarization ticket embedded, or does it get stripped during GitHub upload?
2. What quarantine metadata does the tarball have after npm download? (`xattr -l` on downloaded file)
3. What quarantine metadata does the extracted .app have? (`xattr -l` on extracted app)
4. What does `spctl --assess` show BEFORE you remove quarantine?
5. Have you tested launching the app WITHOUT any quarantine removal to see the ACTUAL Gatekeeper dialog?

### Debugging Steps

1. Download the tarball manually:
   ```bash
   curl -L -O https://github.com/.../FreeAgent.app.tar.gz
   xattr -l FreeAgent.app.tar.gz
   ```

2. Extract and check:
   ```bash
   tar -xpzf FreeAgent.app.tar.gz
   xattr -l FreeAgent.app
   ```

3. Check Gatekeeper assessment BEFORE any manipulation:
   ```bash
   spctl --assess --type execute --verbose FreeAgent.app
   ```

4. Try launching without ANY quarantine removal and observe the ACTUAL dialog macOS shows.

The "damaged" message specifically indicates Gatekeeper can't verify the app's integrity - which means either:
- Notarization ticket is missing/invalid after extraction
- Code signature was corrupted
- xattrs were stripped during packaging/extraction

---

## Summary

**Stop fighting Gatekeeper. It's trying to help you.**

The app is properly signed and notarized at the source. The problem is your distribution pipeline corrupts the trust chain. Remove all the quarantine manipulation code and investigate why the extracted app fails Gatekeeper assessment.
