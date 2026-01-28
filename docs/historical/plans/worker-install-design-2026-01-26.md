# Expo Free Agent Worker - Single-Command Installation Design

**Date:** 2026-01-26
**Status:** Design Proposal
**Goal:** `npx expo-free-agent-worker` bootstraps menu bar app, registers with controller, starts building

---

## Executive Summary

**Recommended approach:** npx script downloads pre-built notarized .app from GitHub Releases, installs to /Applications, launches setup wizard, registers with controller.

This mirrors the installation UX of Ollama, Postgres.app, and Docker Desktop while using npx as the entry point for discoverability.

---

## Comparison: How Others Handle This

| Project | Install Method | Binary Distribution | Config Flow | LaunchAgent |
|---------|---------------|--------------------|--------------| ------------|
| **Ollama** | `curl -fsSL ollama.ai/install.sh \| sh` | Pre-built binary from ollama.ai | CLI `ollama serve` auto-starts | Self-installs plist |
| **Docker Desktop** | DMG from docker.com | Signed/notarized .app | GUI setup wizard | Installs plist on first run |
| **Postgres.app** | Download .app, drag to Applications | Signed/notarized .app | GUI (click "Initialize") | User creates manually |
| **Homebrew** | `/bin/bash -c "$(curl ...)"` | Source compilation | None (CLI tool) | N/A |
| **Tart** | `brew install cirruslabs/cli/tart` | Pre-built via Homebrew | None (CLI tool) | N/A |

**Key insight:** Apps with persistent background services (Docker, Ollama) either self-install LaunchAgents or prompt user. Menu bar apps typically launch-at-login via macOS "Login Items" (no plist needed).

---

## Proposed Installation Command

```bash
npx expo-free-agent-worker
```

**Alternative names considered:**
- `npx @expo/free-agent` - Scoped, but longer
- `npx expo-worker` - Generic, could conflict
- `npx install-expo-worker` - Explicit but verbose

**Why npx?**
- Single command, no git clone
- Works cross-platform (for the installer, not the app)
- Familiar to Expo/React Native users
- Can be published to npm (or run from GitHub URL)

---

## Installation Flow (Step-by-Step)

### Phase 1: Pre-flight Checks

```
$ npx expo-free-agent-worker

Expo Free Agent Worker Installer v0.1.0
=======================================

Checking system requirements...
  [OK] macOS 14.0+ (detected: macOS 15.2)
  [OK] Apple Silicon (detected: arm64)
  [WARN] Xcode: Not found
         Required for building. Install from App Store.
  [OK] Tart: v2.15.0 (/opt/homebrew/bin/tart)
  [WARN] Template VM: Not found
         Will be created during setup.

Continue with installation? [Y/n]
```

