# Expo Controller CLI - Usage Guide

## Quick Start

```bash
# 1. Install and build
cd cli
bun install
bun run build

# 2. Link globally (optional)
bun link

# 3. Configure controller URL
expo-controller config --set-url http://your-controller:3000

# 4. Submit a build
expo-controller submit ./my-expo-app \
  --cert ./certs/dist.p12 \
  --profile ./profiles/adhoc.mobileprovision
```

## Complete Workflow Example

### 1. Prepare Your Project

```bash
# Ensure you have:
# - Expo project with app.json/app.config.js
# - Signing certificate (.p12)
# - Provisioning profile (.mobileprovision)
# - Apple app-specific password (for notarization)
```

### 2. Submit Build

```bash
expo-controller submit ./my-expo-app \
  --cert ./certs/distribution.p12 \
  --profile ./profiles/adhoc.mobileprovision \
  --apple-id me@example.com \
  --apple-password "xxxx-xxxx-xxxx-xxxx"
```

Output:
```
✔ Project zipped (3.45 MB)
✔ Uploading to controller
✔ Build submitted successfully

Build ID: 550e8400-e29b-41d4-a716-446655440000

Track status: expo-controller status 550e8400-e29b-41d4-a716-446655440000
Download when ready: expo-controller download 550e8400-e29b-41d4-a716-446655440000
```

### 3. Check Status

Single check:
```bash
expo-controller status 550e8400-e29b-41d4-a716-446655440000
```

Watch mode (auto-updates):
```bash
expo-controller status 550e8400-e29b-41d4-a716-446655440000 --watch
```

Output:
```
Build Progress |████████████████████| Completed

Build completed successfully!
Duration: 18m 32s
Download: expo-controller download 550e8400-e29b-41d4-a716-446655440000
```

### 4. Download IPA

```bash
expo-controller download 550e8400-e29b-41d4-a716-446655440000
```

Custom output path:
```bash
expo-controller download 550e8400-e29b-41d4-a716-446655440000 -o ./builds/v1.0.0.ipa
```

Output:
```
✔ Build downloaded successfully

File: /Users/me/build.ipa
Size: 125.34 MB
```

### 5. List All Builds

```bash
expo-controller list
```

Output:
```
Recent Builds:

ID: 550e8400-e29b-41d4-a716-446655440000
  Status: completed
  Created: 1/23/2026, 2:30:45 PM
  Duration: 18m 32s

ID: 661f9511-f3ac-52e5-b827-557766551111
  Status: building
  Created: 1/23/2026, 3:15:20 PM

View details: expo-controller status <build-id>
```

## Command Reference

### submit

Submit an Expo project for building.

```bash
expo-controller submit <project-path> [options]
```

**Arguments:**
- `<project-path>` - Path to Expo project directory

**Options:**
- `--cert <path>` - Signing certificate (.p12)
- `--profile <path>` - Provisioning profile (.mobileprovision)
- `--apple-id <email>` - Apple ID for notarization
- `--apple-password <password>` - App-specific password

**Examples:**
```bash
# Minimal (just project)
expo-controller submit ./my-app

# With signing
expo-controller submit ./my-app --cert ./cert.p12 --profile ./adhoc.mobileprovision

# Full (with notarization)
expo-controller submit ./my-app \
  --cert ./cert.p12 \
  --profile ./adhoc.mobileprovision \
  --apple-id me@example.com \
  --apple-password "xxxx-xxxx-xxxx-xxxx"
```

**What gets zipped:**
- All project files
- Excludes: node_modules, .expo, .git, ios/Pods, android/build, .DS_Store

### status

Check build status.

```bash
expo-controller status <build-id> [options]
```

**Arguments:**
- `<build-id>` - Build ID to check

**Options:**
- `-w, --watch` - Watch progress and poll for updates

**Examples:**
```bash
# Single check
expo-controller status 550e8400-e29b-41d4-a716-446655440000

# Watch mode (updates every 5s)
expo-controller status 550e8400-e29b-41d4-a716-446655440000 --watch
```

**Status values:**
- `pending` - Waiting for worker
- `building` - Currently building
- `completed` - Build succeeded
- `failed` - Build failed

### download

Download a completed build.

```bash
expo-controller download <build-id> [options]
```

**Arguments:**
- `<build-id>` - Build ID to download

