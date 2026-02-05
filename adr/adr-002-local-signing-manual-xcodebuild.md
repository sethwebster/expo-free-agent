# ADR-002: Local Signing With Manual Xcodebuild for iOS Builds

**Status**: Proposed
**Date**: 2026-02-05
**Deciders**: @sethwebster, @codex
**Consulted**: TBD

## Context
We need a reliable, same-day path to produce installable iOS artifacts via the CLI. Current builds fail because Xcode is invoked with automatic signing and no Apple account configured inside the VM. The system currently packages all provisioning profiles and does not select a profile matching the bundle identifier.

## Decision Drivers
- Reliability: build must succeed without Xcode account setup in the VM.
- Security: signing secrets should remain on the user’s machine unless explicitly shared.
- Time to implement: achievable in a long day.
- Maintainability: minimal new dependencies.
- Compatibility: works with existing local keychain profiles.

## Considered Options
1. **Mesh compile + VM signing (demo)**
- Pros: Works without Apple auth in VM. Immediate path to valid `.ipa`. Minimal external dependencies.
- Cons: Signing secrets are exposed to mesh workers. Mesh workers still see source code.

2. **Apple-auth flow with Developer API access**
- Pros: Guided team/profile selection. Familiar Expo UX.
- Cons: Requires Apple credential handling, 2FA flows, token caching, and higher operational risk. Not feasible in a day.

3. **Remote signing via centralized signing service**
- Pros: Simplifies developer onboarding. Enables mesh builds without user secrets on workers.
- Cons: High security risk, large scope, requires key management infrastructure.

## Decision
Adopt mesh build with signing inside the VM using submitter-provided certs (demo-only). Simulator builds do not require signing and can run without certs.

**MVP constraints**:
- Only App Store / TestFlight export supported.
- Cert bundle must include a single matching provisioning profile and P12.

## Consequences
### Positive
- Builds succeed without Xcode account configuration in the VM.
- Minimal changes to current architecture.
- Clear separation between simulator and TestFlight artifacts.

### Negative
- Signing secrets are exposed to mesh workers (demo-only).
- Mesh workers still see source code (best-effort security only).
- Profile selection becomes a critical path.

### Neutral
- Does not preclude future Apple-auth integration.

## Implementation
- CLI extracts bundle identifier and team ID from Expo config.
- CLI packages cert bundle and submits with source.
- VM installs certs and profile, runs `xcodebuild archive`, and exports `.ipa`.
- Simulator builds use `iphonesimulator` target and package `.app` as `.zip`.

## Validation
- Integration test builds a simulator artifact without certs.
- Integration test builds a TestFlight `.ipa` using manual signing.
- Unit tests for profile parsing and profile selection by bundle identifier.

## References
- plans/plan-2026-02-05-mesh-build-flow.md
