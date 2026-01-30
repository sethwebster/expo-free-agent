# Distributed Expo Build System - Architecture & Prototype Plan

## Executive Summary

Design for distributed build mesh where users run build workers on their Macs (background idle CPU) to earn Expo credits. Security in both directions: protect Expo from malicious users, protect users from malicious code.

**Core Approach:**
- **Hypervisor-isolated micro-VMs** (Apple Virtualization.framework) per build job
- **Secure Enclave attestation** for worker identity (hardware-bound, Apple-verified)
- **E2E encryption** for source code (user → worker, never exposed)
- **Reproducible builds + parallel verification** for tamper detection
- **Paid builds on Expo hardware, free/low-pri on mesh**

---

## Architecture Design (Phase 1: Research)

### 1. VM Isolation

**Technology:** Apple Virtualization.framework with per-build micro-VMs

Each build runs in dedicated lightweight VM with hypervisor-level isolation:
- No persistent storage (ephemeral tmpfs only)
- No internet access (localhost socket to host worker agent only)
- Memory encrypted, wiped on completion
- Hardware-isolated vCPUs and RAM

```swift
class BuildWorkerVM {
    func executeBuild(encryptedCode: Data, buildScript: String) async throws -> SignedBuildArtifact {
        // Configure minimal VM: no disk, no network, CPU/RAM quotas
        let vm = VZVirtualMachine(config: createEphemeralConfig())
        try await vm.start()
        defer { Task { try? await vm.stop() } }

        // Stream encrypted code via vsock, build, sign result
        let result = try await sendBuildJob(encryptedCode, buildScript)
        return try await attestAndSign(result)
    }
}
```

