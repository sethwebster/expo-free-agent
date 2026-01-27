# Expo Free Agent Controller: TypeScript to Elixir Migration Plan

**Date:** 2026-01-26
**Reviewer:** Code Review
**Scope:** Full architectural review + Elixir migration strategy

---

## Part 1: Current Architecture Review

### System Overview

The controller is a build orchestration system with:
- **Fastify REST API** handling build submission, worker coordination, artifact management
- **SQLite (Bun)** for persistence (workers, builds, logs, diagnostics)
- **In-memory JobQueue** with DB-backed recovery
- **Local filesystem storage** for source, certs, results
- **EJS-rendered dashboard** (no SSE/WebSocket - static page refresh only)

### Critical Files Reviewed

| File | LOC | Purpose |
|------|-----|---------|
| `server.ts` | 246 | Main server, queue restoration, stuck build checker |
| `api/builds/index.ts` | 519 | Build CRUD, file downloads, telemetry, heartbeat |
| `api/workers/index.ts` | 317 | Worker registration, polling, result upload |
| `db/Database.ts` | 311 | SQLite wrapper with transactions |
| `services/JobQueue.ts` | 173 | In-memory FIFO queue with events |
| `services/FileStorage.ts` | 232 | Filesystem operations with path traversal protection |
| `middleware/auth.ts` | 100 | API key + worker access validation |

---

## Part 2: Critical Issues (RED)

### 1. Race Condition in Worker Polling

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/packages/controller/src/api/workers/index.ts:115-129`

```typescript
// Assign next pending build
const build = queue.assignToWorker(worker);  // In-memory first

if (!build) {
  return reply.send({ job: null });
}

// ATOMIC: Assign build to worker in database with transaction
const assigned = db.assignBuildToWorker(build.id, worker_id, timestamp);

if (!assigned) {
  // Build was already assigned by another worker, try again
  return reply.send({ job: null });  // BUG: Queue state is now inconsistent
}
```

**Problem:** The queue is modified in-memory BEFORE the DB transaction. If `assignBuildToWorker` fails (concurrent claim), the build is removed from the in-memory queue but still marked pending in DB. Next poll won't find it.

**Impact:** Lost builds under concurrent worker load.

**Elixir Fix:** Use Ecto transactions with `SELECT FOR UPDATE` or optimistic locking. GenServer serializes queue operations naturally.

---

### 2. Heartbeat Timeout Window Too Short

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/packages/controller/src/server.ts:156-200`

```typescript
const HEARTBEAT_TIMEOUT = 120000; // 2 minutes
// Only check builds that have been running for at least 30 seconds
if (timeSinceStart > 30000) {
  const timeSinceHeartbeat = lastHeartbeat ? now - lastHeartbeat : timeSinceStart;
  if (timeSinceHeartbeat > HEARTBEAT_TIMEOUT) {
    // Mark as failed
```

**Problem:** iOS builds can legitimately hang for 3-5 minutes during code signing, CocoaPods install, or Xcode archive. 2-minute timeout will cause false positives.

**Impact:** Builds cancelled incorrectly during heavy operations.

**Elixir Fix:** Configurable timeout per build stage. Use GenServer timers with dynamic adjustment based on telemetry data.

---

### 3. No Connection Pooling / Single Database Handle

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/packages/controller/src/db/Database.ts:55-58`

```typescript
constructor(dbPath: string) {
  this.db = new BunDatabase(dbPath);  // Single connection
  this.initSchema();
}
```

**Problem:** Single SQLite connection will serialize all database operations. Under load with 100+ concurrent builds, this becomes a bottleneck.

**Impact:** Linear scaling limit, potential timeouts under load.

**Elixir Fix:** Ecto with PostgreSQL connection pool (default 10 connections, configurable). Write-ahead logging for concurrent reads.

---

### 4. Memory Exhaustion Risk in File Upload

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/packages/controller/src/api/builds/index.ts:49-76`

```typescript
for await (const part of parts) {
  if (part.type === 'file') {
    if (part.fieldname === 'source') {
      const chunks: Buffer[] = [];
      for await (const chunk of part.file) {
        chunks.push(chunk);  // Accumulates entire file in memory
      }
      sourceBuffer = Buffer.concat(chunks);  // Then concatenates again
```

**Problem:** 500MB source files are fully loaded into memory twice (chunks array + concatenated buffer). With concurrent uploads, memory usage explodes.

**Impact:** OOM crashes under load.

**Elixir Fix:** Stream directly to disk using `Plug.Upload` temp files. Phoenix already handles this correctly by default.

---

