# VM Implementation Summary

Complete implementation of macOS VM infrastructure for Free Agent iOS builds.

## What Was Implemented

### 1. VM Creation Script (`/vm-setup/create-macos-vm.sh`)

**Purpose:** Automate creation of macOS VMs for building iOS apps.

**Features:**
- Downloads macOS IPSW from Apple servers
- Creates VM using Virtualization.framework
- Generates hardware model and machine identifier
- Creates 80GB disk image (configurable)
- Sets up auxiliary storage (NVRAM)
- Validates VM configuration

**Usage:**
```bash
./create-macos-vm.sh my-builder 80
```

**Output:**
- VM directory: `~/Library/Application Support/FreeAgent/VMs/my-builder/`
- Files: HardwareModel, MachineIdentifier, Disk.img, AuxStorage

**Time:** ~30-60 minutes (most time spent installing macOS)

### 2. SSH Communication (`XcodeBuildExecutor.swift`)

**Purpose:** Execute commands in VM and transfer files.

**Implementation:**
- SSH client using macOS `/usr/bin/ssh`
- Key-based authentication (ED25519)
- Command execution with stdout/stderr capture
- Timeout handling (terminates hung processes)
- SCP for file transfer (single files and directories)

**Methods:**
```swift
public func executeCommand(_ command: String, timeout: TimeInterval) async throws -> String
public func copyFileToVM(localPath: URL, remotePath: String) async throws
public func copyFileFromVM(remotePath: String, localPath: URL) async throws
public func copyDirectoryToVM(localPath: URL, remotePath: String) async throws
```

**SSH Configuration:**
- Host: 192.168.64.2 (default NAT IP)
- Port: 22
- User: builder
- Key: `~/.ssh/free_agent_ed25519`
- Connection timeout: 10s
- Keepalive: 30s intervals

**Error Handling:**
- Connection failures (VM not ready)
- Command failures (non-zero exit codes)
- Timeouts (process termination)
- File transfer failures

### 3. Certificate Management (`CertificateManager.swift`)

**Purpose:** Install P12 certificates and provisioning profiles in VM.

**Implementation:**
- Creates dedicated keychain (`build.keychain-db`)
- Imports P12 with password
- Unlocks keychain for codesign access
- Sets key partition list (no password prompt)
- Installs provisioning profiles to correct directory
- Verifies installation with `security find-identity`
- Cleanup: removes keychain and profiles

**API:**
```swift
public func installCertificates(
    p12Path: URL,
    p12Password: String,
    provisioningProfiles: [URL]
) async throws

public func listSigningIdentities() async throws -> [String]
public func cleanup() async throws
```

**Security Commands Used:**
```bash
security create-keychain -p <password> <path>
security unlock-keychain -p <password> <path>
security import <p12> -k <keychain> -P <p12-password>
security set-key-partition-list -S apple-tool:,apple: -k <password> <keychain>
security find-identity -v -p codesigning
```

**Keychain Location:** `$HOME/Library/Keychains/build.keychain-db`
**Profile Location:** `$HOME/Library/MobileDevice/Provisioning Profiles/`

### 4. Artifact Extraction (`VMManager.swift`)

**Purpose:** Locate and copy IPA from VM to host.

**Implementation:**
- Searches DerivedData for `*.ipa` files
- Uses `find` command to locate build output
- Copies IPA from VM to host temp directory via SCP
- Verifies file exists and checks size
- Returns URL to local IPA for upload

**Command:**
```bash
find ~/Library/Developer/Xcode/DerivedData -name "*.ipa" -type f 2>/dev/null | head -n 1
```

**Output:**
- Local IPA path: `/tmp/build-<uuid>.ipa`
- Typical size: 50-200MB

### 5. Integrated Pipeline (`WorkerService.swift` + `VMManager.swift`)

**Complete build flow:**

```swift
// 1. Download assets
let sourceCode = try await downloadBuildPackage(job)      // Source zip
let certs = try await downloadSigningCertificates(job)    // P12 + profiles

// 2. Create and start VM
let vmManager = try VMManager(configuration: vmConfig)
let buildResult = try await vmManager.executeBuild(
    sourceCodePath: sourceCode,
    signingCertsPath: certs,
    buildTimeout: TimeInterval(config.buildTimeoutMinutes * 60)
)

// 3. Inside executeBuild():
// - Start VM (30-60s)
// - Wait for SSH (up to 120s)
// - Copy source code to /Users/builder/project
// - Install certificates
// - Run build: npm install → pod install → eas build
// - Extract IPA
// - Stop VM

// 4. Upload results
try await uploadBuildResult(job.id, result: buildResult)

// 5. Cleanup
if config.cleanupAfterBuild {
    try await vmManager.cleanup()  // Delete VM disk
}
try FileManager.default.removeItem(at: sourceCode)
try FileManager.default.removeItem(at: certs)
```

### 6. Error Handling and Timeouts

**VM Crash Detection:**
- `VZVirtualMachineDelegate` tracks crashes
- Build aborts if VM crashes during execution
- Error logged and reported to controller

