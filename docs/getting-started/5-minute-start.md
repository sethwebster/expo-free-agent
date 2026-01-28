# Get Started in 5 Minutes

Build your first Expo app using Expo Free Agent in under 5 minutes. Zero configuration required.

## What You'll Accomplish

By the end of this guide:
- ✅ Controller running locally
- ✅ Worker connected and ready
- ✅ First iOS build submitted
- ✅ Artifacts downloaded

**Time**: ~5 minutes
**Prerequisites**: macOS (for worker), Bun installed

---

## Step 1: Start the Controller (30 seconds)

The controller coordinates builds between your CLI and workers.

```bash
# Clone and start controller
git clone https://github.com/expo/expo-free-agent.git
cd expo-free-agent
bun install
bun controller
```

**Expected output:**
```
🚀 Expo Free Agent Controller
📍 Server: http://localhost:3000
🔑 API Key: your-api-key-here
✅ Ready for builds!
```

**What you just did:** Started a local build coordinator. It's now waiting for workers and build requests.

💡 **Keep this terminal open** - controller must stay running.

---

## Step 2: Set Your API Key (10 seconds)

Copy the API key from the controller output above.

```bash
# In a NEW terminal
export EXPO_CONTROLLER_API_KEY="your-api-key-here"
```

**What you just did:** Configured authentication so the CLI and worker can talk to the controller.

---

## Step 3: Start a Worker (1 minute)

Workers execute builds in isolated VMs on Mac hardware.

```bash
# Download and install worker
cd ~/Downloads
npx @sethwebster/expo-free-agent-worker

# Start the worker (menu bar app will appear)
open /Applications/FreeAgent.app
```

**Expected:** Menu bar app appears with ⚡️ icon. Click it → "Connect to Controller":

```
Controller URL: http://localhost:3000
API Key: [paste your key]
```

Click **Connect**. Status should show: `✅ Connected • Ready for builds`

**What you just did:** Installed a worker that will execute builds in secure VMs.

**Troubleshooting:**
- **"App is damaged"**: macOS Gatekeeper blocked it. Run: `xattr -d com.apple.quarantine /Applications/FreeAgent.app`
- **"Cannot connect"**: Ensure controller is running at http://localhost:3000

---

## Step 4: Submit Your First Build (2 minutes)

Let's build a sample Expo app.

```bash
# Create a test project
cd ~/
npx create-expo-app@latest my-test-app
cd my-test-app

# Submit build to Free Agent
npx expo-build submit --platform ios

# Or if you have the CLI installed globally:
# expo-build submit --platform ios
```

**Expected output:**
```
📦 Bundling source code...
✓ Source bundled (12.4 MB)

📤 Uploading to controller...
✓ Upload complete

🎯 Build submitted!
   Build ID: build-abc123
   Job ID: job-xyz789

⏳ Waiting for worker...
✓ Assigned to worker: worker-001

🔨 Building...
   [=====>                    ] 25% Installing dependencies...
```

**What you just did:** Packaged your app and sent it to the controller, which assigned it to your worker.

**This will take 5-15 minutes** depending on your project size. Go grab coffee! ☕

---

## Step 5: Download Your Build (30 seconds)

Once the build completes:

```bash
# Download artifacts
expo-build download build-abc123

# Or if still in previous command:
# It will auto-download when complete
```

**Expected output:**
```
✓ Build completed successfully!

📥 Downloading artifacts...
   ✓ App.ipa (45.2 MB)
   ✓ build-logs.txt (124 KB)

💾 Saved to: ./expo-builds/build-abc123/

Next steps:
  • Install on device: ./expo-builds/build-abc123/App.ipa
  • Upload to TestFlight: Use Xcode or Transporter
  • See logs: ./expo-builds/build-abc123/build-logs.txt
```

**What you just did:** Retrieved your compiled iOS app from the controller.

---

## 🎉 Success! What You Built

```
┌─────────────────────────────────────────────┐
│                                             │
│   You now have a working distributed        │
│   build system:                             │
│                                             │
│   1️⃣  Controller (orchestrates builds)      │
│   2️⃣  Worker (executes in VMs)              │
│   3️⃣  CLI (submits and downloads)           │
│                                             │
│   Your first .ipa file: ✅                  │
│                                             │
└─────────────────────────────────────────────┘
```

---

## What's Next?

### As a User (Building Apps)
- [Submit More Builds](../operations/build-submission.md)
- [Configure Build Settings](../operations/build-config.md)
- [Upload to TestFlight](../operations/testflight.md)

### As an Operator (Running Infrastructure)
- [Deploy Controller to VPS](../getting-started/setup-remote.md)
- [Set Up Multiple Workers](../operations/worker-setup.md)
- [Configure Production Settings](../operations/production.md)

### As a Contributor (Improving the System)
- [Understand the Architecture](../architecture/diagrams.md)
- [Set Up Development Environment](../getting-started/setup-local.md)
- [Contributing Guide](../contributing/GUIDE.md)

---

## Troubleshooting

### Build Failed
```bash
# Check build logs
expo-build logs build-abc123

# Common issues:
# - Missing dependencies: Check package.json
# - Expo config errors: Validate app.json
# - Certificate issues: Ensure valid Apple Developer cert
```

### Worker Not Connecting
```bash
# Verify controller is running
curl http://localhost:3000/health

# Check worker logs (click worker → View Logs)
# Common issues:
# - Wrong API key
# - Controller URL incorrect
# - Firewall blocking port 3000
```

### Upload Timeout
```bash
# Large projects may timeout on slow connections
# Increase timeout:
export EXPO_BUILD_TIMEOUT=600  # 10 minutes

# Or exclude unnecessary files in .gitignore:
node_modules/
.expo/
ios/
android/
```

---

## Quick Reference

**Controller Commands:**
```bash
bun controller          # Start controller
bun controller:dev      # Start with auto-reload
curl http://localhost:3000/health  # Check health
```

**CLI Commands:**
```bash
expo-build submit       # Submit build
expo-build status <id>  # Check build status
expo-build download <id> # Download artifacts
expo-build list         # List all builds
```

**Worker Controls:**
```bash
open /Applications/FreeAgent.app  # Launch worker
# Menu: Connect, Disconnect, View Logs, Quit
```

**Environment Variables:**
```bash
EXPO_CONTROLLER_URL     # Default: http://localhost:3000
EXPO_CONTROLLER_API_KEY # Required for auth
EXPO_BUILD_TIMEOUT      # Default: 300 (5 min)
```

---

## Video Walkthrough

🎥 **Watch:** [5-Minute Setup Video](https://youtube.com/watch?v=...) _(coming soon)_

---

**Got questions?** See the [Complete Setup Guide](./setup-local.md) for detailed explanations.

**Having issues?** Check [Troubleshooting Guide](../operations/troubleshooting.md) or [open an issue](https://github.com/expo/expo-free-agent/issues).