### 5. API Key Comparison Vulnerable to Timing Attack

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/packages/controller/src/middleware/auth.ts:26`

```typescript
if (providedKey !== config.apiKey) {
  return reply.status(403).send({
    error: 'Invalid API key',
  });
}
```

**Problem:** String comparison short-circuits on first mismatch, revealing key length and prefix through timing analysis.

**Impact:** API key can be brute-forced with timing analysis.

**Elixir Fix:** Use `Plug.Crypto.secure_compare/2` which runs in constant time.

---

## Part 3: Architecture Concerns (YELLOW)

### 1. In-Memory Queue is Single Point of Failure

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/packages/controller/src/services/JobQueue.ts`

The queue lives entirely in memory with DB backup on restart. If server crashes mid-operation:
- Pending builds survive (in DB)
- Active assignments may be inconsistent

**Elixir Design:** Replace with Oban (PostgreSQL-backed job queue):
- Durable by default
- Built-in retry logic
- Scheduled jobs
- Horizontal scaling via PubSub

### 2. No Rate Limiting

**Location:** All API routes

Workers can poll infinitely, telemetry can flood the server. No protection against DoS.

**Elixir Design:** Use `PlugAttack` or `Hammer` for rate limiting with configurable per-endpoint limits.

### 3. Tight Coupling Between Routes and Business Logic

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/packages/controller/src/api/builds/index.ts`

Route handlers contain business logic (queue management, file storage, DB updates). Makes testing difficult and creates 500-line files.

**Elixir Design:** Phoenix contexts:
```
lib/controller/
  builds/          # Business logic
    build.ex       # Ecto schema
    builds.ex      # Context module (public API)
  workers/
    worker.ex
    workers.ex
  orchestration/   # GenServers
    queue_manager.ex
    heartbeat_monitor.ex
```

### 4. No Observability

No metrics, no tracing, no structured logging. `console.log` everywhere.

**Elixir Design:**
- Telemetry events for all operations
- Logger with structured metadata
- LiveDashboard for metrics

---

## Part 4: DRY Opportunities (GREEN)

### 1. Repeated Stream-to-Buffer Pattern

**Locations:**
- `api/builds/index.ts:52-56` (source upload)
- `api/builds/index.ts:62-66` (certs upload)
- `api/workers/index.ts:172-178` (result upload)

```typescript
const chunks: Buffer[] = [];
for await (const chunk of part.file) {
  chunks.push(chunk);
}
someBuffer = Buffer.concat(chunks);
```

**Consolidation:** Extract to `bufferFromStream(stream: AsyncIterable<Buffer>): Promise<Buffer>`

### 2. Worker Validation Logic

**Locations:**
- `middleware/auth.ts:44-99` (requireWorkerAccess)
- `api/workers/index.ts:86-97` (poll validation)
- `api/builds/index.ts:375-378` (heartbeat validation)

Worker existence checks, ownership validation duplicated across multiple places.

**Elixir Design:** Single `Workers.authorized?(worker_id, build_id)` function in context module.

### 3. Build Status Update Pattern

**Locations:**
- `api/builds/index.ts:467-481` (cancel)
- `api/workers/index.ts:220-227` (success)
- `api/workers/index.ts:242-253` (failure)
- `server.ts:177-188` (timeout)

Each does: update build -> update worker -> update queue -> add log

**Elixir Design:** Single `Builds.transition(build_id, :completed | :failed, opts)` with Ecto.Multi for atomicity.

---

## Part 5: Maintenance Improvements (BLUE)

### 1. Type Safety Gaps

**Location:** Multiple files

```typescript
const build = (request as any).build;  // Loss of type safety
const lastHeartbeat = (build as any).last_heartbeat_at;  // Schema drift
```

**Elixir Fix:** Ecto schemas enforce types. Pattern matching catches shape mismatches at compile time.

### 2. Magic Numbers

**Locations:**
- `server.ts:156` - `HEARTBEAT_TIMEOUT = 120000`
- `server.ts:170` - `timeSinceStart > 30000`
- `server.ts:220` - `60000` (interval)
- `Config.ts:40-43` - Size limits

**Elixir Fix:** Application config with runtime validation:
```elixir
config :controller,
  heartbeat_timeout_ms: 120_000,
  stuck_check_interval_ms: 60_000,
  max_source_size_bytes: 500 * 1024 * 1024
```

### 3. Missing Error Boundaries

**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/packages/controller/src/api/builds/index.ts:244-253`

```typescript
try {
  const stream = storage.createReadStream(build.result_path);
  return reply
    .header('Content-Disposition', `attachment; filename="${filename}"`)
    .send(stream);
} catch (err) {
  fastify.log.error('File read error:', err);
  return reply.status(500).send({ error: 'Failed to read build result' });
}
```

