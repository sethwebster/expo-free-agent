# Local Setup Guide - Expo Free Agent

Complete guide for running Expo Free Agent locally for end-to-end testing.

## System Overview

**Components:**
- **Controller** - Central server managing build queue and distributing jobs
- **Worker (GUI)** - macOS menu bar app that picks up and executes builds
- **CLI Client** - Command-line tool for submitting builds and checking status

## Prerequisites

### Required Software

- **macOS** (for Worker GUI app)
- **Bun** - JavaScript runtime and package manager
  ```bash
  curl -fsSL https://bun.sh/install | bash
  ```
- **Swift** - For building the GUI worker (included with Xcode)
- **Git**

### Optional

- **Xcode Command Line Tools**
  ```bash
  xcode-select --install
  ```

## Step 1: Clone Repository

```bash
git clone <repository-url> expo-free-agent
cd expo-free-agent
```

## Step 2: Install Dependencies

```bash
# Install root dependencies
bun install

# Install controller dependencies
cd packages/controller
bun install
cd ../..

# Install CLI dependencies
cd cli
bun install
cd ..
```

## Step 3: Start Controller

The controller is the central server that manages the build queue.

```bash
cd packages/controller

# Set API key (minimum 16 characters)
export CONTROLLER_API_KEY="test-api-key-1234567890"

# Start controller
bun run start
```

**Expected output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚀 Expo Free Agent Controller
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📍 Server:   http://localhost:3000
📊 Web UI:   http://localhost:3000
🔌 API:      http://localhost:3000/api

💾 Database: ./data/controller.db
📦 Storage:  ./storage
🔐 API Key:  test-api...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Keep this terminal running.**

## Step 4: Build and Start Worker (GUI App)

The worker is a macOS menu bar app that picks up builds from the controller.

Open a **new terminal:**

```bash
cd free-agent

# Build the Swift app
swift build

# Start the GUI app
.build/debug/FreeAgent
```

**Expected output:**
```
Worker service starting...
✓ Registered with controller (ID: <worker-id>)
Worker service started
```

**Menu bar icon should appear** with a block pattern (⬛ above ⬛⬛⬛).

### Configure Worker

1. Click the menu bar icon
2. Click **"Settings..."**
3. Set configuration:
   - **Controller URL:** `http://localhost:3000`
   - **API Key:** `test-api-key-1234567890`
   - **Worker Name:** `Local Test Worker`
   - **Auto-start:** ✓ (checked)
4. Click **Save**

**Important:** The worker must be running to pick up builds.

## Step 5: Configure CLI Client

Open a **new terminal:**

```bash
cd cli

# Configure controller URL
bun run dev config set controller-url http://localhost:3000

# Set API key via environment variable
export EXPO_CONTROLLER_API_KEY="test-api-key-1234567890"

# Verify configuration
bun run dev config list
```

**Expected output:**
```
Configuration:
  Controller URL: http://localhost:3000
```

## Step 6: Submit Test Build

### Prepare Test Project

You need an Expo/React Native project to build. For testing, create a minimal project:

```bash
# In a separate directory
npx create-expo-app test-project
cd test-project

# Package for submission (creates tar.gz)
tar -czf ../test-project.tar.gz .
cd ..
```

### Submit Build

```bash
cd expo-free-agent/cli

export EXPO_CONTROLLER_API_KEY="test-api-key-1234567890"

bun run dev submit ../test-project.tar.gz
```

**Expected output:**
```
✓ Build submitted successfully

Build ID: <build-id>
Status: pending

Track status:
  expo-controller status <build-id>

Download when complete:
  expo-controller download <build-id>
```

## Step 7: Monitor Build Progress

### Check Menu Bar

The menu bar app shows active builds:

1. Click the menu bar icon
2. You should see:
   ```
   Status: Running
   ─────────────────
   Building IOS • 1m 23s
   ─────────────────
   Stop Worker
   ```

**Green dot appears** on icon when builds are active.

### Check via CLI

