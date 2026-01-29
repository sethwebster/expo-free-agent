# ADR-0004: Never Manipulate Quarantine Attributes on Notarized Apps

**Status:** Accepted

**Date:** 2026-01-27 (Commits 16916ef, 77b1c7e, de5ba00 rejected; 0317032 adopted correct approach)

## Context

Notarized apps downloaded from the internet get `com.apple.quarantine` extended attribute. First launch triggers Gatekeeper validation flow:
1. User double-clicks app
2. Gatekeeper checks quarantine attribute
3. Contacts Apple's notarization servers
4. Validates ticket matches code signature
5. Shows "downloaded from internet" dialog
6. User clicks "Open"
7. Gatekeeper removes quarantine attribute
8. App launches

Initial installation was showing "app is damaged" dialog despite valid notarization. Natural impulse: remove quarantine attribute to bypass the dialog.

## Decision

**Never manipulate quarantine attributes. Trust macOS Gatekeeper.**

Reject all attempted "fixes":
- ❌ `xattr -d com.apple.quarantine` (removes attribute)
- ❌ `xattr -cr` (clears all attributes)
- ❌ `spctl --add` (adds to Gatekeeper allowlist)
- ❌ `lsregister -kill -r` (resets Launch Services)

These commands break the notarization validation flow and make the problem worse.

## Consequences

### Positive

- **Notarization works:** Gatekeeper validates ticket correctly
- **Security preserved:** macOS protection mechanisms function as designed
- **Simpler code:** Removed ~50 lines of quarantine manipulation
- **Auto-removes quarantine:** Gatekeeper handles attribute removal after validation
- **Audit compliance:** Respects enterprise security policies
- **User trust:** App shows proper "downloaded from internet" dialog (expected behavior)

### Negative

- **First launch dialog:** User sees "downloaded from internet, are you sure?" prompt
  - **This is correct behavior** for internet-downloaded apps
  - Required by macOS security model
  - Assures user app is notarized

## Why Manipulation Made It Worse

Removing quarantine attribute before Gatekeeper validation:
1. Prevents ticket validation (Gatekeeper skips check)
2. Triggers Launch Services corruption detection
3. Marks app as "damaged" in Launch Services cache
4. Shows "damaged app" error instead of quarantine dialog

The "damaged" error is **worse** than the quarantine dialog because:
- No "Open anyway" option
- Requires command-line recovery
- Looks like malware to users

## Root Cause

The "damaged app" error was caused by **code signature corruption** during extraction/installation (see ADR-0003), not quarantine attributes.

Fixing signature preservation (native tar + ditto) eliminated the problem. Quarantine attribute manipulation was addressing symptoms, not root cause.

## Exception: Non-Interactive Environments

In **automated CI/CD** or **testing** environments where user interaction is impossible:
- Use `xattr -d com.apple.quarantine` after installation
- Document why automation requires this
- Only in controlled environments, never in installer

This project's installer does **not** do this - users are expected to launch manually.

## Platform Security Philosophy

**Work with platform security mechanisms, not against them:**
- Gatekeeper exists to protect users
- Notarization provides cryptographic proof of author
- Quarantine attribute is part of that security model
- Bypassing it undermines user protection

When macOS shows security prompts, **fix the underlying issue**, don't suppress the prompt.

## References

- Failed attempts documented: `docs/operations/gatekeeper.md` (What We Tried section)
- Correct implementation: `packages/worker-installer/src/install.ts` (no xattr manipulation)
- Apple documentation: [Gatekeeper](https://support.apple.com/en-us/HT202491), [Notarization](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