**Problem:** Stream errors after headers sent will crash response. No cleanup of partial responses.

**Elixir Fix:** Phoenix handles this via `Plug.Conn.send_file/5` with proper error handling.

---

## Part 6: Nitpicks (WHITE)

1. **Inconsistent timestamp handling** - Some places use `Date.now()`, others use inline. Centralize.
2. **require('stream') inline** - Should be top-level import.
3. **JSON.parse without try/catch** for `worker.capabilities` in EJS template.
4. **No request ID tracking** - Makes log correlation difficult.
5. **Hardcoded localhost in startup message** - Should use actual bound address.

---

## Part 7: Strengths (CHECKMARK)

1. **Atomic build assignment transaction** (`assignBuildToWorker`) - Good use of SQLite transactions
2. **Path traversal protection** in FileStorage - Validates paths stay within storage root
3. **Zip bomb protection** - 50MB uncompressed limit, entry name validation
4. **Queue state recovery** - Restores pending/assigned builds on restart
5. **Comprehensive E2E tests** - 788 lines covering full build lifecycle
6. **Clear API documentation** in route index comments

---

## Part 8: Elixir Architecture Design

### Supervisor Tree

```
ExpoController.Application
├── ExpoController.Repo (Ecto)
├── ExpoController.PubSub (Phoenix.PubSub)
├── ExpoController.Telemetry (Telemetry supervisor)
├── ExpoController.Endpoint (Phoenix)
├── ExpoController.QueueSupervisor (DynamicSupervisor)
│   └── ExpoController.BuildRunner (per-build GenServer)
├── ExpoController.WorkerRegistry (Registry)
├── ExpoController.HeartbeatMonitor (GenServer)
├── ExpoController.FileStorage (GenServer for S3/local)
└── Oban (PostgreSQL job queue)
```

### Ecto Schema Design

```elixir
# lib/controller/builds/build.ex
defmodule ExpoController.Builds.Build do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}

  schema "builds" do
    field :status, Ecto.Enum, values: [:pending, :assigned, :building, :completed, :failed]
    field :platform, Ecto.Enum, values: [:ios, :android]
    field :source_path, :string
    field :certs_path, :string
    field :result_path, :string
    field :error_message, :string
    field :last_heartbeat_at, :utc_datetime

    belongs_to :worker, ExpoController.Workers.Worker, type: :string
    has_many :logs, ExpoController.Builds.BuildLog

    timestamps(type: :utc_datetime)
  end
end

# lib/controller/workers/worker.ex
defmodule ExpoController.Workers.Worker do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}

  schema "workers" do
    field :name, :string
    field :status, Ecto.Enum, values: [:idle, :building, :offline]
    field :capabilities, :map
    field :builds_completed, :integer, default: 0
    field :builds_failed, :integer, default: 0
    field :last_seen_at, :utc_datetime

    has_many :builds, ExpoController.Builds.Build
    has_many :diagnostics, ExpoController.Diagnostics.Report

    timestamps(type: :utc_datetime)
  end
end
```

### Phoenix Channels vs LiveView

**Recommendation: Phoenix Channels for worker communication, LiveView for dashboard**

- **Workers:** Channels provide persistent connection, eliminating polling overhead. Server pushes jobs immediately.
- **Dashboard:** LiveView provides real-time updates without custom JS. Built-in reconnection handling.

```elixir
# lib/controller_web/channels/worker_channel.ex
defmodule ExpoControllerWeb.WorkerChannel do
  use ExpoControllerWeb, :channel

  def join("worker:" <> worker_id, %{"api_key" => key}, socket) do
    if valid_api_key?(key) && Workers.exists?(worker_id) do
      Workers.mark_online(worker_id)
      {:ok, assign(socket, :worker_id, worker_id)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_in("heartbeat", %{"build_id" => id, "progress" => p}, socket) do
    Builds.record_heartbeat(id, p)
    {:noreply, socket}
  end

  # Server pushes job when available
  def handle_info({:job_available, build}, socket) do
    push(socket, "job", build_to_json(build))
    {:noreply, socket}
  end
end
```

### GenServer for Queue Management

```elixir
# lib/controller/orchestration/queue_manager.ex
defmodule ExpoController.Orchestration.QueueManager do
  use GenServer

  # Public API
  def enqueue(build_id), do: GenServer.call(__MODULE__, {:enqueue, build_id})
  def assign_to_worker(worker_id), do: GenServer.call(__MODULE__, {:assign, worker_id})

  # Callbacks
  def handle_call({:assign, worker_id}, _from, state) do
    case Repo.transaction(fn ->
      # SELECT ... FOR UPDATE prevents race conditions
      build = Builds.next_pending_for_update()
      if build do
        {:ok, _} = Builds.assign_to_worker(build, worker_id)
        build
      end
    end) do
      {:ok, build} -> {:reply, {:ok, build}, state}
      {:ok, nil} -> {:reply, {:ok, nil}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
end
```

