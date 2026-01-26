# Expo Free Agent Worker Installer

One-command installer for the Expo Free Agent Worker macOS app. This package downloads, verifies, and configures the Free Agent Worker on your Mac to accept distributed iOS/Android builds.

## Installation

```bash
npx expo-free-agent
```

That's it! The installer will:

1. Check system requirements (macOS 14+, Apple Silicon, Xcode, Tart)
2. Download the latest Free Agent Worker app
3. Install to `/Applications/FreeAgent.app`
4. Prompt for controller URL and API key
5. Register your worker with the controller
6. Launch the app and optionally add to Login Items

## Requirements

- macOS 14.0 (Sonoma) or newer
- Apple Silicon (M1/M2/M3)
- Xcode (for iOS builds)
- Tart (VM management - installer can install this for you)
- 10GB+ free disk space (50GB+ recommended for VMs)

## Command Line Options

```bash
# Install with specific controller URL
npx expo-free-agent --controller-url https://my-controller.com

# Install with API key (skip prompt)
npx expo-free-agent --api-key sk-your-api-key-here

# Skip launching the app after installation
npx expo-free-agent --skip-launch

# Force reinstall even if already installed
npx expo-free-agent --force

# Verbose output for debugging
npx expo-free-agent --verbose
```

## What Gets Installed

- **App**: `/Applications/FreeAgent.app`
- **Config**: `~/Library/Application Support/FreeAgent/config.json`
- **Login Item**: Optional, added via System Settings

## Configuration

After installation, your configuration is saved to:

```
~/Library/Application Support/FreeAgent/config.json
```

Default configuration:

```json
{
  "controllerURL": "https://your-controller.com",
  "apiKey": "sk-...",
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

You can reconfigure at any time by:
- Re-running `npx expo-free-agent`
- Editing the JSON file directly
- Using the app's Settings interface

## Updating

To update to the latest version:

```bash
npx expo-free-agent --force
```

This will download and install the latest release.

## Uninstalling

To remove the Free Agent Worker:

```bash
npx expo-free-agent
```

Choose "Uninstall" from the menu.

Or manually:
1. Quit the app
2. Delete `/Applications/FreeAgent.app`
3. Delete `~/Library/Application Support/FreeAgent/`
4. Remove from Login Items in System Settings

## Troubleshooting

### "Controller unreachable"

The installer couldn't connect to your controller URL. This is usually fine - the configuration is saved and the worker will retry when launched. Check:

- Is the URL correct?
- Is the controller running?
- Are you on the correct network/VPN?

### "Xcode not found"

Install Xcode from the Mac App Store, then run:

```bash
sudo xcode-select -s /Applications/Xcode.app
```

### "Tart not found"

Tart is required for VM isolation. Install with:

```bash
brew install cirruslabs/cli/tart
```

The installer can do this automatically if you have Homebrew.

### "Only X GB free"

Free Agent needs disk space for:
- VM images (10-30GB each)
- Build outputs (1-5GB per build)
- Temporary files

Free up space or adjust VM settings in the config file.

### "App is not signed"

For development builds, the app may not be code-signed. This is expected. For production releases, the app will be signed and notarized by Expo.

## Development

### Local Testing

```bash
cd packages/worker-installer

# Install dependencies
bun install

# Run locally
bun run dev

# Build
bun run build

# Link for local testing
bun link
npx expo-free-agent
```

### Running Without npx

```bash
# Clone the repo
git clone https://github.com/expo/expo-free-agent.git
cd expo-free-agent/packages/worker-installer

# Install and run
bun install
bun run dev
```

## Architecture

The installer is a TypeScript CLI tool that orchestrates:

1. **Pre-flight checks** (`src/preflight.ts`) - Validates system requirements
2. **Download** (`src/download.ts`) - Fetches latest release from GitHub
3. **Installation** (`src/install.ts`) - Copies app to /Applications
4. **Registration** (`src/register.ts`) - Registers worker with controller
5. **Launch** (`src/launch.ts`) - Opens app and manages Login Items

## Security

- API keys are stored in `~/Library/Application Support/FreeAgent/config.json` with 0600 permissions (owner-only)
- Never log or display API keys
- App bundles are verified before installation
- Code signature verification (when available)

**Note**: For production deployments, consider using macOS Keychain for API key storage.

## Contributing

See the main [expo-free-agent](https://github.com/expo/expo-free-agent) repository for contribution guidelines.

## License

MIT
