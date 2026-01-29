# ADR-0002: Use Tart for VM Management

**Status:** Accepted

**Date:** 2026-01-27 (Initial commit 47b1097)

## Context

iOS builds require macOS VMs with Xcode installed. Need hypervisor-level isolation to execute untrusted build scripts safely.

Apple provides Virtualization.framework (native macOS hypervisor API), but direct usage requires:
- Low-level VM lifecycle management
- Manual network/storage configuration
- Boot loader and UEFI setup
- macOS installation and Xcode provisioning
- VM snapshot/clone management

## Decision

Use **Tart** CLI tool (wrapper around Virtualization.framework):

- Clone-based workflow: template image → job-specific clone → execute → destroy
- Template image pre-baked with macOS + Xcode
- SSH for host-VM communication
- Tart handles all low-level hypervisor operations
- Community-maintained base images available

## Consequences

### Positive

- **Battle-tested:** Tart handles edge cases (boot failures, network setup, snapshot corruption)
- **Simple cloning:** Immutable template semantics prevent state contamination
- **Standard communication:** SSH is well-understood, widely supported, easily debuggable
- **Community images:** Can use `ghcr.io/cirruslabs/macos-*` base images
- **CLI simplicity:** Single `tart clone/run/stop/delete` command vs hundreds of lines of Virtualization.framework code
- **Lower maintenance:** Outsource VM complexity to upstream maintainers
- **Screen/tmux integration:** Easy to attach to running build for debugging

### Negative

- **External dependency:** Requires `tart` installation on worker machine (documented in installer)
- **SSH overhead:** ~50-100ms latency vs direct virtio-vsock communication
- **Large templates:** Base images are ~50GB (mitigated by using APSF clone-on-write)
- **Boot time:** VM cold start takes ~30 seconds (acceptable for 5-30 minute builds)
- **Tart updates:** Breaking changes in Tart CLI could require worker updates
- **Limited customization:** Cannot tweak low-level hypervisor settings

### Alternatives Considered

**Direct Virtualization.framework:**
- Pros: No external dependency, full control, potential performance gains
- Cons: 1000+ lines of complex Swift code, VM management bugs, network setup fragility
- **Rejected:** Complexity outweighs benefits for prototype

**Docker/containers:**
- Pros: Lightweight, fast startup, familiar tooling
- Cons: Cannot run macOS/iOS builds (kernel mismatch)
- **Not viable** for iOS build use case

**Cloud VMs (AWS Mac instances):**
- Pros: No worker hardware required, elastic scaling
- Cons: High cost ($1.09/hour minimum 24h), slow provisioning (minutes), defeats distributed mesh goal
- **Rejected:** Against core "distributed build mesh" architecture

## Implementation Notes

VM management in `free-agent/Sources/BuildVM/TartVMManager.swift`:
- Uses `Process` API to shell out to `tart` CLI
- Captures stdout/stderr for error reporting
- Implements timeout handling for hung VMs
- Cleans up failed VMs with `defer { tart delete }`

Template updates via `vm-setup/` scripts and GitHub releases.

## References

- VM manager implementation: `free-agent/Sources/BuildVM/TartVMManager.swift`
- Template setup: `vm-setup/install.sh`
- Tart project: https://github.com/cirruslabs/tart