### File Storage with S3 Support

```elixir
# lib/controller/storage/file_storage.ex
defmodule ExpoController.Storage.FileStorage do
  @behaviour ExpoController.Storage.Behaviour

  # Configurable backend: :local | :s3
  def save_source(build_id, upload) do
    case Application.get_env(:controller, :storage_backend) do
      :local -> save_local(upload, source_path(build_id))
      :s3 -> save_s3(upload, source_key(build_id))
    end
  end

  defp save_local(%Plug.Upload{path: temp_path}, dest_path) do
    File.mkdir_p!(Path.dirname(dest_path))
    File.copy!(temp_path, dest_path)
    {:ok, dest_path}
  end

  defp save_s3(%Plug.Upload{path: temp_path}, key) do
    temp_path
    |> ExAws.S3.Upload.stream_file()
    |> ExAws.S3.upload(bucket(), key)
    |> ExAws.request()
  end
end
```

---

## Part 9: Migration Strategy

### Phase 1: Database Migration (Week 1)

1. **Set up Ecto schemas** matching current SQLite structure
2. **Write data migration script** SQLite -> PostgreSQL
3. **Deploy PostgreSQL** alongside existing system
4. **Run dual-write** for validation

**Deliverables:**
- `priv/repo/migrations/` with all schemas
- `mix run priv/repo/seeds.exs` for migration
- Docker Compose with PostgreSQL

### Phase 2: Core API (Weeks 2-3)

1. **Phoenix JSON API** for builds and workers
2. **File upload handling** with Plug.Upload
3. **Authentication plug** with secure_compare
4. **Integration tests** ported from Bun tests

**Coexistence Strategy:**
- Run Elixir on port 4000, TypeScript on 3000
- Nginx reverse proxy routes:
  - `/api/v2/*` -> Elixir
  - `/api/*` -> TypeScript (legacy)
- Workers updated to use v2 endpoints

**Deliverables:**
- All 13 API endpoints ported
- 100% test coverage
- Load test results

### Phase 3: GenServer Orchestration (Week 4)

1. **QueueManager GenServer** replacing JobQueue
2. **HeartbeatMonitor** with configurable timeouts
3. **WorkerRegistry** for connection tracking
4. **Oban integration** for durable jobs

**Deliverables:**
- Supervisor tree implementation
- Crash recovery tests
- Metrics via Telemetry

### Phase 4: Realtime Dashboard (Week 5)

1. **LiveView dashboard** replacing EJS
2. **Phoenix Channels** for worker communication
3. **PubSub** for cross-process updates
4. **Chart.js integration** via hooks

**Deliverables:**
- Zero-refresh dashboard
- Worker WebSocket connection
- Real-time build progress

### Phase 5: Cutover & Cleanup (Week 6)

1. **DNS cutover** to Elixir-only
2. **TypeScript deprecation**
3. **S3/R2 storage migration** (optional)
4. **Documentation update**

---

## Part 10: Performance Considerations

### Database

- **Connection pool:** 10 connections default, scale to 50 under load
- **Indexes:** Already defined in schema.sql, add `(status, submitted_at)` composite
- **Vacuum:** PostgreSQL autovacuum handles this

### Telemetry Ingestion

- **Buffer in GenServer:** Batch inserts every 100ms or 100 events
- **Async processing:** Cast messages, don't block response
- **Compression:** gzip telemetry payloads >1KB

```elixir
def handle_cast({:telemetry, event}, %{buffer: buffer} = state) do
  new_buffer = [event | buffer]
  if length(new_buffer) >= 100 do
    flush_buffer(new_buffer)
    {:noreply, %{state | buffer: []}}
  else
    {:noreply, %{state | buffer: new_buffer}}
  end
end
```

### Concurrent Build Limits

- **Per-worker:** 1 (current design assumes single build per worker)
- **Total system:** Configurable via Oban concurrency
- **Backpressure:** Return `{:error, :queue_full}` when pending > threshold

### File Storage

- **Local:** Direct streaming with sendfile
- **S3:** Presigned URLs for downloads, bypass server
- **Chunk size:** 64KB for uploads

---

## Part 11: Trade-offs Assessment

### Development Time

