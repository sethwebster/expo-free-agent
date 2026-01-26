# Worker Installer - Quick Start

The `expo-free-agent` npx installer package is now complete and ready for testing.

## What Was Built

A production-ready TypeScript CLI tool that automates:
- System requirement checks (macOS, Xcode, Tart, disk space)
- Downloading latest worker app from GitHub Releases
- Installing to `/Applications/FreeAgent.app`
- Registering with controller
- Configuration management
- Launch and Login Items setup

## Location

```
packages/worker-installer/
```

## Usage

### For End Users

```bash
# Install the worker
npx expo-free-agent

# With options
npx expo-free-agent \
  --controller-url https://builds.mycompany.com \
  --api-key sk-abc123 \
  --verbose
```

### For Development

```bash
cd packages/worker-installer

# Install dependencies
bun install

# Build
bun run build

# Test locally
bun run dev

# Run tests
./test-local.sh
```

## What's Next

### Critical Before Release

1. **Implement controller registration endpoint**
   - Add `POST /api/workers/register` to controller
   - Accept: `{ name, capabilities, apiKey }`
   - Return: `{ workerID, message }`

2. **Create first GitHub release**
   - Build Swift app: `cd free-agent && swift build -c release`
   - Package: `tar -czf FreeAgent.app.tar.gz .build/release/FreeAgent.app`
   - Create release: `gh release create v0.1.0 FreeAgent.app.tar.gz`
   - Test installer: `npx expo-free-agent --verbose`

3. **Test on clean system**
   - Create new macOS user account or use VM
   - Run: `npx expo-free-agent --verbose`
   - Verify all steps work

### Optional Enhancements

- Code signing and notarization (requires Apple Developer ID)
- Publish to npm (requires npm publish access)
- Add to Homebrew Cask
- Keychain integration for API keys
- Auto-update mechanism

## Documentation

- **README**: `/packages/worker-installer/README.md` - User documentation
- **IMPLEMENTATION**: `/packages/worker-installer/IMPLEMENTATION.md` - Technical details
- **TODO**: `/packages/worker-installer/TODO.md` - Follow-up tasks
- **CHANGELOG**: `/packages/worker-installer/CHANGELOG.md` - Version history

## Known Limitations

1. **Controller endpoint missing**: `/api/workers/register` not implemented yet
2. **No code signing**: Development builds are unsigned (expected)
3. **Requires Bun runtime**: Built for Bun, not Node.js
4. **No auto-update**: Users must re-run installer to update

See `packages/worker-installer/TODO.md` for complete list.

## Files Created

- `packages/worker-installer/` - Complete package
- `.github/workflows/release-worker.yml` - Release automation
- This file - Quick reference

## Testing Checklist

- [x] Package builds successfully
- [x] CLI shows help and version
- [ ] Pre-flight checks run on actual system
- [ ] Download from GitHub works (needs release)
- [ ] Installation to /Applications works
- [ ] Configuration prompts work
- [ ] Controller registration works (needs endpoint)
- [ ] Launch and Login Items work
- [ ] Reinstall/update flow works
- [ ] Uninstall works

## Quick Commands

```bash
# Build installer
cd packages/worker-installer && bun run build

# Test installer locally
cd packages/worker-installer && bun run dev --verbose

# Create GitHub release (when ready)
cd free-agent
swift build -c release
tar -czf ../FreeAgent.app.tar.gz .build/release/FreeAgent.app
cd ..
gh release create v0.1.0 FreeAgent.app.tar.gz

# Publish to npm (when ready)
cd packages/worker-installer
npm publish --access public
```
