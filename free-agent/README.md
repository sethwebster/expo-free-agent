# Free Agent - Expo Build Worker

macOS menu bar application that runs Expo builds in isolated macOS VMs using Apple's Virtualization.framework.

## Features

- Menu bar app with status indicator
- SwiftUI settings window for configuration
- Polls central controller for build jobs
- Executes builds in ephemeral macOS VMs
- Handles iOS code signing in VM
- Uploads build artifacts
- Resource limits (CPU, memory, concurrent builds)

## Requirements

- macOS 14.0+ (Sonoma or later)
- Apple Silicon or Intel Mac with VT-x
- Xcode 15+
- Swift 6.0+

## Architecture

```
FreeAgent (menu bar app)
├── WorkerCore
│   ├── WorkerConfiguration - Settings persistence
│   └── WorkerService - Controller polling & job execution
└── BuildVM
    ├── VMManager - Virtualization.framework wrapper
    └── XcodeBuildExecutor - EAS build execution
```

## Building

```bash
cd free-agent
swift build -c release
```

## Running

```bash
swift run FreeAgent
```

Or build an app bundle:
```bash
swift build -c release
# Copy .build/release/FreeAgent to /Applications
```

## Configuration

Settings stored at: `~/Library/Application Support/FreeAgent/config.json`

Default configuration:
- Controller URL: `http://localhost:3000`
- Poll interval: 30 seconds
- Max CPU: 70%
- Max memory: 8 GB
- Concurrent builds: 1
- VM disk size: 50 GB

## VM Setup

The app requires a macOS VM image with Xcode installed. On first run, the VM will be created automatically, but you need to:

1. Download macOS restore image (IPSW)
2. Install macOS in VM
3. Install Xcode in VM
4. Configure SSH access

See `/vm-setup/` directory for scripts (TODO).

## Development Status

**Implemented:**
- [x] Swift package structure
- [x] Menu bar app skeleton
- [x] SwiftUI settings window
- [x] WorkerService polling logic
- [x] VMManager with Virtualization.framework
- [x] Basic build executor

**TODO:**
- [ ] VM-host communication (SSH or virtio-vsock)
- [ ] Certificate installation in VM keychain
- [ ] Artifact extraction from VM
- [ ] macOS VM image creation automation
- [ ] Xcode installation in VM
- [ ] virtio-fs mounting for source code
- [ ] Build progress streaming
- [ ] Statistics tracking
- [ ] Error recovery and retry logic
- [ ] VM pooling and reuse
- [ ] Resource monitoring dashboard

## Testing

```bash
swift test
```

## Notes

- VM creation requires ~50GB disk space per VM
- First build will be slow (Xcode downloads dependencies)
- Consider pre-baking VM image with Xcode + common deps
- Virtualization.framework requires hypervisor entitlement
- App must run with full disk access (no sandbox)

## License

See main project LICENSE.