| Component | TypeScript (existing) | Elixir (estimated) |
|-----------|----------------------|-------------------|
| Core API | Done | 2 weeks |
| Queue system | Done | 1 week |
| Dashboard | Done | 1 week |
| Tests | Done | 1 week |
| DevOps | Minimal | 1 week |
| **Total** | 0 | **6 weeks** |

### Learning Curve

- **Elixir syntax:** 1-2 weeks for proficiency
- **OTP patterns:** 2-4 weeks for confidence
- **Phoenix ecosystem:** 1-2 weeks with prior web experience

**Mitigation:** Start with API ports (familiar patterns), progress to GenServers.

### Operational Complexity

| Aspect | TypeScript | Elixir |
|--------|-----------|--------|
| Deployment | Single binary (Bun) | Release tarball or Docker |
| Monitoring | Ad-hoc logging | Built-in observer, LiveDashboard |
| Debugging | console.log | :observer, remote shell |
| Horizontal scaling | Manual | Built-in distribution |

### When NOT to Use Elixir

1. **Team has zero FP experience** and deadline is < 3 months
2. **System is IO-bound on external services** (Elixir's concurrency advantages don't help)
3. **Existing TypeScript investment** is large and working well
4. **No need for realtime** - REST API is sufficient

### Honest Assessment

**Elixir shines for this use case because:**
- Long-running build processes need supervision
- Worker coordination needs reliable messaging
- Telemetry ingestion needs high throughput
- Dashboard needs realtime updates

**Elixir may be overkill if:**
- Build volume stays < 100/day
- Single server deployment is permanent
- Team won't maintain Elixir long-term

---

## Part 12: Security Analysis

### API Key Management

**Current:** Single shared key in env var
**Elixir Improvement:**
```elixir
# Per-worker keys stored in DB
defmodule ExpoController.Auth do
  def verify_api_key(provided, expected) do
    # Constant-time comparison
    Plug.Crypto.secure_compare(provided, expected)
  end

  def worker_key(worker_id) do
    # Generate unique key per worker
    :crypto.strong_rand_bytes(32) |> Base.url_encode64()
  end
end
```

### Certificate Handling

**Current:** Certs stored on disk, served via authenticated endpoint
**Elixir Improvement:**
- Encrypt at rest with per-build key
- Decrypt in memory only when serving
- Auto-delete after build completion

```elixir
def save_certs(build_id, upload) do
  key = :crypto.strong_rand_bytes(32)
  encrypted = :crypto.crypto_one_time(:aes_256_gcm, key, iv, upload.content, aad, true)

  # Store key in DB, encrypted content on disk
  Repo.update!(build, certs_encryption_key: Base.encode64(key))
  File.write!(certs_path(build_id), encrypted)
end
```

### Worker Authentication

**Current:** X-Worker-Id header, validated against DB
**Elixir Improvement:**
- JWT tokens with short expiry
- Refresh via WebSocket heartbeat
- Revocation list for compromised workers

---

## Part 13: Unresolved Questions

1. **S3/R2 timeline?** Affects storage interface design now vs later.
2. **Multi-region deployment?** Elixir distribution needs planning upfront.
3. **Worker authentication model?** Per-worker keys add complexity but improve security.
4. **Oban vs custom queue?** Oban adds dependency but battle-tested.
5. **LiveView vs SPA?** LiveView simpler but less flexible for complex interactions.
6. **PostgreSQL hosting?** Self-managed vs managed (Supabase, Neon, RDS).
7. **Existing worker client changes?** WebSocket requires worker code updates.
8. **Rollback plan?** If Elixir migration fails, how to revert?

---

## Appendix: File Inventory for Migration

### Must Port (Critical Path)

| TypeScript File | Elixir Equivalent |
|-----------------|-------------------|
| `db/Database.ts` | `lib/controller/repo.ex` + schemas |
| `api/builds/index.ts` | `lib/controller_web/controllers/build_controller.ex` |
| `api/workers/index.ts` | `lib/controller_web/controllers/worker_controller.ex` |
| `services/JobQueue.ts` | `lib/controller/orchestration/queue_manager.ex` |
| `services/FileStorage.ts` | `lib/controller/storage/file_storage.ex` |
| `middleware/auth.ts` | `lib/controller_web/plugs/auth.ex` |

### Can Defer

| TypeScript File | Reason |
|-----------------|--------|
| `views/index.ejs` | Replace with LiveView |
| `demo/generateDemoData.ts` | Low priority, seed data |
| `api/diagnostics/index.ts` | Secondary feature |

### Delete After Migration

- `__tests__/*.ts` - Replaced by ExUnit tests
- `domain/Config.ts` - Replaced by Mix config
- `cli.ts` - Replaced by Mix tasks

