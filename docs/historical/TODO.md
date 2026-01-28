# TODO - Worker Installer

## Critical for Release

- [ ] Implement `/api/workers/register` endpoint in controller
- [ ] Test full installation flow on clean macOS system
- [ ] Obtain Apple Developer ID certificate for code signing
- [ ] Set up notarization workflow with Apple
- [ ] Create initial GitHub release with .app.tar.gz
- [ ] Test npx installation from npm registry
- [ ] Document controller setup for self-hosted deployments

## Code Signing & Distribution

- [ ] Sign app bundle with Developer ID certificate
- [ ] Notarize with Apple for Gatekeeper approval
- [ ] Staple notarization ticket to app bundle
- [ ] Add signature verification to installer
- [ ] Generate and verify SHA-256 checksums
- [ ] Test on macOS with Gatekeeper enabled

## Controller Integration

- [ ] Implement worker registration endpoint
  - POST `/api/workers/register`
  - Request: `{ name, capabilities, apiKey }`
  - Response: `{ workerID, message }`
- [ ] Add API key validation
- [ ] Add worker capability storage in database
- [ ] Add worker status tracking
- [ ] Document API authentication flow

## Installer Improvements

- [ ] Add progress bar for downloads (currently uses spinner)
- [ ] Implement checksum verification from release assets
- [ ] Add retry logic for network failures
- [ ] Better error messages with actionable steps
- [ ] Add dry-run mode for testing
- [ ] Support custom download URLs (for enterprise)
- [ ] Add telemetry opt-in/out
- [ ] Implement rollback on partial failure

## Security Enhancements

- [ ] Migrate API key storage to macOS Keychain
- [ ] Add API key rotation support
- [ ] Implement certificate pinning for controller API
- [ ] Add audit logging for sensitive operations
- [ ] Document security best practices

## VM Template Setup

- [ ] Create separate `expo-free-agent setup-vm` command
- [ ] Guide user through VM creation with Tart
- [ ] Pre-download macOS IPSW files
- [ ] Automate Xcode installation in VM
- [ ] Validate VM configuration
- [ ] Add VM template listing command
- [ ] Document manual VM setup process

## Testing

- [ ] Create automated test suite
- [ ] Add unit tests for all modules
- [ ] Add integration tests with mock controller
- [ ] Add E2E test with real installation
- [ ] Test on multiple macOS versions (14, 15)
- [ ] Test on different hardware (M1, M2, M3)
- [ ] Test upgrade path from previous versions
- [ ] Test error scenarios (no network, no disk space, etc.)

## Documentation

- [ ] Add architecture diagram
- [ ] Create video walkthrough
- [ ] Document troubleshooting steps
- [ ] Add FAQ section
- [ ] Document configuration options in detail
- [ ] Create deployment guide for enterprises
- [ ] Add contributing guide

## Distribution

- [ ] Publish to npm registry as `expo-free-agent`
- [ ] Create Homebrew Cask formula
- [ ] Add curl install script (like Ollama)
- [ ] Host binaries on Expo CDN (alternative to GitHub)
- [ ] Set up CDN for faster downloads
- [ ] Add download mirrors for reliability

## Future Features

- [ ] Auto-update mechanism using Sparkle
- [ ] Desktop notifications for build status
- [ ] Built-in diagnostics tool (`FreeAgent doctor`)
- [ ] Support for custom VM templates
- [ ] Multi-worker management from single machine
- [ ] Resource usage monitoring and limits
- [ ] Build queue visualization
- [ ] Remote worker management dashboard
- [ ] Support for GPU passthrough (future Tart feature)
- [ ] Windows/Linux worker support (via different VM tech)

## Known Issues

- [ ] Tart installation via Homebrew requires user to have Homebrew
- [ ] Code signature verification fails on unsigned development builds
- [ ] Login Items API uses deprecated osascript method
- [ ] No graceful handling of network timeouts
- [ ] Config file permissions not enforced on Windows (future support)
