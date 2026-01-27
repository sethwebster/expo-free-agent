# Changelog

All notable changes to the Expo Free Agent Worker Installer will be documented in this file.

## [0.1.0] - 2026-01-26

### Added
- Initial release of `expo-free-agent` installer package
- Pre-flight system checks (macOS, architecture, Xcode, Tart, disk space)
- Automatic download from GitHub Releases
- Installation to `/Applications/FreeAgent.app`
- Controller registration with API key authentication
- Configuration management in `~/Library/Application Support/FreeAgent/`
- Launch helper with Login Items support
- Interactive prompts for configuration
- Command-line options for automation
- Update/reinstall support
- Uninstall support
- Verbose logging mode

### Known Limitations
- Code signing verification is optional (not required for development builds)
- Controller registration endpoint (`/api/workers/register`) needs to be implemented
- Tart auto-installation requires Homebrew
- No auto-update mechanism (users must re-run installer)

## [Unreleased]

### Planned
- macOS Keychain integration for API key storage
- Auto-update mechanism using Sparkle framework
- Homebrew Cask distribution
- Pre-built VM template download support
- Better error recovery and rollback
- Progress bar for downloads
- Checksum verification
