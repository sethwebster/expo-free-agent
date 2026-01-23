# Free Agent Implementation Status

## Summary

macOS worker app for Expo Free Agent distributed build system - Week 3-4 implementation complete (core structure).

## Completed Components

### 1. Swift Package Structure ✓
- Package.swift with 3 modules: FreeAgent (executable), WorkerCore, BuildVM
- Proper module dependencies
- Swift 6.0 concurrency-safe code
- macOS 14.0+ platform requirement

### 2. Menu Bar App ✓
**File:** `/free-agent/Sources/FreeAgent/main.swift`

Features:
- NSStatusBar integration with CPU icon
- Menu items:
  - Status indicator (Idle/Running)
  - Start/Stop worker toggle
  - Settings window
  - Statistics (placeholder)
  - Quit
- Worker service lifecycle management
- @MainActor for UI thread safety

### 3. SwiftUI Settings Window ✓
**File:** `/free-agent/Sources/FreeAgent/SettingsView.swift`

Configuration options:
- Controller URL and poll interval
- Resource limits: CPU (10-100%), Memory (2-16GB), concurrent builds (1-4)
- VM settings: disk size (30-100GB), reuse VMs toggle, cleanup toggle
- Worker preferences: auto-start, idle-only mode, build timeout
- Persistent config via WorkerConfiguration

### 4. Worker Configuration ✓
**File:** `/free-agent/Sources/WorkerCore/WorkerConfiguration.swift`

Features:
- Codable struct for JSON persistence
- Stored at `~/Library/Application Support/FreeAgent/config.json`
- Auto-generates worker ID (UUID) and device name on first run
- Sendable conformance for Swift 6 concurrency

### 5. Worker Service ✓
**File:** `/free-agent/Sources/WorkerCore/WorkerService.swift`

Implemented:
- Actor-based service for thread-safe state management
- Registration with controller (POST `/api/workers/register`)
- Polling loop (GET `/api/workers/poll?worker_id={id}` every 30s)
- API key authentication (X-API-Key header on all requests)
- Job execution coordination:
  - Download build package
  - Download signing certs
  - Create VM and execute build
  - Upload results
  - Cleanup
- Build concurrency limits
- Graceful shutdown (wait for active builds)
- Error handling and retry logic

### 6. VM Manager ✓
**File:** `/free-agent/Sources/BuildVM/VMManager.swift`

Implemented:
- Apple Virtualization.framework integration
- macOS VM configuration:
  - Platform config (Apple Silicon hardware model)
  - CPU allocation based on % limit
  - Memory allocation (GB limit)
  - Disk image creation (ephemeral or reusable)
  - NAT networking
  - Headless graphics (1920x1080)
  - Entropy device for RNG
- VM lifecycle:
  - Create/start/stop VM
  - Persistent storage at `~/Library/Application Support/FreeAgent/VMs/`
  - Hardware model and machine identifier persistence
  - Auxiliary storage (NVRAM)
- Build execution workflow
- Cleanup on completion

### 7. Xcode Build Executor ✓
**File:** `/free-agent/Sources/BuildVM/XcodeBuildExecutor.swift`

Implemented:
- Build execution interface
- Command execution hooks (SSH/virtio-vsock placeholders)
- Build timeout handling
- Log collection
- Success/failure result handling

### 8. Type Definitions ✓
**File:** `/free-agent/Sources/BuildVM/BuildVMTypes.swift`

- `BuildResult` (success, logs, artifactPath)
- `VMConfiguration` (resource limits for VM)
- Sendable conformance for all shared types

### 9. Build System ✓
- Compiles successfully with Swift 6.0
- No warnings (Swift strict concurrency mode)
- Proper entitlements (hypervisor, networking, no sandbox)
- Info.plist for app metadata

## Not Yet Implemented (TODO)

### Critical Path (Required for MVP)

1. **VM-Host Communication**
   - SSH server in VM + key-based auth
   - OR virtio-vsock guest agent
   - Command execution with stdout/stderr streaming
   - File transfer (source code, certs, artifacts)

2. **macOS VM Image Creation**
   - Download IPSW restore image
   - Install macOS via VZMacOSInstaller
   - Automated Xcode installation in VM
   - Pre-bake VM image with common dependencies
   - VM snapshot/cloning for fast startup

3. **Certificate Installation**
   - Extract P12 cert from downloaded bundle
   - Transfer to VM
   - Import to VM keychain: `security import cert.p12 -k ~/Library/Keychains/login.keychain`
   - Unlock keychain for build process
   - Provisioning profile installation

4. **Source Code Mounting**
   - virtio-fs shared directory
   - OR rsync/scp source code to VM
   - Extract zip in VM
   - Set proper permissions

5. **Artifact Extraction**
   - Locate IPA in VM: `find ~/Library/Developer/Xcode/DerivedData -name "*.ipa"`
   - Copy from VM to host
   - Verify signature: `codesign --verify --deep --verbose=4 app.ipa`

6. **Error Recovery**
   - VM crash detection and restart
   - Build timeout enforcement (kill VM after timeout)
   - Network failure retry with exponential backoff
   - Corrupt VM disk recovery (delete and recreate)