**Checks performed:**
1. macOS version >= 14.0 (Sonoma) - required for Virtualization.framework
2. Architecture = arm64 (Apple Silicon required for Tart VMs)
3. Xcode presence (warn if missing, don't block)
4. Tart installation (offer to install via Homebrew if missing)
5. Disk space >= 100GB free (VMs need space)

### Phase 2: Binary Download

```
Downloading Free Agent Worker v0.1.0...
  Source: https://github.com/expo/expo-free-agent/releases/download/v0.1.0/FreeAgent.app.zip
  Size: 12.4 MB
  [====================] 100%

Verifying code signature...
  [OK] Signed by: Developer ID Application: Expo Inc
  [OK] Notarized by Apple

Installing to /Applications...
  [OK] Installed: /Applications/Free Agent.app
```

**Binary distribution strategy:**
- Pre-built .app bundle in GitHub Releases (or Expo CDN)
- Code-signed with Expo's Developer ID certificate
- Notarized with Apple for Gatekeeper approval
- Zipped for download (not DMG - simpler scripting)

**Why pre-built, not `swift build`?**
- Users don't need Xcode just to install the worker
- Consistent binary (no build-time variance)
- Faster installation (seconds vs minutes)
- Notarization requires Expo's signing identity anyway

### Phase 3: Controller Configuration

```
Configure controller connection:

Controller URL [https://expo-free-agent-controller.projects.sethwebster.com]:
> https://builds.mycompany.com

API Key:
> ****************************************

Testing connection...
  [OK] Controller reachable
  [OK] API key valid
  [OK] Worker registered (ID: worker-abc123)

Saving configuration to ~/Library/Application Support/FreeAgent/config.json
```

**Three authentication modes:**

| Mode | UX | Security | Prototype? |
|------|----|-----------| -----------|
| **Manual API Key** | Prompt for URL + key | Medium (key in config file) | YES |
| **OAuth/Browser** | Open browser, get token | High (short-lived tokens) | No (complex) |
| **Invite Code** | Controller generates 1-time code | Medium | No (extra infra) |

**Recommendation for prototype:** Manual API key entry. Simple, works now.

### Phase 4: VM Template Setup

```
Setting up build VM template...

This creates a macOS VM image with Xcode pre-installed.
The VM will be used for isolated builds.

Options:
  1. Use existing template: expo-free-agent-tahoe-26.2-xcode-expo-54
  2. Create new template (downloads macOS, installs Xcode - ~2 hours)
  3. Skip for now (configure later in Settings)

Choice [1]:

Checking template...
  [OK] Template exists: expo-free-agent-tahoe-26.2-xcode-expo-54
  [OK] Xcode version: 16.2
```

**Template strategies:**
- **Pre-baked (ideal):** Download pre-built VM image from Expo (large: 30-50GB)
- **User-built:** Script guides user through creating VM + installing Xcode
- **Deferred:** Skip during install, worker runs diagnostics and prompts later

**Recommendation:** Defer to separate `expo-free-agent setup-vm` command or let worker's built-in diagnostics guide user on first launch.

### Phase 5: Launch & Start at Login

```
Installation complete!

Starting Free Agent Worker...
  [OK] App launched (look for icon in menu bar)

Start at login?
  This adds Free Agent to your Login Items so it runs automatically.
  [Y/n]

  [OK] Added to Login Items

Next steps:
  1. Click the Free Agent icon in your menu bar
  2. Click "Start Worker" to begin accepting builds
  3. Run 'FreeAgent doctor' to verify VM setup

Documentation: https://docs.expo.dev/free-agent/
```

**Launch-at-login implementation:**
- Use macOS Login Items API (not LaunchAgent plist)
- SMAppService in Swift or `osascript` from installer
- Cleaner than plist: user can remove via System Settings

---

## Architecture Design

### What the npx Installer Does (TypeScript/Bun)

```
cli/src/commands/install-worker.ts
├── preflight.ts          # System checks (macOS, arch, disk, Xcode, Tart)
├── download.ts           # Download + verify binary from GitHub Releases
├── install.ts            # Unzip to /Applications, handle existing
├── configure.ts          # Prompt for controller URL/API key, write config
├── register.ts           # POST to /api/workers/register
├── launch.ts             # Open the .app, optionally add to Login Items
└── vm-setup.ts           # (Optional) Guide through VM template creation
```

**Package structure:**
```json
{
  "name": "expo-free-agent-worker",
  "bin": {
    "expo-free-agent-worker": "./dist/install.js"
  },
  "scripts": {
    "postinstall": "echo 'Run: npx expo-free-agent-worker'"
  }
}
```

### Where the Swift Binary Comes From

**Release process:**
1. Tag release in GitHub (e.g., `v0.1.0`)
2. GitHub Action builds Swift app:
   - `swift build -c release`
   - Code sign with Expo Developer ID
   - Notarize with Apple
   - Zip and upload to GitHub Releases
3. Installer downloads from: `https://github.com/expo/expo-free-agent/releases/download/v0.1.0/FreeAgent.app.zip`

**Signing/notarization (critical for distribution):**
```yaml
# .github/workflows/release.yml
- name: Build
  run: swift build -c release
- name: Sign
  run: codesign --sign "Developer ID Application: Expo Inc" .build/release/FreeAgent.app
- name: Notarize
  run: xcrun notarytool submit FreeAgent.app.zip --apple-id ... --wait
- name: Staple
  run: xcrun stapler staple FreeAgent.app
```

### Configuration Storage

**Location:** `~/Library/Application Support/FreeAgent/config.json`

```json
{
  "controllerURL": "https://builds.mycompany.com",
  "apiKey": "sk-...",
  "pollIntervalSeconds": 30,
  "maxCPUPercent": 70,
  "maxMemoryGB": 8,
  "maxConcurrentBuilds": 1,
  "vmDiskSizeGB": 50,
  "reuseVMs": false,
  "cleanupAfterBuild": true,
  "autoStart": true,
  "onlyWhenIdle": true,
  "buildTimeoutMinutes": 120,
  "workerID": "worker-abc123",
  "deviceName": "Seth's MacBook Pro"
}
```

**Security consideration:** API key in plaintext config file.

**Future improvement:** Store in macOS Keychain via `security` CLI or Swift's Keychain API. For prototype, plaintext is acceptable (same as `.env` files everywhere).

---

## Edge Cases & Error Handling

### What if Xcode not installed?

```
[WARN] Xcode not found.

Xcode is required for iOS builds. Options:
  1. Install Xcode from App Store (recommended)
  2. Install Xcode Command Line Tools only (limited builds)
  3. Continue anyway (worker will fail builds)

Choice [1]:

Opening App Store...
  After installing, run: sudo xcode-select -s /Applications/Xcode.app
  Then re-run this installer or start the worker.
```

**Don't block installation.** Worker's diagnostics (`FreeAgent doctor`) will catch this and guide user.

### What if Tart not installed?

```
[WARN] Tart not found.

Tart is required for VM isolation. Installing via Homebrew...

  $ brew install cirruslabs/cli/tart

  [OK] Tart v2.15.0 installed
```

**Auto-install via Homebrew** if `brew` is available. Otherwise, provide manual instructions.

### What if worker already installed?

```
Free Agent Worker is already installed.

Options:
  1. Update to v0.2.0 (current: v0.1.0)
  2. Reconfigure controller connection
  3. Uninstall
  4. Cancel

Choice [1]:
```

**Update flow:**
1. Stop running worker (gracefully)
2. Download new binary
3. Replace `/Applications/Free Agent.app`
4. Preserve config file (don't overwrite)
5. Restart worker

### What if controller unreachable?

```
Testing connection to https://builds.mycompany.com...
  [ERROR] Connection failed: ECONNREFUSED

Troubleshooting:
  - Is the controller running?
  - Is the URL correct?
  - Are you on the same network/VPN?

Retry? [Y/n]
```

**Don't fail installation.** Save config anyway, let user fix network and retry via app Settings.

---

## Security Considerations

### Binary Distribution

| Risk | Mitigation |
|------|-----------|
| Supply chain attack (malicious binary) | Code signing + notarization (Apple verifies) |
| Man-in-the-middle | HTTPS download from GitHub/Expo CDN |
| Binary tampering | Verify code signature before installation |
| Unsigned binary execution | macOS Gatekeeper blocks unsigned apps |

**Critical:** Without notarization, users must bypass Gatekeeper manually ("Open Anyway" in System Settings). This is unacceptable UX for a prototype demo.

### API Key Storage

| Risk | Mitigation |
|------|-----------|
| Key exposed in config file | File permissions 0600 (owner-only) |
| Key leaked to logs | Never log API key |
| Key reused across workers | Each worker gets unique key (future) |

**Prototype tradeoff:** Plaintext config is acceptable. Production should use Keychain.

### Auto-Update

**Not recommended for prototype.** Reasons:
- Complexity (Sparkle framework, update server)
- Security risk if update mechanism compromised
- Users can re-run `npx expo-free-agent-worker` to update

---

## Implementation Plan

### Phase 1: Pre-built Binary Distribution (1-2 days)

1. Create GitHub Actions workflow for Swift builds
2. Obtain Apple Developer ID certificate for code signing
3. Set up notarization (requires Apple Developer account with notarytool access)
4. Test: Build, sign, notarize, download, verify

### Phase 2: npx Installer Script (2-3 days)

1. Create new package `packages/worker-installer/` or add to CLI
2. Implement preflight checks (macOS, arch, disk, Xcode, Tart)
3. Implement download + signature verification
4. Implement configuration prompts
5. Implement worker registration API call
6. Implement app launch + Login Items

### Phase 3: Integration Testing (1 day)

1. Test on clean macOS (VM or fresh user account)
2. Test upgrade flow (existing installation)
3. Test error cases (no Xcode, no Tart, no network)
4. Document any manual steps

### Phase 4: Documentation (1 day)

1. Update README with installation instructions
2. Create troubleshooting guide
3. Document configuration options

---

## Recommended Install Command (Final)

```bash
# Primary (npm/npx)
npx expo-free-agent-worker

# Alternative (curl, like Ollama)
curl -fsSL https://expo.dev/install-worker | bash

# Alternative (Homebrew cask, future)
brew install --cask expo-free-agent
```

**Start with npx.** It's familiar, works today, and can be published to npm or run directly from GitHub:

```bash
# From GitHub (no npm publish needed)
npx github:expo/expo-free-agent/packages/worker-installer
```

---

## Unresolved Questions

1. **Apple Developer account:** Does Expo have notarytool access? Who signs the binary?
2. **Hosting:** GitHub Releases or Expo CDN for binary downloads?
3. **Update mechanism:** Prompt user to re-run npx, or build Sparkle-style auto-update?
4. **Template VM:** Pre-bake and host (50GB!), or guide user through creation?
5. **Keychain:** Worth the complexity for prototype, or defer to v2?

---

## Critique of Alternatives

### Alternative A: Homebrew Cask

```bash
brew install --cask expo-free-agent
```

**Pros:**
- Standard macOS distribution mechanism
- Auto-updates via `brew upgrade`
- Handles code signing verification

**Cons:**
- Requires Homebrew (not everyone has it)
- Cask submission process (tap or official)
- Configuration still needs manual setup

**Verdict:** Good for v2, not for quick prototype.

### Alternative B: Direct DMG Download

```bash
open https://github.com/expo/expo-free-agent/releases/download/v0.1.0/FreeAgent.dmg
```

**Pros:**
- Standard macOS UX
- No npm/npx dependency

**Cons:**
- Manual drag-to-Applications
- No automated configuration
- No preflight checks

**Verdict:** Fallback option if npx fails, but not primary.

### Alternative C: Swift Build on User Machine

```bash
npx expo-free-agent-worker  # clones repo, runs swift build
```

**Pros:**
- No code signing needed
- Always latest code

**Cons:**
- Requires Xcode (circular: installing worker to build, but need Xcode to build worker)
- Slow (minutes vs seconds)
- Build failures (Swift version, dependencies)

**Verdict:** Terrible UX. Reject.

### Alternative D: Electron Wrapper

**Pros:**
- Cross-platform (could run on Windows/Linux)
- Web-based UI
- npx could include entire app

**Cons:**
- Adds 200MB+ to download
- Can't access Virtualization.framework (macOS-only API)
- Defeats purpose of native Swift app

**Verdict:** Wrong tool for the job. Reject.

---

## Summary

**Best approach for prototype demo:**

1. **Command:** `npx expo-free-agent-worker`
2. **Binary:** Pre-built, signed, notarized .app from GitHub Releases
3. **Config:** Interactive prompts for controller URL + API key
4. **Registration:** Auto-register with controller during install
5. **Launch:** Start app, optionally add to Login Items
6. **VM Setup:** Defer to worker's built-in diagnostics/wizard

This gives the smoothest UX while being achievable in a week. Production hardening (Keychain, auto-update, Homebrew cask) can come later.
