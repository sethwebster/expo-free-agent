# Plan: Mesh Build Submission Flow (iOS Simulator + TestFlight)

**Date**: 2026-02-05
**Status**: Draft
**Owner**: @sethwebster, @codex

## Goal
Define an achievable end-to-end flow that produces installable iOS artifacts via `npx @sethwebster/expo-free-agent submit [options] [path]` while protecting developer IP and secrets, and enabling mesh contribution credits.

## User Stories
As a developer, I want to run `npx @sethwebster/expo-free-agent submit [options] [path]` and receive a correctly signed artifact for TestFlight or a simulator-compatible build.

As a developer, submitting builds must not compromise my IP or secrets.

As a contributor, I want to offer my idle CPU cycles and earn credits for higher-tier builds.

## Definition of “Will Work Today”
The flow must produce a valid, installable artifact on day one, even if it only supports a narrower trust model.
For MVP, we accept explicit constraints to guarantee correctness.

## Flow (Optimal Path - Achievable Today)
### Inputs
- Project path.
- Target: `ios-simulator` or `ios-testflight`.
- Signing material on the user’s machine.

### Build Targets
- `ios-simulator` produces a `.app` bundle for iOS Simulator in a `.zip` archive.
- `ios-testflight` produces a signed `.ipa` using certs provided by the submitter.

### Trust Model (Achievable Today)
- All mesh workers can run builds.
- Signing secrets are sent to the worker VM (insecure, demo-only).
- Source code is visible to a malicious host (best-effort security only).

### MVP Constraints (Hard Requirements)
- Only App Store / TestFlight export supported for `ios-testflight`.
- Cert bundle must include a single P12, password, and one matching provisioning profile.

### Submit Flow
1. CLI validates project path and target.
2. CLI reads `app.json` or `app.config.*` and extracts `ios.bundleIdentifier` and `ios.appleTeamId`.
3. CLI discovers local signing material and packages cert bundle.
4. CLI submits source + cert bundle for `ios-testflight`, source only for `ios-simulator`.
6. Controller assigns build to a worker matching trust model and platform capability.
7. Worker provisions VM, downloads source and certs, then executes build.
8. Worker uploads artifact and build logs, VM destroyed.

### Certificate Discovery (Local, Non-Apple-Auth)
- Runs on the user’s machine at submit time.
- List local signing identities from keychain.
- Parse local provisioning profiles from `~/Library/MobileDevice/Provisioning Profiles`.
- Match profile by `application-identifier` against `ios.bundleIdentifier`.
- For TestFlight, prefer distribution profiles.
- Cache selection per project in `.expo-free-agent-certs.json`.

### VM Build Steps (TestFlight)
1. Install P12 into a temporary keychain.
2. Install matching provisioning profile into `~/Library/MobileDevice/Provisioning Profiles`.
3. Run `xcodebuild archive` with manual signing flags.
4. Export `.ipa` using an `ExportOptions.plist` derived from profile type.

### VM Build Steps (Simulator)
1. Run `xcodebuild` targeting `iphonesimulator`.
2. Package `.app` into a `.zip` artifact.

### Output
- TestFlight: `.ipa` (signed in VM) and build logs.
- Simulator: `.zip` containing `.app` and build logs.

## Security Posture (Achievable Today)
- Signing secrets are sent to worker VMs for signing (demo-only).
- Source code is still visible to mesh workers (best-effort security only).
- VM uses ephemeral storage and is destroyed after completion.
### Mitigations (Best-Effort, Not Guarantees)
- Allowlist trusted workers for teams that require stricter controls.
- Minimize logs and disable source retention on workers.
- Short-lived tokens and encrypted transit for all artifacts.

## Diff From Current Flow
- Current flow sends certs to the controller; new flow **never uploads certs**.
- Current flow relies on `-allowProvisioningUpdates`; new flow archives with `CODE_SIGNING_ALLOWED=NO`.
- Current flow fails in VM due to missing accounts/profiles; new flow enforces profile selection and manual signing.
- Current flow does not separate simulator vs TestFlight artifacts; new flow does.

## Feasibility Tests (Short-Term)
- Unit test for profile parsing from `.mobileprovision`.
- Unit test for profile selection by bundle identifier.
- Integration test for manual signing flags passed to `xcodebuild`.
- Integration test for simulator build artifact structure.
- E2E test that builds a simulator app without any certs.

## Risks
- No Apple-auth API support means developers must already have local certs and profiles.
- Trust model is limited for signed builds until end-to-end encryption or enclave support exists.
- Profile parsing must be reliable across profile formats.

## Next Steps
- Add explicit target selection in CLI: `--target ios-simulator|ios-testflight`.
- Update VM build executor to install certs and export `.ipa` in VM.
- Add tests listed above.
- Enforce MVP constraints in CLI (profile selection + bundle match).
