# ADR-0003: Use Native tar and ditto for Code Signature Preservation

**Status:** Accepted

**Date:** 2026-01-27 (Commit 0317032 after 5 failed attempts)

## Context

Worker app (`FreeAgent.app`) must be:
- Notarized by Apple for Gatekeeper approval
- Distributed via npm package (tarball extraction)
- Installed to `/Applications/` preserving code signature

npm's `tar` package and Node's `fs.cpSync()` were corrupting code signatures:
- `tar` package created AppleDouble files (`._*`) during extraction
- `cpSync` didn't preserve extended attributes
- Resulted in "code signature invalid" errors
- Gatekeeper showed "damaged app" dialog

5 failed attempts tried fixing symptoms:
1. Remove quarantine attribute after install → made it worse
2. Clear all xattrs + reset Launch Services → still broken
3. Add app to Gatekeeper allowlist with `spctl --add` → no effect
4. More aggressive quarantine manipulation → signature still corrupt

Root cause: Wrong tools for macOS-specific requirements.

## Decision

Use **native macOS tools** for security-critical operations:

**Extraction:** Replace `tar.x()` with native `tar` command
```typescript
// Before (broken)
import tar from 'tar'
await tar.x({ file: tarball, cwd: tmpDir })

// After (fixed)
execFileSync('tar', ['-xzf', tarball, '-C', tmpDir])
```

**Installation:** Replace `cpSync()` with `ditto` command
```typescript
// Before (broken)
fs.cpSync(source, dest, { recursive: true })

// After (fixed)
execFileSync('ditto', [source, dest])
```

**Verification:** Add post-install signature check
```typescript
execFileSync('codesign', [
  '--verify', '--deep', '--strict', appPath
])
```

**Never manipulate quarantine attributes** - let Gatekeeper handle validation flow.

## Consequences

### Positive

- **Signature preserved:** `codesign --verify` succeeds after extraction + installation
- **Gatekeeper happy:** App launches without "damaged" dialog
- **Smaller package:** Removed npm `tar` dependency, saved 155KB (30% reduction)
- **Correct behavior:** Respects macOS security model instead of fighting it
- **Early detection:** Post-install verification catches corruption immediately
- **Audit trail:** Verbose logging shows exact commands executed

### Negative

- **Platform-specific:** macOS-only solution (acceptable - worker is macOS-only)
- **External dependencies:** Assumes `tar`, `ditto`, `codesign` in PATH (safe on macOS)
- **Harder errors:** Installation fails loudly on corruption (correct behavior)
- **More code:** 3 `execFileSync` calls vs 2 library function calls

### Key Lesson Learned

**Fighting platform security mechanisms creates more problems than it solves.**

Initial attempts tried to "fix" Gatekeeper behavior with attribute manipulation. Correct solution was to use platform-native tools that respect security semantics.

## Security Benefits

Using `execFileSync` instead of `execSync` prevents shell injection:
```typescript
// Vulnerable to shell injection
execSync(`xattr -cr "${dest}"`)  // If dest contains `"; rm -rf /`, catastrophic

// Safe from injection
execFileSync('xattr', ['-cr', dest])  // dest treated as literal argument
```

## Verification Commands

Post-installation validation (run by installer):
```bash
# Verify code signature
codesign --verify --deep --strict /Applications/FreeAgent.app

# Check Gatekeeper assessment
spctl --assess --type execute --verbose /Applications/FreeAgent.app

# Verify no AppleDouble files
find /Applications/FreeAgent.app -name "._*"  # Should be empty
```

## References

- Implementation: `packages/worker-installer/src/download.ts`, `packages/worker-installer/src/install.ts`
- Comprehensive documentation: `docs/operations/gatekeeper.md`
- Testing checklist: `docs/operations/gatekeeper.md` (Verification section)
- Commit history: 5 failed attempts documented in `docs/operations/gatekeeper.md`
