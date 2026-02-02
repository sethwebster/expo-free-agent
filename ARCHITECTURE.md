# Expo Free Agent Architecture

Comprehensive system architecture documentation for the distributed, self-hosted Expo build system.

**Last Updated:** 2026-02-02

---

## Table of Contents

1. [System Overview](#system-overview)
2. [High-Level Architecture](#high-level-architecture)
3. [Component Deep Dive](#component-deep-dive)
4. [Complete Build Flow](#complete-build-flow)
5. [Authentication Chain](#authentication-chain)
6. [Data Flow](#data-flow)
7. [Technology Stack](#technology-stack)
8. [Critical Design Decisions](#critical-design-decisions)
9. [Performance Characteristics](#performance-characteristics)
10. [Security Model](#security-model)
11. [Fault Tolerance](#fault-tolerance)
12. [Deployment Architecture](#deployment-architecture)

---

## System Overview

Expo Free Agent is a **distributed build system** that enables developers to build iOS/Android applications on their own Mac hardware with complete VM isolation. It consists of three main components orchestrated to execute builds securely and efficiently.

### Core Principles

1. **VM Isolation**: Every build runs in an ephemeral macOS VM, destroyed after completion
2. **Zero Trust**: Multi-layer authentication prevents unauthorized access
3. **Atomic Operations**: Database transactions guarantee zero race conditions
4. **Self-Healing**: Automatic recovery from crashes, network failures, and token expiration
5. **Polling-Based**: Works behind NAT/firewalls without persistent connections

### Design Philosophy

- **Simplicity over complexity**: Polling instead of WebSockets, PostgreSQL instead of distributed queues
- **Fail fast, fail loud**: No silent failures or degraded modes
- **Security by default**: Multiple authentication layers, ephemeral credentials
- **Production-grade from day 1**: Battle-tested patterns (Elixir/OTP, Tart VMs)

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          DEVELOPER MACHINE                              │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  CLI Tool (TypeScript/Bun)                                       │  │
│  │  - Bundle project source                                         │  │
│  │  - Upload to controller (HTTPS)                                  │  │
│  │  - Poll for completion                                           │  │
│  │  - Download artifacts                                            │  │
│  └─────────────────────────┬────────────────────────────────────────┘  │
└────────────────────────────┼───────────────────────────────────────────┘
                             │
                             │ HTTPS + Build Token
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     CONTROLLER (Elixir/Phoenix)                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  API Server (Bandit HTTP/2)                                      │  │
│  │  - RESTful endpoints                                             │  │
│  │  - Multi-layer authentication                                    │  │
│  │  - Streaming file uploads/downloads                              │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  QueueManager (GenServer)                                        │  │
│  │  - Atomic build assignment                                       │  │
│  │  - SELECT FOR UPDATE SKIP LOCKED                                 │  │
│  │  - Auto-recovery on startup                                      │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  PostgreSQL Database                                             │  │
│  │  - Builds (pending → assigned → completed)                       │  │
│  │  - Workers (access tokens, heartbeats)                           │  │
│  │  - Build logs                                                    │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  File Storage                                                    │  │
│  │  - Source tarballs                                               │  │
│  │  - Signing certificates (ephemeral)                              │  │
│  │  - Build artifacts (IPAs/APKs)                                   │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             │ Polling (30s interval)
                             │ Worker Token + API Key
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        WORKER MACHINE (macOS)                           │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  FreeAgent.app (Swift Menu Bar App)                              │  │
│  │  - Poll controller every 30s                                     │  │
│  │  - Download source/certs on assignment                           │  │
│  │  - Manage VM lifecycle                                           │  │
│  │  - Upload results                                                │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  Tart VM Manager                                                 │  │
│  │  - Clone template VM                                             │  │
│  │  - Mount build-config                                            │  │
│  │  - Start/stop VMs                                                │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│  ┌────────────────────────────────────────────────────────────────┐   │
│  │  EPHEMERAL VM (macOS via Apple Virtualization Framework)       │   │
│  │  ┌──────────────────────────────────────────────────────────┐  │   │
│  │  │  bootstrap.sh (auto-runs on start)                       │  │   │
│  │  │  1. Authenticate with OTP token                          │  │   │
│  │  │  2. Receive VM token                                     │  │   │
│  │  │  3. Fetch certificates (base64-encoded JSON)             │  │   │
│  │  │  4. Write "vm-ready" signal                              │  │   │
│  │  └──────────────────────────────────────────────────────────┘  │   │
│  │  ┌──────────────────────────────────────────────────────────┐  │   │
│  │  │  Build Execution                                         │  │   │
│  │  │  1. Download source.zip from controller                  │  │   │
│  │  │  2. Extract to /tmp/build-{id}                           │  │   │
│  │  │  3. Install certs to keychain                            │  │   │
│  │  │  4. Execute build (xcodebuild/gradlew)                   │  │   │
│  │  │  5. Stream logs to controller                            │  │   │
│  │  │  6. Upload artifact                                      │  │   │
│  │  │  7. Write "build-complete" signal                        │  │   │
│  │  └──────────────────────────────────────────────────────────┘  │   │
│  │                                                                 │   │
│  │  Destroyed after build (certs gone forever)                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Component Deep Dive

### 1. Controller (Elixir/Phoenix/PostgreSQL)

**Purpose:** Central orchestration server managing build queue, worker coordination, and authentication.

#### Technology Choices

- **Elixir/OTP**: Erlang VM provides battle-tested concurrency, supervision trees for automatic crash recovery
- **Phoenix Framework**: REST API, connection pooling (100+ concurrent connections)
- **PostgreSQL**: `SELECT FOR UPDATE SKIP LOCKED` prevents race conditions atomically
- **Bandit**: HTTP/2 server for efficient streaming

#### Core Modules

```
lib/expo_controller/
├── builds.ex                 # Build lifecycle management
├── workers.ex                # Worker registration, heartbeats
├── diagnostics.ex            # Health monitoring
└── file_storage.ex           # Path traversal-safe file ops

lib/expo_controller_web/
├── controllers/
│   ├── build_controller.ex   # Build submission, status, download
│   └── worker_controller.ex  # Poll, register, upload
└── plugs/
    └── auth.ex               # Multi-layer authentication
```

#### OTP Supervision Tree

```
Application Supervisor
  ├─ Bandit (HTTP server)
  ├─ Ecto.Repo (database connection pool)
  ├─ Phoenix.PubSub (real-time events)
  └─ QueueManager (GenServer)
      - Rebuilds queue from database on startup
      - Serializes queue access (no race conditions)
```

#### Key Features

- **Atomic build assignment**: `SELECT FOR UPDATE SKIP LOCKED` guarantees exactly one worker per build
- **Worker token rotation**: Every poll rotates access token (90s TTL)
- **Streaming uploads/downloads**: No buffering (10MB memory vs 500MB in TypeScript version)
- **Automatic recovery**: OTP supervisors restart crashed processes
- **Connection pooling**: 100+ workers polling simultaneously

#### Migration from TypeScript

**Before (TypeScript/Bun/SQLite):**
- SQLite single-writer bottleneck (~10 builds/sec)
- Race conditions in build assignment
- In-memory queue lost on crash
- 500MB memory per build (buffering)

**After (Elixir/Phoenix/PostgreSQL):**
- 100+ builds/sec throughput (PostgreSQL connection pooling)
- Zero race conditions (`SELECT FOR UPDATE SKIP LOCKED`)
- Queue restored from database on startup
- 10MB memory per build (streaming)

See [ADR-0009](./docs/adr/0009-migrate-controller-to-elixir.md) for full rationale.

---

### 2. Worker (Swift/macOS Menu Bar App)

**Purpose:** Runs on Mac hardware, manages VM lifecycle, executes builds in isolation.

#### Architecture

```
FreeAgent.app (Swift)
├── WorkerService.swift       # Polling, coordination
├── TartVMManager.swift       # VM lifecycle (Tart CLI)
├── BuildExecutor.swift       # Build orchestration
└── WorkerConfiguration.swift # Settings persistence
```

#### Polling Loop

```swift
while !Task.isCancelled && isActive {
    // Poll controller every 30s
    if let job = try await pollForJob() {
        await executeJob(job)
    }

    try await Task.sleep(for: .seconds(30))
}
```

**Why polling instead of WebSockets?**
- Works behind NAT/firewalls (home networks)
- Stateless server (no connection management)
- Simple error recovery (just poll again)
- Acceptable latency for 15-30 minute builds

See [ADR-0007](./docs/adr/0007-polling-based-worker-protocol.md) for alternatives considered.

#### VM Lifecycle

1. **Clone template**: `tart clone sequoia-vanilla vm-{uuid}`
2. **Mount config**: Write `build-config.json` + `bootstrap.sh` to mounted directory
3. **Start VM**: `tart run vm-{uuid}`
4. **Wait for bootstrap**: Poll for `vm-ready` signal file
5. **Execute build**: VM downloads source, builds, uploads artifact
6. **Destroy VM**: `tart delete vm-{uuid}` (ephemeral, certs gone)

**Template VM preparation:**
- macOS 15.2 (Sequoia)
- Xcode 16.2
- Homebrew + Node.js 20 + Bun + CocoaPods
- Auto-run bootstrap on startup (`LaunchAgent`)

#### Build Execution Flow

```
Worker receives job → Download source.zip
                   → Clone template VM
                   → Mount build-config/ (OTP token, URLs)
                   → Start VM
                   → VM runs bootstrap.sh
                   → VM authenticates with OTP
                   → VM receives VM token
                   → VM fetches certs (iOS only)
                   → VM downloads source.zip
                   → VM extracts and builds
                   → VM uploads artifact
                   → Worker destroys VM
                   → Worker reports completion
```

---

### 3. CLI (TypeScript/Bun)

**Purpose:** Developer-facing tool for submitting builds and downloading artifacts.

#### Commands

```bash
# Submit build
expo-build submit --platform ios

# Check status
expo-build status <build-id>

# Download artifact
expo-build download <build-id>

# List all builds
expo-build list
```

#### Workflow

1. **Bundle project**: Create `source.tar.gz` with all files
2. **Upload**: `POST /api/builds` with multipart form data
3. **Poll status**: `GET /api/builds/{id}/status` every 10s
4. **Download**: `GET /api/builds/{id}/artifacts/app.ipa`

#### Authentication

- API key in `~/.expo-free-agent/config.json` or `EXPO_CONTROLLER_API_KEY` env var
- Build token returned on submission (scoped to that build only)

---

## Complete Build Flow

### Phase 1: Build Submission (Developer → Controller)

```
Developer machine:
  $ expo-build submit --platform ios

CLI:
  1. Bundle project → source.tar.gz (~10-50 MB)
  2. POST /api/builds
     - Headers: X-API-Key
     - Body: multipart form data (source.tar.gz, metadata)
  3. Receive: {build_id, access_token}

Controller:
  1. Validate API key
  2. Generate build_id (UUID)
  3. Store source.tar.gz → data/builds/{build_id}/source/
  4. Generate access_token (32-byte nanoid)
  5. INSERT INTO builds (id, status='pending', access_token)
  6. INSERT INTO jobs (build_id, status='pending')
  7. Return {build_id, access_token} to CLI

Database state:
  builds: {id, status='pending', source_path, access_token}
  jobs: {build_id, status='pending', submitted_at}
```

---

### Phase 2: Worker Polling & Job Assignment (Worker ← Controller)

```
Worker (every 30 seconds):
  GET /api/workers/poll
  Headers:
    X-API-Key: <api-key>
    X-Worker-Token: <current-access-token>

Controller:
  1. Validate API key
  2. Lookup worker by token:
     SELECT * FROM workers
     WHERE access_token = <token>
       AND access_token_expires_at > NOW()
  3. If not found → 401 Unauthorized (worker re-registers)
  4. Heartbeat + token rotation:
     UPDATE workers
     SET last_seen_at = NOW(),
         access_token = generate_token(),
         access_token_expires_at = NOW() + 90 seconds
  5. Atomic build assignment:
     BEGIN TRANSACTION;
       SELECT * FROM builds
       WHERE status = 'pending'
       ORDER BY submitted_at ASC
       LIMIT 1
       FOR UPDATE SKIP LOCKED;  -- Only this worker gets lock

       UPDATE builds
       SET status = 'assigned',
           worker_id = <worker-id>
       WHERE id = <build-id>;

       UPDATE workers
       SET status = 'building'
       WHERE id = <worker-id>;
     COMMIT;
  6. Generate OTP token (5-minute TTL, single-use)
  7. Return:
     {
       job: {
         id: <build-id>,
         platform: 'ios',
         source_url: '/api/builds/{id}/source'
       },
       access_token: <new-token>,
       otp_token: <vm-bootstrap-token>
     }

Worker:
  1. Update configuration.accessToken = new-token
  2. Store OTP token for VM bootstrap
  3. Proceed to download phase
```

**Race Condition Prevention:**

`FOR UPDATE SKIP LOCKED` ensures:
- Worker A locks build #123 → Workers B & C skip it
- Worker B locks build #124 → Workers A & C skip it
- Exactly one worker per build, guaranteed by PostgreSQL

**Token Rotation:**

```
T=0s:   Poll → Token A (expires T=90s)
T=30s:  Poll → Token B (expires T=120s), Token A still valid
T=60s:  Poll → Token C (expires T=150s), Token A expired
T=90s:  Poll → Token D (expires T=180s), Token B expired
```

Safety margin: 60 seconds (2 missed polls before expiration).

See [ADR-0010](./docs/adr/0010-worker-token-rotation.md) for security analysis.

---

### Phase 3: VM Creation & Bootstrap (Worker → VM → Controller)

```
Worker:
  1. Clone template VM:
     $ tart clone sequoia-vanilla vm-<build-id>

  2. Create build-config directory:
     build-config/
       ├── build-config.json
       │   {
       │     "buildId": "<build-id>",
       │     "workerId": "<worker-id>",
       │     "controllerURL": "http://controller:3000",
       │     "otpToken": "<5-min-single-use-token>",
       │     "platform": "ios"
       │   }
       └── bootstrap.sh
           #!/bin/bash
           # Authenticate with OTP → receive VM token
           # Fetch certificates (iOS only)
           # Download source.zip
           # Write "vm-ready" signal

  3. Start VM:
     $ tart run --dir build-config:/mnt/build-config vm-<build-id>

VM auto-runs bootstrap.sh on startup:
  1. Authenticate with controller:
     POST /api/vm/auth
     Headers:
       X-API-Key: <api-key>
       X-OTP-Token: <otp-token>
     Response:
       {
         vm_token: <24-hour-token-scoped-to-build>,
         build_id: <build-id>
       }

  2. Fetch certificates (iOS only):
     GET /api/builds/<build-id>/certs-secure
     Headers:
       X-API-Key: <api-key>
       X-VM-Token: <vm-token>
     Response:
       {
         p12: "<base64-encoded>",
         p12Password: "<password>",
         keychainPassword: "<password>",
         provisioningProfiles: ["<base64>", ...]
       }

  3. Install certificates:
     $ security create-keychain -p <password> build.keychain
     $ echo "<base64-p12>" | base64 -d > cert.p12
     $ security import cert.p12 -k build.keychain -P <p12-password>
     $ security set-key-partition-list -S apple-tool:,apple: \
         -k <password> build.keychain
     $ cp provisioning-profiles/* \
         ~/Library/MobileDevice/Provisioning\ Profiles/

  4. Write signal:
     $ touch /mnt/build-config/vm-ready

Worker:
  Poll for /mnt/build-config/vm-ready signal
  When found → proceed to build execution
```

**OTP Token Security:**

- 5-minute TTL (expires before worker can reuse)
- Single-use (marked as consumed after authentication)
- Scoped to specific build (prevents cross-build impersonation)
- VM token received is 24-hour but scoped to build

**Certificate Isolation:**

- Certificates fetched inside VM (worker never sees them)
- Stored in ephemeral keychain (`build.keychain`)
- VM destroyed after build → certs gone forever
- No persistence across builds

---

### Phase 4: Build Execution (VM)

```
VM (running inside ephemeral Tart VM):
  1. Download source:
     $ curl -H "X-API-Key: <key>" \
            -H "X-VM-Token: <vm-token>" \
            <controller>/api/builds/<id>/source \
            -o source.zip

  2. Extract:
     $ unzip source.zip -d /tmp/build-<id>
     $ cd /tmp/build-<id>

  3. Build:
     iOS:
       $ npm install
       $ npx pod-install
       $ xcodebuild -workspace ios/App.xcworkspace \
                    -scheme App \
                    -configuration Release \
                    -archivePath build/App.xcarchive \
                    archive
       $ xcodebuild -exportArchive \
                    -archivePath build/App.xcarchive \
                    -exportPath build/ \
                    -exportOptionsPlist exportOptions.plist
       → build/App.ipa

     Android:
       $ npm install
       $ cd android
       $ ./gradlew assembleRelease
       → app/build/outputs/apk/release/app-release.apk

  4. Stream logs (parallel task):
     POST /api/builds/<id>/logs (chunked transfer)
     Headers:
       X-API-Key: <key>
       X-VM-Token: <vm-token>
     Body: (stream build output)

  5. Upload artifact:
     POST /api/builds/<id>/artifacts
     Headers:
       X-API-Key: <key>
       X-VM-Token: <vm-token>
     Body: multipart form data (app.ipa or app.apk)

  6. Write completion signal:
     $ touch /mnt/build-config/build-complete

Worker:
  Poll for /mnt/build-config/build-complete
  When found:
    1. Destroy VM: $ tart delete vm-<build-id>
    2. Report to controller:
       POST /api/workers/upload
       {
         build_id: <id>,
         worker_id: <worker-id>,
         success: true
       }
```

**Build Timeout:**

- Default: 30 minutes (configurable)
- Worker monitors VM process
- If timeout exceeded → kill VM, mark build failed

**Parallel Execution:**

- Log streaming runs concurrently with build
- Telemetry (CPU, memory) sent every 10s
- Doesn't block artifact upload

---

### Phase 5: Cleanup & Result Retrieval (Worker → Controller → Developer)

```
Worker:
  1. Destroy VM:
     $ tart delete vm-<build-id>
     (Certs in keychain gone forever)

  2. Update controller:
     POST /api/workers/upload
     {
       build_id: <id>,
       worker_id: <worker-id>,
       success: true,
       artifact_path: "<uploaded-path>"
     }

Controller:
  1. Update database:
     BEGIN TRANSACTION;
       UPDATE builds
       SET status = 'completed',
           completed_at = NOW(),
           result_path = <artifact-path>
       WHERE id = <build-id>;

       UPDATE workers
       SET status = 'idle',
           builds_completed = builds_completed + 1
       WHERE id = <worker-id>;
     COMMIT;

  2. Return 200 OK to worker

Developer (CLI polling every 10s):
  GET /api/builds/<id>/status
  Response:
    {
      status: 'completed',
      artifacts: [
        {
          name: 'App.ipa',
          size: 52428800,
          url: '/api/builds/<id>/artifacts/App.ipa'
        }
      ]
    }

  Download artifact:
    GET /api/builds/<id>/artifacts/App.ipa
    Headers:
      X-API-Key: <key>
      X-Build-Token: <access-token>

    Save to: ./App.ipa
```

**Cleanup Guarantees:**

- VM destroyed even if build fails
- Temporary files removed from worker
- Database transaction ensures consistent state
- No orphaned builds or hung VMs

---

## Parallel: Monitoring & Fault Tolerance

### Heartbeat Monitoring

```
Background job (runs every 60s):
  SELECT id, last_seen_at
  FROM workers
  WHERE status != 'offline'
    AND last_seen_at < NOW() - INTERVAL '5 minutes'

  For each stale worker:
    1. Mark offline:
       UPDATE workers SET status = 'offline' WHERE id = <worker-id>

    2. Reassign builds:
       UPDATE builds
       SET status = 'pending',
           worker_id = NULL,
           assigned_at = NULL
       WHERE worker_id = <worker-id>
         AND status IN ('assigned', 'building')
```

**Recovery Time:**
- Worker crash detected in 5 minutes
- Builds reassigned immediately
- Available for next worker poll (within 30 seconds)

---

### Worker Crash Recovery

```
Graceful shutdown (user quits app):
  Worker sends:
    POST /api/workers/unregister
    Headers:
      X-API-Key: <key>
      X-Worker-Token: <token>

  Controller reassigns builds:
    UPDATE builds
    SET status = 'pending', worker_id = NULL
    WHERE worker_id = <worker-id>
      AND status IN ('assigned', 'building')

  Returns: {builds_reassigned: 2}

Ungraceful shutdown (crash, kill -9):
  - No unregister request sent
  - Heartbeat monitor detects staleness after 5 min
  - Builds reassigned automatically
```

---

### Token Expiration Recovery

```
Worker poll with expired token:
  GET /api/workers/poll
  Headers:
    X-Worker-Token: <expired-token>

  Controller:
    SELECT * FROM workers
    WHERE access_token = <expired-token>
      AND access_token_expires_at > NOW()

    Returns: NULL (token expired)

  Response: 401 Unauthorized

Worker auto-recovery:
  1. Clear credentials:
     configuration.workerID = nil
     configuration.accessToken = nil

  2. Re-register:
     POST /api/workers/register
     Headers: X-API-Key
     Body: {name, capabilities}

  3. Receive new credentials:
     {id: <new-or-existing-worker-id>, access_token: <new-token>}

  4. Resume polling (transparent to operator)
```

**No Operator Intervention Required:**
- Worker detects 401/404 responses
- Automatically re-registers
- Continues polling seamlessly

---

## Authentication Chain

Multi-layer security model with five distinct credential types:

### 1. API Key (Controller Access)

**Purpose:** Authenticate access to controller (both workers and CLI)

**Format:** 32-byte random string (base64-encoded)

**Storage:**
- Controller: Hashed with bcrypt (cost factor 10)
- Client: `~/.expo-free-agent/config.json` or env var

**Scope:** Global (all operations require API key)

**Rotation:** Manual (user regenerates via controller admin)

**Used in:**
- All worker endpoints (registration, poll, upload)
- All build endpoints (submit, status, download)
- All VM endpoints (auth, cert fetch)

---

### 2. Worker Token (Worker Sessions)

**Purpose:** Short-lived, rotating credential for worker authentication

**Format:** 32-character nanoid (cryptographically random)

**Lifetime:**
- TTL: 90 seconds
- Rotates: Every poll (30s interval)
- Safety margin: 60 seconds (2 missed polls)

**Storage:**
- Controller: `workers.access_token` + `access_token_expires_at`
- Worker: `WorkerConfiguration.accessToken` (persisted)

**Rotation Flow:**
```
Poll request:
  Headers: X-Worker-Token: <current-token>

Response:
  {
    job: {...},
    access_token: <new-token>  // Replaces current token
  }

Worker:
  configuration.accessToken = new-token
  Save to disk
```

**Security Benefits:**
- Stolen token valid for max 90 seconds
- Automatic cleanup (expired tokens can't be used)
- Forward secrecy (old tokens can't be reused)
- Audit trail (`last_seen_at` timestamp)

See [ADR-0010](./docs/adr/0010-worker-token-rotation.md) for threat analysis.

---

### 3. Build Token (CLI → Controller)

**Purpose:** Scoped credential for accessing specific build artifacts

**Format:** 32-byte random string

**Lifetime:** Persistent (until build deleted)

**Storage:**
- Controller: `builds.access_token` (hashed)
- CLI: Returned on submission, stored locally

**Scope:** Single build only (cannot access other builds)

**Used for:**
- Polling build status
- Downloading artifacts
- Viewing build logs

**Example:**
```
Submit build:
  POST /api/builds
  Response: {build_id, access_token}

Download artifact:
  GET /api/builds/{build_id}/artifacts/app.ipa
  Headers: X-Build-Token: <access_token>
```

See [ADR-0006](./docs/adr/0006-build-specific-access-tokens.md) for design.

---

### 4. OTP Token (VM Bootstrap)

**Purpose:** One-time password for VM to authenticate and receive VM token

**Format:** 32-character nanoid

**Lifetime:**
- TTL: 5 minutes
- Single-use (marked consumed after first use)

**Scope:** Specific build only

**Flow:**
```
Worker receives job:
  Response includes: otp_token

Worker writes to VM config:
  build-config/build-config.json:
    {
      "otpToken": "<5-min-token>",
      "buildId": "<id>"
    }

VM bootstrap:
  POST /api/vm/auth
  Headers:
    X-OTP-Token: <otp-token>
    X-Build-Id: <build-id>

  Controller validates:
    - Token exists and not expired
    - Token not already consumed
    - Token matches build ID

  Marks token consumed

  Response:
    {
      vm_token: <24-hour-vm-token>,
      build_id: <build-id>
    }
```

**Security:**
- Prevents worker from impersonating VM
- Prevents VM from accessing other builds
- Short TTL limits replay window
- Single-use prevents token reuse

---

### 5. VM Token (VM → Controller)

**Purpose:** Long-lived credential for VM to download source and upload artifacts

**Format:** 32-character nanoid

**Lifetime:** 24 hours (longer than any build)

**Scope:** Specific build only

**Used for:**
- Downloading source code (`/api/builds/{id}/source`)
- Fetching certificates (`/api/builds/{id}/certs-secure`)
- Uploading artifacts (`/api/builds/{id}/artifacts`)
- Streaming logs (`/api/builds/{id}/logs`)

**Validation:**
```elixir
def require_vm_token(conn) do
  vm_token = get_req_header(conn, "x-vm-token") |> List.first()
  build_id = get_build_id_from_path(conn)

  case Builds.get_build_by_vm_token(vm_token, build_id) do
    nil -> unauthorized(conn, "Invalid VM token")
    build -> assign(conn, :build, build)
  end
end
```

**Scoping:**
- Token only valid for specific build
- Cannot be used to access other builds
- Expires after 24 hours (cleanup job removes)

---

### Authentication Summary

| Credential Type | Lifetime | Rotates | Scope | Purpose |
|-----------------|----------|---------|-------|---------|
| **API Key** | Persistent | Manual | Global | Controller access |
| **Worker Token** | 90s | Every poll | Worker session | Poll/heartbeat |
| **Build Token** | Persistent | Never | Single build | CLI download |
| **OTP Token** | 5 min | Single-use | Single build | VM bootstrap |
| **VM Token** | 24 hours | Never | Single build | VM operations |

**Layered Security:**
- All requests require API key (first layer)
- Worker operations require worker token (second layer)
- Build operations require build/VM token (third layer)
- Tokens scoped to prevent lateral access

---

## Data Flow

### Source Code Journey

```
Developer machine:
  Project directory
  ↓ (tar + gzip)
  source.tar.gz (~10-50 MB)
  ↓ (HTTPS upload)

Controller:
  data/builds/{build-id}/source/source.tar.gz
  ↓ (HTTPS download, streaming)

Worker:
  /tmp/build-{build-id}.zip
  ↓ (VM mount)

VM:
  /mnt/build-config/source.zip
  ↓ (extract)
  /tmp/build-{build-id}/ (source files)
  ↓ (build process)

Artifact:
  /tmp/build-{build-id}/build/App.ipa
  ↓ (upload)

Controller:
  data/builds/{build-id}/artifacts/App.ipa
  ↓ (HTTPS download)

Developer machine:
  ./App.ipa
```

**No Intermediate Storage:**
- Worker doesn't persist source (temp files deleted)
- VM destroyed after build (no source remains)
- Controller can optionally purge old builds

**Streaming Transfers:**
- No buffering of entire file in memory
- Chunked transfer encoding
- 10MB memory footprint vs 500MB in buffered mode

---

### Certificate Journey (iOS Only)

```
Developer uploads:
  cert.p12 + provisioning profiles
  ↓ (HTTPS upload)

Controller (temporary storage):
  data/builds/{build-id}/certs/cert.p12
  data/builds/{build-id}/certs/profiles/*.mobileprovision
  ↓

Worker assigns job:
  Receives: otp_token
  ↓

VM bootstrap:
  Authenticates with OTP → receives VM token
  ↓
  GET /api/builds/{id}/certs-secure
  Headers: X-VM-Token
  ↓
  Response: {p12: "<base64>", p12Password, profiles: ["<base64>", ...]}
  ↓
  Decode base64 → write to temp files
  ↓
  security import cert.p12 -k build.keychain
  cp profiles/* ~/Library/MobileDevice/Provisioning\ Profiles/
  ↓

Build uses certs:
  xcodebuild -exportArchive (signs IPA)
  ↓

VM destroyed:
  $ tart delete vm-{id}
  → Keychain deleted
  → Provisioning profiles deleted
  → Certs gone forever

Controller (cleanup job):
  DELETE data/builds/{build-id}/certs/ (after 24 hours)
```

**Security Properties:**
- Worker never sees certificates (fetched inside VM)
- Certificates stored in ephemeral keychain
- VM destroyed → keychain destroyed → certs unrecoverable
- Controller deletes certs after build completion
- No long-term storage of signing credentials

---

## Technology Stack

### Runtime & Languages

| Component | Technology | Why |
|-----------|-----------|-----|
| **Controller Runtime** | Elixir 1.15 + Erlang/OTP | Concurrency, fault tolerance, battle-tested patterns |
| **Controller Framework** | Phoenix 1.8 | REST API, Ecto ORM, connection pooling |
| **Controller HTTP Server** | Bandit | HTTP/2, efficient streaming |
| **Worker Runtime** | Swift 5.9 (macOS) | Native macOS APIs, Apple Virtualization Framework |
| **CLI Runtime** | Bun (TypeScript) | Fast startup, native TypeScript support |

---

### Data Storage

| Layer | Technology | Why |
|-------|-----------|-----|
| **Database** | PostgreSQL 15 | `SELECT FOR UPDATE SKIP LOCKED`, JSON support, full-text search |
| **File Storage** | Local filesystem | Simple, no cloud dependencies |
| **Queue** | PostgreSQL (via Ecto) | No separate queue service, atomic operations |
| **Cache** | None (stateless) | Simplicity, PostgreSQL fast enough |

---

### Virtualization

| Component | Technology | Why |
|-----------|-----------|-----|
| **VM Management** | Tart | CLI wrapper around Apple Virtualization Framework |
| **VM Base Images** | OCI images (ghcr.io) | Versioned, reproducible, shareable |
| **VM Isolation** | Apple Virtualization Framework | Hardware-level isolation, hypervisor security boundary |

**Why Tart over raw Virtualization.framework?**
- Simpler VM lifecycle management (clone, start, stop, delete)
- OCI image support (pull base images from GitHub Container Registry)
- CLI tool (scriptable, no Swift code needed)
- Pre-built images available (macOS + Xcode)

See [ADR-0002](./docs/adr/0002-tart-vm-management.md) for alternatives.

---

### Communication Protocols

| Protocol | Use Case | Why |
|----------|----------|-----|
| **HTTPS** | All network traffic | Encryption, authentication, industry standard |
| **HTTP/2** | Controller API | Multiplexing, header compression, streaming |
| **Polling** | Worker ↔ Controller | Works behind NAT, stateless server, simple |
| **Chunked Transfer** | File uploads/downloads | No memory buffering, handles large files |

**No WebSockets/SSE:**
- Polling sufficient for 15-30 minute builds
- Avoids connection management complexity
- Works universally (NAT, proxies, firewalls)

See [ADR-0007](./docs/adr/0007-polling-based-worker-protocol.md) for rationale.

---

### Build Tools

| Tool | Purpose | Invoked By |
|------|---------|-----------|
| **Xcode** | iOS compilation + signing | VM (xcodebuild) |
| **Gradle** | Android compilation | VM (./gradlew) |
| **CocoaPods** | iOS dependencies | VM (pod install) |
| **npm/Bun** | JavaScript dependencies | VM (npm install or bun install) |
| **EAS CLI** | Expo build orchestration | VM (eas build --local) |

---

### Monitoring & Observability

| Tool | Purpose | Status |
|------|---------|--------|
| **Phoenix LiveDashboard** | Real-time metrics | ✅ Implemented |
| **Ecto query logging** | SQL debugging | ✅ Implemented |
| **Build logs** | Stored per build | ✅ Implemented |
| **Telemetry** | VM resource usage | ⏳ Planned |
| **OpenTelemetry** | Distributed tracing | ⏳ Planned |
| **Prometheus** | Metrics export | ⏳ Planned |
| **Grafana** | Dashboards | ⏳ Planned |

---

## Critical Design Decisions

### 1. Elixir/OTP for Controller

**Decision:** Migrate from TypeScript/Bun to Elixir/Phoenix/PostgreSQL

**Problem:**
- SQLite single-writer bottleneck
- Race conditions in build assignment
- Queue lost on crash
- 500MB memory per build

**Solution:**
- PostgreSQL `SELECT FOR UPDATE SKIP LOCKED` (atomic assignment)
- OTP supervision trees (automatic crash recovery)
- GenServer queue manager (serialized access)
- Streaming file transfers (10MB memory footprint)

**Results:**
- 10x throughput (100+ builds/sec vs 10/sec)
- 4x faster assignment (50ms vs 200ms)
- 50x memory efficiency
- Zero race conditions

See [ADR-0009](./docs/adr/0009-migrate-controller-to-elixir.md) for full analysis.

---

### 2. Polling Instead of Push

**Decision:** Workers poll controller every 30 seconds instead of WebSocket/SSE

**Problem:**
- Workers behind NAT/firewalls (home networks)
- Need stateless server (no connection management)
- Simplicity over performance

**Solution:**
- HTTP GET every 30 seconds
- Controller returns job or null
- Exponential backoff on errors

**Trade-offs:**
- ✅ Works universally (NAT, proxies)
- ✅ Stateless server (no connection tracking)
- ✅ Simple error recovery
- ❌ 30-second latency (acceptable for 15-30 min builds)
- ❌ Wasted requests when queue empty

**Alternatives Considered:**
- WebSocket (complexity, NAT issues)
- SSE (connection management)
- Long polling (timeout handling)
- Message queue (external dependency)

See [ADR-0007](./docs/adr/0007-polling-based-worker-protocol.md) for detailed comparison.

---

### 3. Worker Token Rotation

**Decision:** Rotate worker access tokens every poll (90s TTL)

**Problem:**
- Static credentials valid forever
- Compromised token grants permanent access
- No automatic cleanup of dead workers

**Solution:**
- Generate new token on every poll
- 90-second TTL (expires if not rotated)
- Safety margin: 60 seconds (2 missed polls)

**Security Benefits:**
- Stolen token valid max 90 seconds
- Automatic cleanup (expired tokens unusable)
- Forward secrecy (old tokens can't be reused)
- Audit trail (last_seen_at timestamp)

**Operational Benefits:**
- Self-healing (worker auto-re-registers on expiration)
- Zero configuration (rotation automatic)
- Stale detection (workers not polling = offline)

See [ADR-0010](./docs/adr/0010-worker-token-rotation.md) for threat model.

---

### 4. Tart for VM Management

**Decision:** Use Tart CLI instead of raw Virtualization.framework

**Problem:**
- Virtualization.framework requires Swift code
- VM lifecycle management complex
- Need reproducible base images

**Solution:**
- Tart: CLI wrapper around Virtualization.framework
- OCI image support (pull from ghcr.io)
- Simple commands: clone, run, delete

**Benefits:**
- ✅ No Swift code for VM management
- ✅ Pre-built images (macOS + Xcode)
- ✅ Versioned, reproducible
- ✅ Simple CLI (scriptable)

**Trade-offs:**
- ❌ External dependency (Tart must be installed)
- ❌ Less control than raw API
- ✅ Faster development (don't reinvent VM management)

See [ADR-0002](./docs/adr/0002-tart-vm-management.md) for alternatives.

---

### 5. Ephemeral VMs vs Persistent

**Decision:** Destroy VM after every build

**Problem:**
- Persistent VMs accumulate state
- Risk of certificate leakage
- Cleanup complexity

**Solution:**
- Clone template → build → destroy
- Certificates installed in ephemeral keychain
- VM disk deleted after build

**Security Benefits:**
- ✅ Certs never persist across builds
- ✅ No state leakage between builds
- ✅ Simpler error recovery (just delete VM)

**Performance Trade-offs:**
- ❌ 30-60s boot time per build
- ❌ More disk I/O
- ✅ Guaranteed clean state
- ✅ No debugging leftover state

**Future Optimization:**
- Warm VM pool (keep N VMs booted)
- Reusable VMs (opt-in for trusted users)

---

### 6. Build-Specific Access Tokens

**Decision:** Each build gets unique access token for artifact downloads

**Problem:**
- Single API key grants access to all builds
- Users can access each other's artifacts
- No audit trail for downloads

**Solution:**
- Generate unique token per build
- Token scoped to single build only
- Required for status/download

**Benefits:**
- ✅ Users can only access their builds
- ✅ Audit trail (who downloaded what)
- ✅ Revocable (delete token = no access)

**Implementation:**
```elixir
def download_artifact(conn, %{"id" => build_id}) do
  build_token = get_req_header(conn, "x-build-token")

  case Builds.get_build_by_token(build_id, build_token) do
    nil -> unauthorized(conn)
    build -> stream_artifact(conn, build.artifact_path)
  end
end
```

See [ADR-0006](./docs/adr/0006-build-specific-access-tokens.md) for design.

---

### 7. PostgreSQL SELECT FOR UPDATE SKIP LOCKED

**Decision:** Use row-level locking for atomic build assignment

**Problem:**
- Multiple workers polling simultaneously
- Race condition: both SELECT same build, both UPDATE it
- Need atomic "claim and assign" operation

**Solution:**
```sql
BEGIN TRANSACTION;
  SELECT * FROM builds
  WHERE status = 'pending'
  ORDER BY submitted_at ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED;  -- Lock row, skip if already locked

  UPDATE builds SET status = 'assigned', worker_id = ?;
COMMIT;
```

**How it works:**
- Worker A locks build #123 → Workers B & C skip it
- Worker B locks build #124 → Workers A & C skip it
- Exactly one worker per build, guaranteed by PostgreSQL

**Alternatives Considered:**
- Distributed locks (Redis): External dependency
- Optimistic locking: Retry loops, wasted work
- Serializable isolation: Too restrictive, poor performance

**Why this is better:**
- ✅ Native PostgreSQL feature
- ✅ Zero application-level logic
- ✅ No retry loops or race windows
- ✅ Scales to 100+ workers

See [ADR-0009](./docs/adr/0009-migrate-controller-to-elixir.md) for migration rationale.

---

## Performance Characteristics

### Throughput

| Metric | TypeScript Version | Elixir Version | Improvement |
|--------|-------------------|----------------|-------------|
| **Max builds/sec** | ~10 | 100+ | **10x** |
| **Poll latency** | 150-250ms | 40-60ms | **4x faster** |
| **Memory per build** | 500MB | 10MB | **50x** |
| **Concurrent workers** | ~20 (locks) | 100+ | **5x** |
| **Queue recovery** | Manual | <1 second | **Automatic** |

---

### Build Timeline

Typical iOS build (20-30 minutes):

| Phase | Time | Description |
|-------|------|-------------|
| **Submission** | <5s | CLI uploads source to controller |
| **Queue wait** | 0-30s | Waiting for worker poll |
| **Assignment** | <100ms | Atomic database transaction |
| **VM clone** | 10-20s | Clone template VM |
| **VM boot** | 30-60s | Start macOS VM |
| **SSH wait** | 10-30s | Wait for SSH server |
| **Source download** | 10-30s | Download from controller |
| **Cert fetch** | 5-10s | VM fetches certs (iOS only) |
| **npm install** | 1-3 min | Download JavaScript deps |
| **pod install** | 2-4 min | Download iOS deps |
| **Xcode build** | 10-15 min | Compile + sign |
| **Artifact upload** | 10-30s | Upload IPA to controller |
| **VM destroy** | 5-10s | Delete VM disk |
| **TOTAL** | **15-25 min** | **Complete build** |

**Bottlenecks:**
1. Xcode compilation (10-15 min) - unavoidable
2. Dependency downloads (3-7 min) - cacheable in base image
3. VM boot (30-60 min) - solvable with warm VM pool

---

### Resource Usage

**Per Worker:**
- CPU: 4 cores (50% of M1 MacBook Air)
- Memory: 8GB (VM) + 2GB (worker app) = 10GB total
- Disk: 80GB (VM) + temp files (~1GB)
- Network: ~600MB download/upload per build

**Scalability:**

| Hardware | Concurrent Builds | Builds/Hour | Builds/Day |
|----------|------------------|-------------|------------|
| M1 MacBook Air (16GB) | 1 | 3 | 72 |
| M2 Mac Mini (32GB) | 2 | 6 | 144 |
| M2 Ultra Mac Studio (64GB) | 4 | 12 | 288 |

---

### Database Load

**Per worker poll (every 30s):**
- 1 SELECT (token lookup) - indexed
- 1 UPDATE (heartbeat + token rotation)
- 1 SELECT FOR UPDATE (build assignment, if pending)
- 1 UPDATE (build status, if assigned)
- 1 UPDATE (worker status, if assigned)

**Example:** 10 workers polling every 30s = ~3 queries/second (negligible)

**Connection Pool:**
- Default: 100 connections
- Supports 100+ concurrent workers
- Auto-scales with PostgreSQL config

---

### Network Bandwidth

**Per build:**
- Upload: ~50MB (source tarball)
- Download (worker): ~50MB (source) + ~10MB (certs)
- Upload (worker): ~100MB (IPA/APK)
- Download (user): ~100MB (IPA/APK)

**Total per build:** ~300MB network traffic

---

### Failure Recovery Time

| Scenario | Detection Time | Recovery Time | Total Downtime |
|----------|---------------|---------------|----------------|
| **Token expiration** | Immediate (on poll) | ~1s (re-register) | <2s |
| **Worker crash** | 5 min (heartbeat) | <30s (next poll) | ~5.5 min |
| **Network failure** | Immediate | <30s (exponential backoff) | <30s |
| **Controller restart** | N/A | <5s (OTP supervision) | <5s |
| **Database crash** | Immediate | Depends on Postgres recovery | Variable |

---

## Security Model

### Defense in Depth

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: Network Security                                  │
│ - HTTPS required (TLS 1.3)                                  │
│ - Certificate validation                                    │
│ - No plaintext protocols                                    │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 2: API Key Authentication                             │
│ - All requests require API key                              │
│ - Bcrypt hashed (cost factor 10)                            │
│ - Timing-safe comparison (constant-time)                    │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 3: Token-Based Authorization                          │
│ - Worker token (90s TTL, rotates)                           │
│ - Build token (scoped to build)                             │
│ - OTP token (5 min, single-use)                             │
│ - VM token (24h, scoped to build)                           │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 4: VM Isolation                                       │
│ - Hardware-level isolation (Apple Virtualization)           │
│ - Ephemeral environment (destroyed after build)             │
│ - No host filesystem access                                 │
│ - Network isolation (NAT only)                              │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 5: Credential Isolation                               │
│ - Certs fetched inside VM only                              │
│ - Ephemeral keychain (destroyed with VM)                    │
│ - No persistence across builds                              │
│ - Zero knowledge (controller never sees plaintext certs)    │
└─────────────────────────────────────────────────────────────┘
```

### Threat Model

| Threat | Mitigation | Residual Risk |
|--------|-----------|---------------|
| **Malicious build code** | VM isolation, no host access | VM escape (Apple's responsibility) |
| **Source code exposure** | HTTPS encryption, temporary storage | Controller compromise |
| **Credential theft** | Token rotation, ephemeral VMs | Short-term exposure (90s) |
| **Artifact tampering** | HTTPS, checksums, code signing | MITM (requires cert compromise) |
| **Authentication bypass** | Multi-layer auth, timing-safe comparison | Brute force (infeasible with 256-bit tokens) |
| **Path traversal** | Input validation, `safe_join` | Implementation bugs |
| **Resource exhaustion** | Build timeouts, VM limits, rate limiting | Intentional abuse |
| **Worker compromise** | Ephemeral VMs, no secrets stored | Lateral movement to controller |
| **Database compromise** | Token expiration, scoped credentials | Long-term access to expired data |

See [Security Architecture](./docs/architecture/security.md) for full threat analysis.

---

### Path Traversal Protection

**Vulnerable Pattern:**
```elixir
# ❌ WRONG - Path traversal attack
def read_file(user_input) do
  File.read!("/data/builds/#{user_input}")
end

# Attack: user_input = "../../../etc/passwd"
# Result: File.read!("/data/builds/../../../etc/passwd")
```

**Safe Pattern:**
```elixir
# ✅ CORRECT - Validated path
def read_file(build_id) do
  base_path = "/data/builds"
  file_path = Path.join([base_path, build_id, "source.zip"])

  # Ensure resolved path is inside base_path
  case Path.safe_join(base_path, file_path) do
    {:ok, safe_path} -> File.read!(safe_path)
    {:error, :unsafe} -> raise "Path traversal detected"
  end
end
```

**Implementation:** `FileStorage.safe_join/2` validates all file operations.

---

### Code Signing (Worker App)

**FreeAgent.app Security:**
- Signed with Developer ID Application certificate
- Hardened runtime enabled (`--options runtime`)
- Entitlements declared (`com.apple.vm.hypervisor`)
- Notarized by Apple (malware scan passed)
- Stapled ticket (works offline)

**Verification:**
```bash
# Signature
$ codesign --verify --deep --strict FreeAgent.app
$ echo $?
0  # Success

# Gatekeeper
$ spctl --assess --type execute --verbose FreeAgent.app
FreeAgent.app: accepted source=Notarized Developer ID

# Notarization
$ xcrun stapler validate FreeAgent.app
The validate action worked!
```

See [Gatekeeper Documentation](./docs/operations/gatekeeper.md) for setup.

---

## Fault Tolerance

### Automatic Recovery Mechanisms

#### 1. Worker Crashes

**Graceful Shutdown:**
```swift
func stop() async {
    isActive = false
    pollingTask?.cancel()

    // Wait for builds to complete
    for (jobID, task) in activeBuilds {
        task.cancel()
        await task.value
    }

    // Unregister (reassigns builds)
    await unregisterWorker()
}
```

**Ungraceful Shutdown (crash, kill -9):**
- Heartbeat monitor detects staleness (5 min)
- Builds automatically reassigned to pending
- Next worker poll picks up orphaned build

---

#### 2. Controller Crashes

**OTP Supervision:**
```
Supervisor restarts crashed process
  ↓
QueueManager.start_link()
  ↓
Rebuild queue from database:
  SELECT * FROM builds WHERE status IN ('pending', 'assigned')
  ↓
Resume operations (<5 seconds)
```

**Zero Data Loss:**
- All state in PostgreSQL (persistent)
- No in-memory queue to lose
- Automatic recovery on startup

---

#### 3. Database Connection Loss

**Ecto Connection Pool:**
- Automatic reconnection (exponential backoff)
- Failed queries return error (not crash)
- Circuit breaker (stops retrying after threshold)

**Application Behavior:**
- Worker polls fail → exponential backoff
- CLI operations fail → user-friendly error
- Build in progress → completes or times out

---

#### 4. Network Failures

**Worker Behavior:**
```swift
do {
    let job = try await pollForJob()
} catch {
    // Network error, exponential backoff
    try? await Task.sleep(for: .seconds(5))
}
```

**Exponential Backoff:**
- Initial: 5 seconds
- Max: 120 seconds
- Automatic recovery when network restored

---

#### 5. VM Crashes

**Detection:**
```swift
class VMManager: VZVirtualMachineDelegate {
    func virtualMachine(_ vm: VZVirtualMachine, didStopWithError error: Error) {
        print("VM crashed: \(error)")

        // Report failure to controller
        reportJobFailure(buildId, error: error)

        // Cleanup
        cleanup()
    }
}
```

**Recovery:**
- Build marked as failed
- VM disk deleted
- Worker status reset to idle
- Build can be retried by user

---

#### 6. Build Timeouts

**Default:** 30 minutes (configurable)

**Enforcement:**
```swift
try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask {
        try await vmManager.executeBuild(...)
    }

    group.addTask {
        try await Task.sleep(for: .seconds(timeout))
        throw BuildError.timeout
    }

    try await group.next()  // First to complete/throw
    group.cancelAll()
}
```

**Timeout Behavior:**
- Kill VM process
- Mark build as failed
- Clean up resources
- Worker returns to idle

---

### Fault Tolerance Summary

| Failure Mode | Detection | Recovery | Data Loss |
|-------------|-----------|----------|-----------|
| Worker crash (graceful) | Immediate | <1s | None |
| Worker crash (ungraceful) | 5 min | <30s | None |
| Controller crash | Immediate | <5s | None (PostgreSQL) |
| Database crash | Immediate | Postgres recovery | Depends on Postgres |
| Network failure | Immediate | <30s | None |
| VM crash | Immediate | <1s | Build fails, retryable |
| Build timeout | Exact (30 min) | Immediate | Build fails, retryable |
| Token expiration | Immediate (on poll) | <2s | None |

**Zero Data Loss Guarantee:**
- All state in PostgreSQL (ACID compliant)
- No in-memory state (except OTP processes, which auto-recover)
- Ephemeral VMs (no state to lose)

---

## Deployment Architecture

### Development (Local Machine)

```
┌─────────────────────────────────────────────────────────┐
│ Mac (localhost)                                         │
│                                                         │
│  ┌───────────────────────────────────────────────┐     │
│  │ Controller (Elixir)                           │     │
│  │ $ mix phx.server                              │     │
│  │ Listening: http://localhost:4000              │     │
│  └───────────────────────────────────────────────┘     │
│                                                         │
│  ┌───────────────────────────────────────────────┐     │
│  │ PostgreSQL (Docker or local)                  │     │
│  │ $ docker run -p 5432:5432 postgres:15         │     │
│  └───────────────────────────────────────────────┘     │
│                                                         │
│  ┌───────────────────────────────────────────────┐     │
│  │ Worker (Swift)                                │     │
│  │ $ swift run FreeAgent                         │     │
│  │ Config: http://localhost:4000                 │     │
│  └───────────────────────────────────────────────┘     │
│                                                         │
│  ┌───────────────────────────────────────────────┐     │
│  │ CLI (Bun)                                     │     │
│  │ $ bun cli submit                              │     │
│  │ Config: http://localhost:4000                 │     │
│  └───────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────┘
```

---

### Production (Distributed)

```
┌──────────────────────────────────────────────────────────────┐
│ VPS (controller.example.com)                                │
│                                                              │
│  ┌────────────────────────────────────────────────────┐     │
│  │ Nginx (Reverse Proxy)                              │     │
│  │ - TLS termination                                  │     │
│  │ - Rate limiting                                    │     │
│  │ - Gzip compression                                 │     │
│  │ Listening: https://controller.example.com          │     │
│  └────────────────────────────────────────────────────┘     │
│         │                                                    │
│         ↓                                                    │
│  ┌────────────────────────────────────────────────────┐     │
│  │ Controller (Elixir Release)                        │     │
│  │ $ _build/prod/rel/expo_controller/bin/start        │     │
│  │ Listening: http://localhost:4000                   │     │
│  └────────────────────────────────────────────────────┘     │
│         │                                                    │
│         ↓                                                    │
│  ┌────────────────────────────────────────────────────┐     │
│  │ PostgreSQL                                         │     │
│  │ - Managed service (AWS RDS, DigitalOcean)          │     │
│  │ - Or self-hosted with backups                      │     │
│  └────────────────────────────────────────────────────┘     │
│                                                              │
│  ┌────────────────────────────────────────────────────┐     │
│  │ File Storage                                       │     │
│  │ - /var/lib/expo-controller/storage/                │     │
│  │ - Or S3-compatible (future)                        │     │
│  └────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────┘
                           ↑
                           │ HTTPS polling (30s interval)
                           │
┌──────────────────────────┴───────────────────────────────────┐
│ Worker Mac #1 (home network)                                │
│                                                              │
│  ┌────────────────────────────────────────────────────┐     │
│  │ FreeAgent.app (Menu Bar)                           │     │
│  │ Config: https://controller.example.com             │     │
│  │ API Key: ********                                  │     │
│  └────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ Worker Mac #2 (office network)                              │
│                                                              │
│  ┌────────────────────────────────────────────────────┐     │
│  │ FreeAgent.app (Menu Bar)                           │     │
│  │ Config: https://controller.example.com             │     │
│  │ API Key: ********                                  │     │
│  └────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ Developer Laptop (anywhere)                                  │
│                                                              │
│  ┌────────────────────────────────────────────────────┐     │
│  │ CLI (Bun)                                          │     │
│  │ $ expo-build submit --platform ios                 │     │
│  │ Config: https://controller.example.com             │     │
│  │ API Key: ********                                  │     │
│  └────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────┘
```

---

### Deployment Checklist

**Controller:**
- [ ] PostgreSQL configured with connection pooling
- [ ] File storage directory with sufficient space
- [ ] HTTPS enabled (via reverse proxy)
- [ ] API key generated (strong, random)
- [ ] Firewall rules (only expose HTTPS)
- [ ] Backup strategy (database + file storage)
- [ ] Monitoring (health endpoint, logs)

**Worker:**
- [ ] macOS 14+ on Apple Silicon
- [ ] Tart installed (`brew install tart`)
- [ ] Template VM prepared (macOS + Xcode)
- [ ] FreeAgent.app installed
- [ ] Configured with controller URL + API key
- [ ] Resource limits set (CPU, memory, disk)
- [ ] Automatic startup (Launch Agent)

**CLI:**
- [ ] Installed globally (`npm install -g @sethwebster/expo-build`)
- [ ] Configured with controller URL + API key
- [ ] Tested with sample project

See [Setup Remote](./docs/getting-started/setup-remote.md) for detailed instructions.

---

## Related Documentation

### Getting Started
- [5-Minute Start](./docs/getting-started/5-minute-start.md) - Quick local setup
- [Setup Local](./docs/getting-started/setup-local.md) - Development environment
- [Setup Remote](./docs/getting-started/setup-remote.md) - Production deployment

### Architecture Deep Dives
- [Diagrams](./docs/architecture/diagrams.md) - Visual flow diagrams
- [Security Model](./docs/architecture/security.md) - Threat analysis and mitigations
- [Build Pickup Flow](./docs/architecture/build-pickup-flow.md) - Complete transaction flow
- [VM Implementation](./docs/architecture/vm-implementation.md) - VM lifecycle details

### Architecture Decision Records
- [ADR-0001: SQLite + Filesystem](./docs/adr/0001-sqlite-filesystem-storage.md) - Storage design
- [ADR-0002: Tart VM Management](./docs/adr/0002-tart-vm-management.md) - VM technology choice
- [ADR-0006: Build-Specific Tokens](./docs/adr/0006-build-specific-access-tokens.md) - Token scoping
- [ADR-0007: Polling Protocol](./docs/adr/0007-polling-based-worker-protocol.md) - Communication pattern
- [ADR-0009: Elixir Migration](./docs/adr/0009-migrate-controller-to-elixir.md) - Controller rewrite
- [ADR-0010: Token Rotation](./docs/adr/0010-worker-token-rotation.md) - Credential lifecycle

### Operations
- [Gatekeeper](./docs/operations/gatekeeper.md) - Code signing and notarization
- [Troubleshooting](./docs/operations/troubleshooting.md) - Common issues
- [VM Setup](./docs/operations/vm-setup.md) - Template VM creation
- [Release Process](./docs/operations/release.md) - Deployment procedures

### Testing
- [Testing Documentation](./docs/testing/testing.md) - Test strategies
- [Smoketest](./docs/testing/smoketest.md) - Quick verification
- [E2E Tests](./docs/testing/e2e-elixir-compatibility.md) - End-to-end validation

---

## Questions or Issues?

- [Documentation Index](./docs/INDEX.md) - Browse all docs
- [GitHub Issues](https://github.com/expo/expo-free-agent/issues) - Report bugs
- [GitHub Discussions](https://github.com/expo/expo-free-agent/discussions) - Ask questions

---

**Expo Free Agent** - Build Expo apps on your own hardware.

Made with precision and care by engineers who value control over their infrastructure.