**Options:**
- `-o, --output <path>` - Output file path (default: ./build.ipa)

**Examples:**
```bash
# Default output (./build.ipa)
expo-controller download 550e8400-e29b-41d4-a716-446655440000

# Custom output
expo-controller download 550e8400-e29b-41d4-a716-446655440000 -o ./releases/v1.0.0.ipa
```

**Behavior:**
- Checks build is completed before downloading
- Confirms before overwriting existing files
- Shows file size after download

### list

List all builds.

```bash
expo-controller list [options]
```

**Options:**
- `-l, --limit <number>` - Limit results (default: 10)

**Examples:**
```bash
# Show 10 most recent
expo-controller list

# Show 25 most recent
expo-controller list --limit 25
```

### config

Manage CLI configuration.

```bash
expo-controller config [options]
```

**Options:**
- `--set-url <url>` - Set controller URL
- `--show` - Show current configuration

**Examples:**
```bash
# Show config
expo-controller config --show

# Set controller URL
expo-controller config --set-url http://my-controller:3000

# Reset to default (localhost)
expo-controller config --set-url http://localhost:3000
```

**Config location:** `~/.expo-controller/config.json`

## Error Handling

### Project not found
```
✖ Project path must be a directory
```

Fix: Provide valid directory path

### Not an Expo project
```
✖ Not a valid Expo project (missing app.json or app.config.js)
```

Fix: Run from Expo project root or specify correct path

### Build not ready
```
✖ Build is not ready (status: building)
```

Fix: Wait for build to complete or use `--watch` mode

### Controller unreachable
```
✖ Build submission failed
Failed to fetch: connect ECONNREFUSED 127.0.0.1:3000
```

Fix:
1. Verify controller is running
2. Check controller URL: `expo-controller config --show`
3. Update URL if needed: `expo-controller config --set-url http://correct-url:3000`

## Tips

### Watch build progress
```bash
# Instead of manually checking status:
expo-controller status <id> --watch

# This auto-updates every 5s with progress bar
```

### Chain commands
```bash
# Submit and immediately watch
BUILD_ID=$(expo-controller submit ./my-app | grep "Build ID:" | awk '{print $3}')
expo-controller status $BUILD_ID --watch
```

### Save build IDs
```bash
# Save for later
expo-controller submit ./my-app | tee build-log.txt

# Extract ID later
BUILD_ID=$(grep "Build ID:" build-log.txt | awk '{print $3}')
expo-controller download $BUILD_ID
```

### Multiple builds
```bash
# Submit multiple variants
for variant in development staging production; do
  expo-controller submit ./my-app-$variant
done

# List all
expo-controller list --limit 50
```

## Development

### Run from source
```bash
bun run dev submit ./my-app
```

### Build
```bash
bun run build
```

### Type check
```bash
bun run typecheck
```

### Link globally
```bash
bun link
# Now use 'expo-controller' from anywhere
```

### Unlink
```bash
bun unlink
```

## Architecture

```
┌─────────────────────────────────────────┐
│ Developer Machine                       │
│                                         │
│ $ expo-controller submit ./my-app       │
│           ↓                             │
│ ┌─────────────────────────────────────┐ │
│ │ CLI                                 │ │
│ │ - Validates project                 │ │
│ │ - Zips files (excludes node_modules)│ │
│ │ - Uploads to controller             │ │
│ │ - Returns build ID                  │ │
│ └──────────────┬──────────────────────┘ │
└────────────────┼─────────────────────────┘
                 │ HTTP POST (multipart/form-data)
                 ↓
┌──────────────────────────────────────────┐
│ Controller Server                        │
│ http://controller:3000                   │
│                                          │
│ POST /api/builds/submit                  │
│ GET  /api/builds/:id/status              │
│ GET  /api/builds/:id/download            │
│ GET  /api/builds                         │
└──────────────────────────────────────────┘
```

## Requirements

- Node.js 18+ or Bun
- Controller accessible via HTTP
- Valid Expo project structure
- Signing certs (for iOS builds)

## Security Notes

- Apple passwords transmitted to controller (use HTTPS in production)
- P12 files uploaded (ensure controller is trusted)
- Config file stored in home directory (readable by user)

In production:
- Always use HTTPS
- Never log sensitive credentials
- Consider OAuth instead of passwords
- Encrypt credentials at rest on controller