### Nice to Have (Future)

7. **VM Pooling**
   - Keep N warm VMs ready (avoid cold start)
   - Recycle VMs after M builds
   - Health check on idle VMs
   - Balance between resource usage and startup time

8. **Statistics Dashboard**
   - Build count (total, today, this week)
   - Success rate
   - Average build time
   - CPU/memory usage graphs
   - Credits earned (future)

9. **Build Progress Streaming**
   - Real-time log streaming to controller
   - Progress percentage estimation
   - Cancel in-progress builds

10. **Advanced Features**
    - Secure Enclave attestation for worker identity
    - E2E encryption for source code
    - Reproducible build verification
    - Build artifact caching

## Known Issues

1. **Hardware Model Initialization**
   - Current code requires pre-existing hardware model
   - Need VM creation workflow to generate on first run
   - Workaround: Manually create VM once, then reuse

2. **SSH Not Implemented**
   - executeCommand() is currently a stub
   - Returns fake success
   - Real implementation needs SSH client or virtio-vsock protocol

3. **No VM Image**
   - VMManager expects VM disk at `~/Library/Application Support/FreeAgent/VMs/default/Disk.img`
   - User must manually create VM first
   - Need automated setup script

4. **Certificate Handling**
   - installSigningCertificates() is a placeholder
   - Needs P12 password handling (keychain or prompt)
   - Provisioning profile support

5. **No Controller Server**
   - WorkerService polls non-existent controller
   - Need to implement controller (Node.js server) separately
   - See ARCHITECTURE.md Week 1-2 tasks

## File Structure

```
free-agent/
├── Package.swift                              # Swift package manifest
├── FreeAgent.entitlements                     # App entitlements (hypervisor, network)
├── Info.plist                                 # App metadata
├── README.md                                  # Usage documentation
├── IMPLEMENTATION_STATUS.md                   # This file
├── Sources/
│   ├── FreeAgent/                            # Main app
│   │   ├── main.swift                        # Menu bar app, entry point
│   │   └── SettingsView.swift                # SwiftUI settings window
│   ├── WorkerCore/                           # Business logic
│   │   ├── WorkerConfiguration.swift         # Config persistence
│   │   └── WorkerService.swift               # Polling, job execution
│   └── BuildVM/                              # VM management
│       ├── BuildVMTypes.swift                # Shared types
│       ├── VMManager.swift                   # Virtualization.framework
│       └── XcodeBuildExecutor.swift          # Build execution
└── Tests/
    └── FreeAgentTests/                       # (empty, TODO)
```

## Next Steps

**Recommended order:**

1. **Create VM image automation** (`/vm-setup/create-macos-vm.sh`)
   - Download macOS IPSW
   - Use VZMacOSInstaller API
   - Install Xcode (20GB download + install)
   - Create snapshot for fast cloning

2. **Implement SSH communication**
   - Add SSH server to VM (enabled by default in macOS)
   - Generate SSH key pair for worker
   - Test command execution: `ssh vm 'npm install'`

3. **Complete certificate installation**
   - Parse P12 file
   - Securely transfer to VM
   - Import to keychain with `security` command

4. **Implement artifact extraction**
   - Find IPA in VM DerivedData
   - SCP back to host
   - Store at temp location for upload

5. **Build controller server**
   - See ARCHITECTURE.md Week 1 tasks
   - Node.js + Express + SQLite
   - REST API for worker registration and job polling

6. **End-to-end test**
   - Real Expo app build
   - Measure timing (target: 15-20 min)
   - Verify IPA signature and installation

## Testing

Currently untested. To test manually:

```bash
cd free-agent
swift build -c release
.build/release/FreeAgent
```

Expected behavior:
- Menu bar icon appears
- Settings window works
- Worker registration fails (no controller)
- VM creation fails (no VM image)

## Build Time Estimate

Remaining work: **2-3 weeks** (1 developer)

Breakdown:
- VM image automation: 3-4 days (complex, needs testing on multiple macOS versions)
- SSH communication: 2-3 days
- Certificate handling: 2 days
- Artifact extraction: 1 day
- Error recovery: 2-3 days
- Testing + debugging: 3-5 days

Total: 13-18 days ≈ 2.5-3.5 weeks

## Dependencies

External:
- Xcode 15+ (for Virtualization.framework)
- macOS 14.0+ (Sonoma)
- macOS IPSW restore image (~13GB download)
- Xcode installer (~15GB download for VM)

Internal:
- Controller server (separate Node.js project)
- CLI submit tool (separate Node.js project)

## Questions for User

1. **Xcode licensing:** Can workers legally run Xcode builds for other users? Apple EULA unclear.
2. **VM technology:** Stick with raw Virtualization.framework or use UTM for simpler VM management?
3. **Warm VMs:** Keep VMs warm between builds (faster) vs cold start (cleaner)? Resource trade-off.
4. **Priority:** Should this work before controller is built, or coordinate timing?
5. **Testing strategy:** Need real EAS credentials for iOS signing tests?
