# Free Agent - Quick Start

## Build

```bash
cd free-agent
swift build -c release
```

Binary: `.build/release/FreeAgent` (416KB, arm64)

## Run

```bash
.build/release/FreeAgent
```

Expected:
- Menu bar icon appears (CPU icon)
- Click icon → menu with Start Worker, Settings, Quit
- Settings window configurable

## Configuration

Auto-created at: `~/Library/Application Support/FreeAgent/config.json`

Defaults:
```json
{
  "controllerURL": "http://localhost:3000",
  "pollIntervalSeconds": 30,
  "maxCPUPercent": 70,
  "maxMemoryGB": 8,
  "maxConcurrentBuilds": 1,
  "vmDiskSizeGB": 50,
  "reuseVMs": false,
  "cleanupAfterBuild": true,
  "autoStart": false,
  "onlyWhenIdle": true,
  "buildTimeoutMinutes": 120
}
```

## Menu Options

- **Status** - Shows Idle/Running
- **Start/Stop Worker** - Toggle worker service
- **Settings** - Opens config window
- **Statistics** - (Placeholder)
- **Quit** - Exit app

## What Works

1. App launches, menu bar UI functional
2. Settings persist
3. Worker attempts to register with controller (will fail - no server yet)
4. Polling loop runs when started
5. VM configuration generates correctly

## What Doesn't Work Yet

1. **No controller server** - Worker can't get jobs (need Week 1-2 implementation)
2. **No VM image** - Can't actually spawn VMs (need `/vm-setup/create-macos-vm.sh`)
3. **No SSH** - Can't execute commands in VM
4. **No cert installation** - Placeholder only
5. **No artifact extraction** - Returns nil

## Testing Without Controller

To verify app works without full stack:

1. Run: `.build/release/FreeAgent`
2. Click menu bar icon
3. Open Settings
4. Change controller URL to `http://httpbin.org/status/200`
5. Click Start Worker
6. Check Console.app for logs:
   - "Worker service starting..."
   - "✓ Registered with controller" (will fail with httpbin)
   - Poll attempts every 30s

## Next Steps

1. **Create VM image** - Run `/vm-setup/create-macos-vm.sh` (TODO)
2. **Build controller** - See `ARCHITECTURE.md` Week 1 tasks
3. **Test end-to-end** - Submit real Expo build

## Troubleshooting

**App won't launch:**
- Check macOS 14.0+ required
- Check Xcode 15+ installed

**Menu bar icon missing:**
- App runs but no UI - check LSUIElement in Info.plist

**Settings don't save:**
- Check permissions: `~/Library/Application Support/FreeAgent/`
- Should auto-create directory

**Worker won't start:**
- Check controller URL in settings
- Check network connectivity
- Check Console.app for errors

**VM creation fails:**
- Check entitlements: `com.apple.vm.hypervisor` = true
- Check no sandbox: `com.apple.security.app-sandbox` = false
- Check macOS version (14.0+ required)

## Development

Edit code, rebuild:
```bash
swift build
.build/debug/FreeAgent
```

Clean build:
```bash
swift package clean
swift build -c release
```

Format code:
```bash
swift-format -i -r Sources/
```

## File Locations

- **Config:** `~/Library/Application Support/FreeAgent/config.json`
- **VM storage:** `~/Library/Application Support/FreeAgent/VMs/`
- **Logs:** Console.app (filter: "FreeAgent")
- **Binary:** `.build/release/FreeAgent`

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15+
- Swift 6.0+
- ~60GB free space (for VM + Xcode)

## Architecture

```
Menu Bar App
    ↓
WorkerService (polls controller)
    ↓
VMManager (creates macOS VM)
    ↓
XcodeBuildExecutor (runs eas build)
    ↓
Upload results
```

See `IMPLEMENTATION_STATUS.md` for detailed status.