```bash
# List all builds
bun run dev list

# Check specific build status
bun run dev status <build-id>
```

### Monitor Controller Logs

In the controller terminal, you'll see:
```
[timestamp] POST /api/builds/submit
[timestamp] GET /api/workers/poll
[timestamp] Assigned build <id> to worker <worker-id>
```

### Monitor Worker Logs

The GUI app runs in background, but you can check process output:

```bash
# Check if worker is running
pgrep -fl FreeAgent

# View system logs (if worker logging is enabled)
log stream --predicate 'process == "FreeAgent"' --level debug
```

## Step 8: Download Completed Build

Once build status is `completed`:

```bash
bun run dev download <build-id>
```

Output file: `./<build-id>.ipa` (iOS) or `./<build-id>.apk` (Android)

## Full E2E Test Checklist

- [ ] Controller starts and shows API endpoint
- [ ] Worker GUI appears in menu bar
- [ ] Worker registers with controller
- [ ] CLI configuration set correctly
- [ ] Build submission succeeds
- [ ] Build appears in `list` command
- [ ] Build status changes: `pending` → `assigned` → `building` → `completed`
- [ ] Menu bar shows active build with elapsed time
- [ ] Green dot appears on menu bar icon
- [ ] Build completes successfully
- [ ] Build can be downloaded
- [ ] Downloaded file exists and is valid

## Troubleshooting

### Controller won't start

**Error:** `API key must be at least 16 characters`

**Fix:**
```bash
export CONTROLLER_API_KEY="test-api-key-1234567890"
```

### Worker can't register

**Error:** `Failed to register with controller`

**Causes:**
1. Controller not running - start controller first
2. Wrong URL - check Settings → Controller URL
3. Wrong API key - must match controller's key

**Fix:**
```bash
# Verify controller is running
curl http://localhost:3000/api/builds/active \
  -H "X-API-Key: test-api-key-1234567890"
```

### Build stuck in "pending"

**Cause:** Worker not running or not polling

**Fix:**
1. Check worker is running: `pgrep -fl FreeAgent`
2. Restart worker if needed
3. Check worker logs for errors

### CLI returns "Unauthorized"

**Cause:** API key mismatch

**Fix:**
```bash
# Use environment variable
export EXPO_CONTROLLER_API_KEY="test-api-key-1234567890"
bun run dev list

# Or set in config
bun run dev config set api-key test-api-key-1234567890
```

### Menu bar icon not showing

**Cause:** App crashed or didn't start

**Fix:**
```bash
# Kill any existing instances
killall FreeAgent

# Rebuild and restart
cd free-agent
swift build
.build/debug/FreeAgent
```

### Green dot not appearing

**Cause:** No active builds or rendering issue

**Fix:**
1. Submit a build to trigger green dot
2. Rebuild app: `swift build && killall FreeAgent && .build/debug/FreeAgent`

## Stopping Services

### Stop Worker
Click menu bar icon → **"Quit Free Agent"**

Or via terminal:
```bash
killall FreeAgent
```

### Stop Controller
In controller terminal: **Ctrl+C**

Or via terminal:
```bash
lsof -ti:3000 | xargs kill
```

## Resetting State

### Clear Database
```bash
rm packages/controller/data/controller.db
```

### Clear Storage
```bash
rm -rf packages/controller/storage/*
```

### Clear CLI Config
```bash
rm -rf ~/.expo-controller
```

## Port Configuration

**Default ports:**
- Controller: `3000`
- Worker: N/A (polls controller)

**Change controller port:**
```bash
cd packages/controller
bun run src/cli.ts --port 8080
```

**Update worker settings:**
Settings → Controller URL → `http://localhost:8080`

**Update CLI:**
```bash
bun run dev config set controller-url http://localhost:8080
```

## Next Steps

- Test with real Expo project
- Test iOS builds (requires certs)
- Test Android builds
- Test multiple workers
- Deploy controller to remote server (see SETUP_REMOTE.md)