**Security properties:**
- VM escape = only way to compromise host (Apple's hypervisor security boundary)
- No code/artifacts persist after build
- Worker agent can't access VM memory/disk directly

---

### 2. Communication Protocol

**Stack:** mTLS + Noise Protocol + E2E Encryption

**Flow:**
1. Worker registers with Secure Enclave attestation → Expo verifies → issues cert
2. Job assignment over mTLS (mutual auth)
3. Worker gets time-limited S3 pre-signed URL for encrypted code download
4. Builds, encrypts result **for user only** (user's pubkey), uploads
5. Expo verifies attestation, delivers to user

**Code never exposed:**
- Expo stores encrypted blobs only
- Worker gets ephemeral decryption key inside VM
- Result encrypted for user before leaving VM
- VM memory wiped on completion

```typescript
interface BuildSubmission {
  encryptedCode: Buffer          // AES-256-GCM encrypted source
  codeHash: string               // SHA-256 of plaintext
  userPublicKey: string          // For worker to encrypt result
  ephemeralKeyEnc: Buffer        // Worker's pubkey encrypts this
}
```

---

### 3. Build Verification

**Approach:** Reproducible Builds + Multi-Worker Verification

- All builds deterministic (same source → same binary hash)
- Critical builds run on 2+ workers in parallel
- Compare output hashes → mismatch = fraud detection
- Each worker signs with Secure Enclave key

```typescript
interface BuildAttestation {
  sourceCodeHash: string
  buildEnvironmentHash: string       // Pinned Docker image
  artifactHash: string               // Output binary
  secureEnclaveAttestation: {
    deviceID: string                 // From Apple attestation
    hardwareFingerprint: string
  }
  signature: string                  // Signed by Secure Enclave
  expoCounterSignature: string       // Expo verifies and counter-signs
}
```

**Tamper detection:**
- If hashes don't match across workers → flag/ban malicious worker
- Run on 3rd worker to find discrepancy
- Fraud = permanent ban + forfeit credits

---

### 4. Worker Authentication

**Technology:** Apple Secure Enclave + App Attest

**Registration:**
1. Generate hardware-bound key pair in Secure Enclave (non-exportable)
2. Request attestation from Apple (proves genuine Mac with intact Secure Enclave)
3. Submit to Expo for verification
4. Expo issues worker certificate

**Authorization tiers:**
- **Probation:** New workers, low-value builds only (public repos)
- **Verified:** Passed probation, standard builds
- **Trusted:** High reputation, can do paid builds
- **Premium:** Certified Macs, enterprise builds

**Properties:**
- Private key never leaves Secure Enclave
- Can't clone worker identity to another device
- Apple-verified hardware authenticity
- Revocable certificates

---

### 5. Resource Isolation

**Technology:** XPC Service + macOS Sandbox + launchd quotas

**Architecture:**
```
┌─────────────────────────────────────┐
│ User's macOS                        │
│ ┌─────────────────────────────────┐ │
│ │ Main App (UI, limited privs)    │ │
│ └──────────────┬──────────────────┘ │
│                │ XPC                 │
│ ┌──────────────▼──────────────────┐ │
│ │ Worker XPC Service (Sandboxed)  │ │
│ │ - Network: Expo endpoints only  │ │
│ │ - No disk read/write (tmp only) │ │
│ │ - CPU quota: 70% max            │ │
│ │ - Memory quota: 8GB max per VM  │ │
│ │ - Process limit: 3 VMs max      │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

**Limits enforced via launchd:**
- CPU throttling (70% max, Background ProcessType)
- Memory hard limit (8GB)
- Aggressive timeout (2 hours max build time)
- Network bandwidth cap (10 MB/s upload)

---

### 6. Failure Handling

**Multi-tier failover:**

```typescript
class BuildOrchestrator {
  async executeBuild(job: BuildJob): Promise<BuildResult> {
    const workers = await this.assignWorkers(job);

    for (const worker of workers) {
      try {
        const result = await Promise.race([
          worker.executeBuild(job),
          timeout(job.estimatedDuration * 2)
        ]);

        if (!await this.verifyIntegrity(result)) {
          await this.flagWorker(worker.id, "integrity_failure");
          continue; // Try next worker
        }

        return result;
      } catch (error) {
        console.warn(`Worker ${worker.id} failed, trying next...`);
      }
    }

    // All mesh workers failed → fallback to Expo hardware
    return await this.fallbackToExpoHardware();
  }
}
```

**Scenarios:**
- Worker offline → reassign build immediately
- Build timeout → try different worker
- Integrity failure → flag worker, investigate fraud
- All workers fail → free fallback to Expo infrastructure

**Long builds:** Checkpoint progress every 10 mins, resume on new worker if crash

---

### 7. Additional Security

**Code protection (minimal exposure):**
- Split source into dependency graph chunks
- Encrypt each chunk separately
- Worker receives chunks progressively (only what's needed per phase)
- Even compromised worker only sees fragments

**Fraud detection:**
- Anomalously fast builds (cached, not actually built)
- Low entropy in outputs (copy-paste attacks)
- Collusion detection (always matches one other worker)
- Suspicious network activity (exfiltration attempts)
- Device fingerprint changes (VM spoofing)

**Privacy:**
- Workers don't see user/project identifiers
- Obfuscated job metadata (no repo URLs, package names)
- Differential privacy on build metrics

---

## Technology Stack

| Component | Technology | Why |
|-----------|-----------|-----|
| VM Isolation | Apple Virtualization.framework | Native macOS, hypervisor isolation, sub-second startup |
| Worker Agent | Swift + XPC Services | macOS sandbox, Secure Enclave access |
| Authentication | Apple Secure Enclave + App Attest | Hardware-bound identity, Apple-verified |
| Transport | mTLS (BoringSSL) | Mutual auth, industry standard |
| Session Crypto | Noise Protocol (XX pattern) | Forward secrecy, post-quantum hybrid |
| Data Encryption | AES-256-GCM | Fast, authenticated encryption |
| Build Verification | Reproducible Builds (SHA-256) | Tamper detection, parallel verification |
| Resource Limits | macOS Sandbox + launchd | Native CPU/memory quotas |
| Backend | Node.js + PostgreSQL | Expo's existing stack |
| Queue | AWS SQS | Build job distribution |
| Storage | S3 with SSE-C | Encrypted storage, user-controlled keys |

---

## Threat Model

| Threat | Mitigation |
|--------|-----------|
| Worker steals user code | E2E encryption, progressive key release, code chunking |
| Worker tampers with build | Reproducible builds, parallel verification, Secure Enclave signing |
| User runs exploits on worker | VM isolation (no persistent storage, no network, hypervisor protection) |
| Worker farms credits (fake builds) | Hash comparison, fraud detection, probation period |
| Worker collusion | Secure Enclave attestation (one identity per Mac), device fingerprinting |
| MITM attack | mTLS + Noise protocol, certificate pinning |
| Worker offline mid-build | Checkpointing, failover to new worker or Expo hardware |
| Resource exhaustion | Sandbox limits, VM quotas, aggressive timeouts |
| Privacy leak | Obfuscated job metadata, no repo URLs sent to worker |

---

## Economic Model

**Worker earnings:**
- Base: 10 credits/CPU-hour
- Multipliers: reliability (1.2x), tier (1.5x), peak demand (2x), verification (1.2x)
- Example: Trusted tier, 95% uptime, peak hours, parallel verification = 43.2 credits/CPU-hour

**Credits redeemable for:**
- Expo build credits (1:1)
- EAS subscription discounts
- Cash payout (100 credits = $1, min $50)

**Expo savings:**
- Mesh handles 70% of free builds
- Paid builds still on dedicated hardware (SLA guarantees)

---

## Unresolved Questions (for user)

1. iOS code signing: User's Apple Developer certs needed - handle without exposing private keys?
2. Credit abuse: Prevent users running worker on own builds to "earn" credits for builds they'd pay for?
3. Bandwidth costs: Workers upload 500MB+ binaries - credits cover egress costs?
4. macOS licensing: Apple EULA restricts virtualization - need special licensing?
5. Cold start: First build needs 10GB+ Xcode/deps download - handle without penalizing users?

---

---

## Security Review Findings (Critical Issues)

### SHOWSTOPPERS IDENTIFIED

1. **Reproducible builds impossible for iOS** - Timestamps, UUIDs, codesigning make hash comparison useless (100% false positive)
2. **Attestation relay attack** - Can proxy through legit Mac while running modified code elsewhere
3. **iOS builds require network** - Xcode needs network for SPM, notarization, provisioning
4. **Virtualization.framework not security boundary** - Convenience isolation, not adversarial (CVE-2023-38606)

### CRITICAL FLAWS

- **E2E encryption theatre** - Keys exist in VM memory, worker can lie about progress, chunking pointless (Xcode needs full source)
- **Economic gaming inevitable** - Self-service (run worker, build on self), minimum viable work, Sybil ($600 Mac = new identity)
- **No consensus protocol** - When verifiers disagree, who decides? Clock skew breaks attestation/timeouts
- **Debugging impossible** - Encrypted logs, ephemeral VMs, no forensics capability

### WHAT FAILS FIRST (Production Prediction)

1. Day 1: Hash verification (100% false positive)
2. Week 1: Build timeouts (large apps >2hrs)
3. Week 1: Network-less builds fail (SPM/CocoaPods)
4. Month 1: Credit gaming begins
5. Month 1: Support overwhelmed (can't debug encrypted failures)

### RECOMMENDATIONS: SIMPLIFY

**Remove:**
- Hash-based verification (doesn't work)
- Noise protocol (mTLS sufficient)
- Progressive key release (false security)
- Chunked delivery (all-or-nothing anyway)

**Replace:**
- Hash verification → Apple notarization receipt verification
- "Trustless" model → Reputation + financial bonds + insurance

---

## REVISED ARCHITECTURE: Practical Prototype

### Core Principle Shift

**From:** "Zero-trust, cryptographically verified, trustless mesh"
**To:** "Reputation-based trust with financial consequences and insurance"

Accept security is **probabilistic**, not absolute. Design for "trust but verify with consequences."

### Simplified Stack

```
User submits build
    ↓
Expo backend (reputation check)
    ↓
Assign to trusted worker (mTLS)
    ↓
Worker runs in VM (defense-in-depth, not absolute)
    ↓
Build → Apple notarization (verification)
    ↓
Deliver to user + log attestation
    ↓
User verifies signature + notarization receipt
```

### Key Changes

1. **Verification:** Use Apple's notarization instead of hash comparison
   - Worker builds, signs with distribution cert, submits to Apple
   - Apple notarizes (malware check)
   - Notarization receipt = proof of integrity
   - User verifies Apple signature chain (built-in to iOS)

2. **Network:** Allow proxied network access
   - VM can reach Apple servers (provisioning, notarization)
   - Proxy logs all requests (forensics)
   - Block non-Apple destinations

3. **Trust Model:** Reputation + bonds + insurance
   - Workers stake $100 bond (forfeit on misbehavior)
   - Reputation score (0-100) from successful builds
   - New workers = probation tier (low-value builds only)
   - High-value builds = trusted tier only (95+ reputation)
   - Expo insurance covers verified breaches (up to $X)

4. **Crypto:** Just mTLS + age encryption
   - Remove Noise protocol complexity
   - age for artifact encryption (simple, audited)
   - User gets age-encrypted artifact, decrypts locally

5. **Timeouts:** 4 hours default, 8 hours for large apps

---

## PROTOTYPE IMPLEMENTATION PLAN

### Goal

Build a **real, self-hosted distributed build system** that proves: "User Mac builds another user's Expo app in background."

Not a mock - this should be usable by you and colleagues immediately. Later, Expo can integrate it into EAS infrastructure.

### Scope (MVP - 6 weeks)

**Three components:**

1. **Free Agent App** (macOS, Swift)
   - Installable Mac app with menu bar UI
   - Polls central controller for jobs
   - Downloads build packages
   - Spawns macOS VM, executes Xcode builds
   - Code signing & notarization in VM
   - Uploads results back to controller
   - Shows status, build count, resource usage

2. **Central Controller** (Node.js server)
   - Self-hosted (runs on Mac/Linux/VPS)
   - REST API for job submission & worker polling
   - Job queue (in-memory for prototype)
   - Worker registry (SQLite)
   - File storage (local filesystem, not S3)
   - Web UI to view builds & workers

3. **Submit CLI** (Node.js)
   - Command: `expo-controller submit ./my-app --certs ./certs/`
   - Uploads Expo project to controller
   - Provides signing certs & credentials
   - Polls for build completion
   - Downloads IPA when ready

**Out of scope (defer to later):**
- Expo EAS integration (prototype is standalone)
- Android builds (iOS first)
- Credit/payment system (track metrics only)
- S3/cloud storage (local files for now)
- Encryption (trust network for prototype)
- Production hardening
- Advanced fraud detection

### Architecture (Prototype - Self-Hosted)

```
┌──────────────────────────────────────────────────────────┐
│ Developer's Machine                                      │
│                                                          │
│  $ expo-controller submit ./my-app --certs ./certs/     │
│                                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │ Submit CLI (Node.js)                           │    │
│  │ - Zips Expo project                            │    │
│  │ - Uploads to controller                        │    │
│  │ - Polls for completion                         │    │
│  └──────────────────┬─────────────────────────────┘    │
└─────────────────────┼──────────────────────────────────┘
                      │ HTTP POST
                      ▼
┌──────────────────────────────────────────────────────────┐
│ Central Controller (self-hosted, Node.js)               │
│ $ expo-controller start                                 │
│                                                          │
│ - Job queue (in-memory)                                 │
│ - Worker registry (SQLite)                              │
│ - File storage (local disk)                             │
│ - Web UI (view builds & workers)                        │
│                                                          │
│ API:                                                     │
│ POST /api/builds/submit                                 │
│ GET  /api/builds/:id/status                             │
│ GET  /api/builds/:id/download                           │
│ POST /api/workers/register                              │
│ GET  /api/workers/poll                                  │
│ POST /api/workers/upload                                │
└──────────────┬───────────────────────────────────────────┘
               │ HTTP (polling)
               ▼
┌──────────────────────────────────────────────────────────┐
│ Colleague's Machine (Worker)                            │
│                                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │ Free Agent App (macOS, menu bar)               │    │
│  │ - Polls controller every 30s                   │    │
│  │ - Downloads build packages                     │    │
│  │ - Spawns VM, executes build                    │    │
│  │ - Uploads results                              │    │
│  └──────────────────┬─────────────────────────────┘    │
│                     │                                    │
│  ┌──────────────────▼─────────────────────────────┐    │
│  │ Build VM (Virtualization.framework)            │    │
│  │ - macOS 14+                                    │    │
│  │ - Xcode 15+                                    │    │
│  │ - Runs: eas build --local --platform ios       │    │
│  │ - Code signing with provided certs             │    │
│  │ - Ephemeral disk (wiped after)                 │    │
│  └────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

**Key Flow:**

1. **Developer submits build:**
   ```bash
   expo-controller submit ./my-app \
     --cert ./certs/dist.p12 \
     --profile ./profiles/adhoc.mobileprovision \
     --apple-id me@example.com \
     --apple-password "app-specific-password"
   ```

2. **Controller receives & queues:**
   - Stores source code zip
   - Stores signing credentials
   - Creates build job
   - Returns build ID

3. **Free Agent polls & picks up job:**
   - Downloads build package
   - Downloads credentials

4. **Free Agent builds in VM:**
   - Spawns macOS VM
   - Installs certs in VM keychain
   - Runs `eas build --local --platform ios`
   - Signs IPA
   - Notarizes with Apple
   - Destroys VM (wipes credentials)

5. **Free Agent uploads result:**
   - Uploads IPA to controller
   - Uploads build logs

6. **Developer downloads:**
   ```bash
   expo-controller download <build-id>
   ```

**This is a real, working system - just self-hosted instead of Expo-hosted.**

### Implementation Steps

#### Week 1: Central Controller (Server)

**File:** `controller/src/index.ts`
```typescript
import express from 'express';
import multer from 'multer';
import sqlite3 from 'sqlite3';

// Central controller server:
// POST /api/builds/submit - Upload Expo project + certs
// GET  /api/builds/:id/status - Check build status
// GET  /api/builds/:id/download - Download IPA
// POST /api/workers/register - Worker registers
// GET  /api/workers/poll - Worker polls for jobs
// POST /api/workers/upload - Worker uploads result
```

**Tasks:**
- [ ] Express server with REST API endpoints
- [ ] SQLite schema: builds, workers, build_logs
- [ ] File upload handling (multer for large zips)
- [ ] Job queue (in-memory array, FIFO)
- [ ] Worker assignment logic (round-robin)
- [ ] File storage (local filesystem: ./storage/builds/, ./storage/results/)
- [ ] Basic web UI (Express + EJS templates)
- [ ] CLI command: `expo-controller start --port 3000`

#### Week 2: Submit CLI (Client)

**File:** `packages/cli/src/commands/submit.ts`
```typescript
import { Command } from 'commander';
import FormData from 'form-data';
import axios from 'axios';
import fs from 'fs';
import archiver from 'archiver';

// CLI for submitting builds:
// expo-controller submit ./my-app --cert ./cert.p12 --profile ./adhoc.mobileprovision
```

**Tasks:**
- [ ] CLI framework (commander.js)
- [ ] Zip Expo project directory
- [ ] Upload to controller (multipart/form-data)
- [ ] Handle signing cert & provisioning profile uploads
- [ ] Poll for build completion (with progress bar)
- [ ] Download IPA when ready
- [ ] Config file support (~/.expo-controller/config.json for controller URL)
- [ ] Commands: `submit`, `status <id>`, `download <id>`, `list`
- [ ] Make executable: `npm link` or `npx expo-controller`

#### Week 3-4: Free Agent App (Worker)

**Files:**
- `free-agent/Sources/FreeAgent/main.swift` - App entry point, menu bar UI
- `free-agent/Sources/FreeAgent/WorkerService.swift` - Polling & job execution
- `free-agent/Sources/BuildVM/VMManager.swift` - VM lifecycle

```swift
// Menu bar app that:
// 1. Shows status icon (idle/building/paused)
// 2. Registers with controller on startup
// 3. Polls controller every 30s for jobs
// 4. Downloads build package + certs
// 5. Spawns VM, executes build
// 6. Uploads result
// 7. Shows build count, earnings (future), resource usage

class BuildVM {
    func executeIOSBuild(
        sourceCodePath: URL,
        signingCerts: URL,
        outputPath: URL
    ) async throws -> BuildResult {
        let vm = try createMacOSVM()
        try await vm.start()
        defer { Task { try? await vm.stop() } }

        try await mountSource(sourceCodePath)
        try await installSigningCerts(signingCerts)

        let result = try await vm.execute("""
            cd /build
            npm install
            npx pod-install
            eas build --platform ios --local --no-wait
        """)

        try await extractArtifact(outputPath)
        return BuildResult(success: result.exitCode == 0, logs: result.stdout)
    }
}
```

**Tasks:**
- [ ] Xcode project with menu bar app (NSStatusBar)
- [ ] SwiftUI settings window (controller URL, resource limits)
- [ ] Worker registration (device info, capabilities)
- [ ] Job polling loop (every 30s when idle)
- [ ] Download build package from controller
- [ ] **Research: UTM vs raw Virtualization.framework**
  - UTM has nice setup flow, CLI support (`utmctl`)
  - Could simplify VM management significantly
  - Need to test headless mode, startup time, embedding
- [ ] macOS VM image creation (via UTM or raw IPSW restore)
- [ ] Xcode installation in VM (20GB+ - consider pre-baked image)
- [ ] VM spawn + code signing cert installation
- [ ] virtio-fs mount for source code (or UTM's shared folder)
- [ ] SSH/script execution in VM
- [ ] IPA extraction from VM
- [ ] Upload result to controller
- [ ] Resource monitoring (CPU/mem display)
- [ ] VM cleanup (wipe disk, destroy)

#### Week 5-6: Integration + Testing (iOS)

**File:** `test/integration/end-to-end.test.ts`
```typescript
test('user submits iOS build, worker executes, user downloads IPA', async () => {
    // 1. User: Upload simple Expo app source + signing certs
    const jobId = await backend.submitJob({
        sourceUrl: 's3://test-bucket/simple-expo-app.zip',
        signingCerts: 's3://test-bucket/certs/dist-cert.p12',
        provisioningProfile: 's3://test-bucket/profiles/adhoc.mobileprovision',
        buildType: 'ios'
    });

    // 2. Worker: Poll, receive job, build
    // (automated by running worker agent)

    // 3. Wait for completion (poll job status)
    await waitForCompletion(jobId, { timeout: 1_200_000 }); // 20 min

    // 4. User: Download artifact
    const artifact = await backend.downloadArtifact(jobId);

    // 5. Verify: IPA exists and is signed
    expect(artifact.type).toBe('application/octet-stream'); // IPA
    expect(await verifyIPASignature(artifact.path)).toBe(true);
});
```

**Tasks:**
- [ ] Create test Expo app (minimal "Hello World" iOS)
- [ ] Generate test signing certs (development/adhoc distribution)
- [ ] End-to-end test: submit → build → download IPA
- [ ] Manual testing with real worker Mac
- [ ] Performance measurement (build time 15-20 min, resource usage)
- [ ] Document findings (what worked, what didn't)
- [ ] Measure Xcode/VM startup overhead vs build time

---

## Critical Files (Prototype)

### Central Controller (Node.js Server)
- `/controller/src/index.ts` - Express app, REST API
- `/controller/src/db/schema.sql` - SQLite schema (builds, workers, logs)
- `/controller/src/services/JobQueue.ts` - Job queue & assignment
- `/controller/src/services/FileStorage.ts` - Local file storage
- `/controller/src/views/` - Web UI templates (EJS)
- `/controller/package.json` - Dependencies & CLI bin

### Submit CLI (Node.js Client)
- `/cli/src/index.ts` - CLI entry point (commander)
- `/cli/src/commands/submit.ts` - Submit build command
- `/cli/src/commands/status.ts` - Check build status
- `/cli/src/commands/download.ts` - Download IPA
- `/cli/src/api-client.ts` - HTTP client for controller API
- `/cli/package.json` - CLI executable config

### Free Agent App (Swift/macOS)
- `/free-agent/Sources/FreeAgent/main.swift` - App entry, menu bar UI
- `/free-agent/Sources/FreeAgent/WorkerService.swift` - Polling & coordination
- `/free-agent/Sources/FreeAgent/SettingsView.swift` - SwiftUI config window
- `/free-agent/Sources/BuildVM/VMManager.swift` - Virtualization.framework
- `/free-agent/Sources/BuildVM/XcodeBuildExecutor.swift` - Run builds in VM
- `/free-agent/Info.plist` - App metadata, entitlements

### VM Setup Scripts
- `/vm-setup/create-macos-vm.sh` - Download IPSW, create base image
- `/vm-setup/install-xcode.sh` - Install Xcode in VM (20GB+)
- `/vm-setup/configure-keychain.sh` - Setup for code signing

### Testing
- `/test/integration/full-flow.test.ts` - End-to-end test
- `/test/fixtures/simple-expo-app/` - Minimal test iOS app
- `/test/fixtures/test-cert.p12` - Test signing certificate

---

## Success Criteria (Prototype)

**Complete workflow must work:**

1. **Self-hosted controller:** You can run `expo-controller start` on your Mac
2. **Worker registration:** Colleague installs Free Agent app, registers with your controller
3. **Build submission:** You run `expo-controller submit ./my-app --cert ./cert.p12` successfully
4. **Worker picks up job:** Free Agent automatically downloads & starts building
5. **Build succeeds:** Worker builds in VM, signs IPA, uploads result
6. **Download works:** You run `expo-controller download <build-id>` and get working IPA
7. **Isolated:** Build runs in macOS VM, disk wiped after completion
8. **Measurable:** Track build time (target: 15-20 min), resource usage, success rate

**NOT success criteria (defer):**
- Expo EAS integration
- Encryption/security hardening
- Credit/payment system
- Production readiness
- Scalability
- Notarization (manual for prototype)

---

## Unresolved Questions (Revised - iOS Focus)

1. **Xcode EULA:** Can third parties run Xcode builds legally? (CRITICAL - must resolve before launch)
2. **VM technology:** UTM vs raw Virtualization.framework?
   - UTM: Easier setup, CLI support, open source
   - Raw: More control, potentially faster
   - Need to benchmark startup time, resource usage
3. **iOS signing:** User's Apple Developer certs - how handle without exposing private keys? (P12 password in secure enclave?)
4. **Xcode installation:** 20GB+ download per VM - cache on worker? Reuse base image? (affects build time dramatically)
5. **macOS licensing:** Apple restricts macOS VM usage - need special licensing for distributed builds?
6. **Provisioning profiles:** Automatic vs manual provisioning - which to support first?
7. **VM lifecycle:** Keep warm between builds or cold start each time?
   - Warm: Faster (no boot time), but higher idle resource usage
   - Cold: Clean slate, but 30-60s startup penalty
8. **Credit abuse prevention:** Self-service gaming - detect via behavioral analysis? (defer to v2)
9. **Bandwidth costs:** 500MB IPAs - who pays egress? (assume Expo absorbs for prototype)
10. **Worker incentives:** Will users actually run this? What credit rate makes sense? (need prototype data)

---

## Next Steps

1. User approval of prototype plan
2. Start Week 1: Worker Agent implementation
3. Iterate based on learnings