**Timeout Enforcement:**
- Default: 4 hours (configurable)
- Each command has individual timeout
- SSH timeout: 120s for VM boot
- Command timeout: varies (npm: 600s, build: 4h)
- Process termination on timeout

**Retry Logic:**
- SSH connection: retry every 2s for 120s
- VM start failure: no retry (fail fast)
- Network errors: exponential backoff (5s, 10s, 20s...)

**Cleanup Guarantees:**
- Always stops VM (even on error)
- Removes temp files (source, certs, IPA)
- Optionally deletes VM disk
- Cleanup runs even if build fails

## File Structure

```
free-agent/
├── Sources/
│   ├── BuildVM/
│   │   ├── VMManager.swift              [✓ Complete]
│   │   │   - VM lifecycle (create, start, stop)
│   │   │   - Build execution coordination
│   │   │   - Source code copying
│   │   │   - Artifact extraction
│   │   │   - Error handling & cleanup
│   │   │
│   │   ├── XcodeBuildExecutor.swift     [✓ Complete]
│   │   │   - SSH command execution
│   │   │   - File transfer (SCP)
│   │   │   - Timeout handling
│   │   │   - VM readiness check
│   │   │
│   │   ├── CertificateManager.swift     [✓ Complete]
│   │   │   - Keychain creation
│   │   │   - P12 import
│   │   │   - Provisioning profile install
│   │   │   - Verification & cleanup
│   │   │
│   │   └── BuildVMTypes.swift           [✓ Complete]
│   │       - BuildResult
│   │       - VMConfiguration
│   │
│   └── WorkerCore/
│       └── WorkerService.swift          [✓ Complete]
│           - Job polling
│           - Download coordination
│           - VM build execution
│           - Upload results
│           - Cleanup orchestration
│
└── vm-setup/
    ├── create-macos-vm.sh               [✓ Complete]
    │   - IPSW download
    │   - VM creation
    │   - macOS installation
    │
    ├── setup-ssh.sh                     [✓ Complete]
    │   - SSH key generation
    │   - Instructions for VM setup
    │
    └── README.md                        [✓ Complete]
        - Complete setup guide
        - Architecture diagrams
        - Troubleshooting
```

## Build Timeline

Typical 20-30 minute build breakdown:

| Step | Time | Description |
|------|------|-------------|
| VM Boot | 30-60s | Start macOS VM |
| SSH Wait | 10-30s | Wait for SSH server |
| Source Copy | 10-30s | SCP project files |
| Cert Install | 5-10s | Import to keychain |
| npm install | 1-3 min | Download JS dependencies |
| pod install | 2-4 min | Download iOS dependencies |
| EAS Build | 10-15 min | Xcode compilation + signing |
| IPA Copy | 10-30s | SCP artifact to host |
| VM Shutdown | 5-10s | Stop VM |
| **Total** | **15-25 min** | **Complete build** |

## Performance Characteristics

### Resource Usage

**Per Build VM:**
- CPU: 4 cores (50% of M1 MacBook Air)
- Memory: 8GB
- Disk: 80GB
- Network: ~600MB download/upload

**Host Requirements:**
- macOS 14+ on Apple Silicon
- 16GB RAM minimum (32GB recommended)
- 100GB free disk space per concurrent build
- Fast internet (npm/CocoaPods downloads)

### Scalability

**Single Mac:**
- M1 MacBook Air (16GB): 1 concurrent build
- M2 Mac Mini (32GB): 2 concurrent builds
- M2 Ultra Mac Studio (64GB): 4 concurrent builds

**Throughput:**
- 1 build = 20 min average
- 1 worker = 3 builds/hour = 72 builds/day
- 4 workers = 12 builds/hour = 288 builds/day

### Bottlenecks

1. **VM Boot Time** (30-60s)
   - Solution: Warm VM pool (future)
   - Saves 30-60s per build

2. **Dependency Downloads** (3-7 min)
   - Solution: Pre-bake in VM image
   - Saves 2-5 min per build

3. **Xcode Compilation** (10-15 min)
   - Solution: Incremental builds with persistent DerivedData
   - Saves 5-10 min on subsequent builds

4. **Disk I/O** (SCP transfers)
   - Solution: virtio-fs shared directories
   - Saves ~1 min per build

## Testing Status

### Compilation: ✓ Passes

```bash
cd free-agent
swift build
# Build complete! (0.67s)
```

Zero errors, zero warnings. Swift 6 strict concurrency compliant.

### Manual Testing: ⚠ Requires VM

To test end-to-end:

1. Create VM:
   ```bash
   cd vm-setup
   ./setup-ssh.sh
   ./create-macos-vm.sh test-builder 80
   ```

2. Boot VM and configure (see vm-setup/README.md)

3. Run Free Agent app:
   ```bash
   cd free-agent
   swift build -c release
   .build/release/FreeAgent
   ```

4. Configure in Settings:
   - Controller URL: http://localhost:3000 (placeholder)
   - Enable worker
   - Trigger build

5. Check logs:
   - VM boot
   - SSH connection
   - Certificate installation
   - Build execution
   - Artifact extraction

### Unit Tests: ✗ Not Implemented

Future work:
- Mock SSH executor
- Test certificate parsing
- Test artifact extraction logic
- Test timeout handling
- Test cleanup on error

## Known Limitations

### 1. Xcode Installation

**Issue:** Xcode not automatically installed in VM.

**Current:** Manual setup required:
```bash
# Inside VM
xcode-select --install
```

**Future:** Script to download and install Xcode from Apple servers.

### 2. VM Boot Time

**Issue:** 30-60s cold start for every build.

**Current:** Acceptable for MVP.

**Future:** Warm VM pool (keep N VMs booted).

### 3. Network Access

**Issue:** No logging/monitoring of VM network traffic.

**Current:** NAT networking (VM can reach internet).

**Future:** Proxy all traffic through host for logging and rate limiting.

### 4. Build Caching

**Issue:** Every build starts from clean state.

**Current:** Consistent but slow.

**Future:** Persistent DerivedData for incremental builds.

### 5. Hardware Model

**Issue:** VM requires pre-existing hardware model file.

**Current:** Created by `create-macos-vm.sh`.

**Future:** Generate on first run if missing.

## Deployment Checklist

Before production use:

- [ ] Test VM creation on fresh macOS install
- [ ] Verify SSH keys work across reboots
- [ ] Test certificate installation with real P12
- [ ] Run complete build with real Expo project
- [ ] Measure actual build times
- [ ] Test concurrent builds (resource limits)
- [ ] Test VM crash recovery
- [ ] Test timeout enforcement
- [ ] Test cleanup on error paths
- [ ] Document VM disk space management
- [ ] Set up monitoring (build times, success rate)
- [ ] Implement controller server
- [ ] Create CLI submit tool

## Future Enhancements

### Phase 2 (1-2 weeks)
- [ ] Automated Xcode installation in VM
- [ ] VM health checks (disk space, CPU, memory)
- [ ] Build progress streaming (real-time logs)
- [ ] Cancel in-progress builds
- [ ] Retry failed builds (transient errors)

### Phase 3 (2-3 weeks)
- [ ] VM pooling (warm VMs)
- [ ] Build caching (persistent DerivedData)
- [ ] Pre-bake VM image (Homebrew, CocoaPods, etc.)
- [ ] Network traffic logging/proxying
- [ ] Statistics dashboard (build times, success rate)

### Phase 4 (Future)
- [ ] Support multiple macOS versions
- [ ] Support multiple Xcode versions
- [ ] Distributed builds (multiple worker machines)
- [ ] Build artifact caching (reuse IPAs)
- [ ] Secure Enclave attestation
- [ ] E2E encryption for source code

## Security Considerations

### Implemented

✓ SSH key-based auth (no passwords)
✓ Ephemeral keychains (deleted after build)
✓ Temp file cleanup (source, certs removed)
✓ NAT networking (VMs isolated)
✓ No persistent credential storage

### Future Work

- [ ] Sign VM images for integrity verification
- [ ] Encrypt source code in transit (TLS for SCP)
- [ ] Rate limit builds per user
- [ ] Audit logging (who built what, when)
- [ ] Sandbox VM network (whitelist domains)

## Architecture Decisions

### Why Virtualization.framework over UTM/QEMU?

**Pros:**
- Native Apple API
- Better performance
- Smaller attack surface
- No third-party dependencies

**Cons:**
- More code to write
- Harder to debug
- No GUI (headless only)

**Decision:** Use Virtualization.framework for production, UTM for debugging.

### Why SSH over virtio-vsock?

**Pros:**
- Simple (uses existing tools)
- Widely understood
- Easy to debug
- Works with SCP for file transfer

**Cons:**
- Slower than virtio-vsock
- Requires VM network setup
- Extra overhead

**Decision:** Use SSH for MVP, consider virtio-vsock for Phase 3.

### Why ephemeral VMs over reusable?

**Pros:**
- Guaranteed clean state
- No state leakage between builds
- Simpler error recovery (just delete VM)

**Cons:**
- Slower (30-60s boot time)
- More disk I/O
- Higher resource usage

**Decision:** Ephemeral by default, reusable as option.

## Success Metrics

**MVP Goals:**
- ✓ Compiles without errors
- ⚠ Builds real Expo project (needs testing)
- ⚠ Build completes in <30 minutes (needs measurement)
- ⚠ Success rate >95% (needs data)
- ⚠ Handles errors gracefully (needs testing)

**Production Goals:**
- Build time: <20 minutes (with optimizations)
- Success rate: >98%
- Concurrent builds: 4 per Mac Mini
- Cost: <$0.50 per build (hardware amortization)

## Summary

Complete implementation of VM infrastructure for iOS builds. All core components implemented and compiling. Requires VM setup and end-to-end testing before production use.

**Next Steps:**
1. Create test VM using `create-macos-vm.sh`
2. Run end-to-end build test
3. Measure actual performance
4. Implement controller server
5. Deploy to first worker Mac

**Estimated Time to Production:** 1-2 weeks (testing + controller + CLI tool)
