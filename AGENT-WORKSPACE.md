# Agent Workspace Guide

**For AI Agents Working on Expo Free Agent**

This document provides workspace-specific information for AI agents contributing to the Expo Free Agent codebase. It complements the main architecture documentation with practical development guidance.

**IMPORTANT: Read [CLAUDE.md](./CLAUDE.md) first for mandatory rules and guardrails.**

---

## Quick Orientation

### What is Expo Free Agent?

A distributed build system that runs Expo/React Native builds on self-hosted Mac hardware with complete VM isolation.

**Three components:**
1. **Controller** (Elixir/Phoenix) - Central orchestration server
2. **Worker** (Swift/macOS) - Menu bar app that runs builds in VMs
3. **CLI** (TypeScript/Bun) - Developer tool for submitting builds

**Key architectural decisions:**
- Elixir/OTP for concurrency and fault tolerance
- PostgreSQL for atomic build assignment
- Polling-based worker protocol (NAT-friendly)
- Ephemeral Tart VMs for security isolation
- Multi-layer authentication (API key, worker token, build token, OTP, VM token)

**Read first:** [ARCHITECTURE.md](./ARCHITECTURE.md) for complete system design.

---

## Workspace Structure

```
expo-free-agent/
├── packages/
│   ├── controller-elixir/      # Elixir/Phoenix controller
│   ├── cli/                     # TypeScript CLI tool
│   ├── worker-installer/        # Worker installation script
│   └── landing-page/            # Marketing site (Vite + React)
├── free-agent/                  # Swift worker app (macOS)
├── docs/                        # Documentation
│   ├── adr/                     # Architecture Decision Records
│   ├── architecture/            # System design docs
│   ├── getting-started/         # Setup guides
│   ├── operations/              # Deployment and ops
│   └── testing/                 # Test strategies
├── scripts/                     # Utility scripts
├── test/                        # Shared test fixtures
├── ARCHITECTURE.md              # Complete architecture reference
├── CLAUDE.md                    # Mandatory agent rules
├── AGENT-WORKSPACE.md           # This file
└── README.md                    # User-facing overview
```

---

## Why is `free-agent/` at the root?

Swift Package Manager and Bun workspaces are incompatible:
- Swift expects traditional package layout (Sources/, Tests/, Package.swift at root)
- Bun workspaces expect everything in `packages/`
- Moving Swift code to `packages/free-agent/` breaks Xcode project structure

**Solution:** Keep Swift app at root, everything else in `packages/`.

See [ADR-001](./docs/adr/adr-001-monorepo-structure.md) for full rationale.

---

## Technology Stack Quick Reference

| Component | Primary Tech | Secondary Tech | Why |
|-----------|-------------|----------------|-----|
| **Controller** | Elixir 1.15 | Phoenix 1.8, Ecto, PostgreSQL, Bandit | Concurrency, OTP supervision, atomic operations |
| **Worker** | Swift 5.9 | Tart (VM management) | Native macOS APIs, Apple Virtualization Framework |
| **CLI** | TypeScript | Bun (runtime), Commander.js | Fast startup, native TS support |
| **Queue** | PostgreSQL | SELECT FOR UPDATE SKIP LOCKED | Atomic build assignment, no race conditions |
| **VM** | Tart | Apple Virtualization Framework | CLI wrapper, OCI image support, simple lifecycle |
| **Landing Page** | React 19 | Vite, Tailwind CSS v4 | Modern UI framework |

---

## Development Workflow

### Running the Controller (Elixir)

```bash
cd packages/controller-elixir

# Install dependencies
mix deps.get

# Setup database
mix ecto.setup

# Start server
mix phx.server

# Server runs at http://localhost:4000
```

**Database:** PostgreSQL required (not SQLite).

**Environment variables:**
```bash
export DATABASE_URL="postgres://localhost/expo_controller_dev"
export SECRET_KEY_BASE="generate_with_mix_phx_gen_secret"
export API_KEY="your-api-key-here"
```

---

### Running the Worker (Swift)

```bash
cd free-agent

# Build
swift build

# Run (debug mode)
.build/debug/FreeAgent

# Build release
swift build -c release

# Run release
.build/release/FreeAgent
```

**Prerequisites:**
- macOS 14+ on Apple Silicon
- Xcode 16+ installed
- Tart installed (`brew install tart`)

**Configuration:** First run opens settings window to configure controller URL and API key.

---

### Running the CLI (TypeScript/Bun)

```bash
cd packages/cli

# Install dependencies
bun install

# Build
bun run build

# Run locally
bun run dev submit

# Test globally
bun link
expo-build submit --platform ios
```

**Configuration:** `~/.expo-free-agent/config.json` or `EXPO_CONTROLLER_API_KEY` env var.

---

### Running Tests

```bash
# All tests
bun run test:all

# Controller tests (Elixir)
cd packages/controller-elixir
mix test

# CLI tests
cd packages/cli
bun test

# Smoketest (quick validation)
./smoketest.sh

# End-to-end test (requires running controller)
./test-e2e.sh
```

---

## Critical Code Locations

### Controller (Elixir)

**Build lifecycle:**
- `lib/expo_controller/builds.ex` - Build management
  - `next_pending_for_update()` - Atomic build assignment query
  - `assign_to_worker()` - Multi-step transaction
  - `complete_build()` - Mark build finished

**Worker management:**
- `lib/expo_controller/workers.ex` - Worker CRUD
  - `register_worker()` - Initial registration
  - `heartbeat_worker()` - Token rotation
  - `get_worker_by_token()` - Auth lookup

**API endpoints:**
- `lib/expo_controller_web/controllers/build_controller.ex`
  - `create()` - POST /api/builds
  - `download_source()` - GET /api/builds/:id/source
  - `download_certs_secure()` - GET /api/builds/:id/certs-secure

- `lib/expo_controller_web/controllers/worker_controller.ex`
  - `register()` - POST /api/workers/register
  - `poll()` - GET /api/workers/poll
  - `upload()` - POST /api/workers/upload

**Authentication:**
- `lib/expo_controller_web/plugs/auth.ex`
  - `require_api_key()` - API key validation
  - `require_worker_token()` - Worker token validation
  - `require_build_access()` - Build ownership validation

**File storage:**
- `lib/expo_controller/file_storage.ex`
  - `save_source()` - Store source tarball
  - `save_certs()` - Store certificates
  - `read_stream()` - Stream file download
  - All operations use `safe_join()` for path traversal protection

---

### Worker (Swift)

**Main coordination:**
- `free-agent/Sources/WorkerCore/WorkerService.swift`
  - `registerWorker()` - Lines 103-170
  - `pollForJob()` - Lines 205-275
  - `performBuild()` - Lines 295-368
  - `uploadBuildResult()` - Lines 417-473

**VM management:**
- `free-agent/Sources/BuildVM/TartVMManager.swift`
  - `executeBuild()` - Clone, start, execute, destroy VM
  - `waitForBootstrap()` - Poll for vm-ready signal
  - `cleanup()` - Delete VM disk

**Configuration:**
- `free-agent/Sources/WorkerCore/WorkerConfiguration.swift`
  - Persisted settings (controller URL, API key, tokens)
  - Thread-safe access
  - Auto-save on changes

---

### CLI (TypeScript)

**Commands:**
- `packages/cli/src/commands/submit.ts` - Build submission
- `packages/cli/src/commands/status.ts` - Status checking
- `packages/cli/src/commands/download.ts` - Artifact download

**API client:**
- `packages/cli/src/api-client.ts`
  - Multipart form uploads
  - Streaming downloads
  - Authentication headers

---

## Common Tasks for Agents

### Adding a New API Endpoint

**1. Controller (Elixir):**

```elixir
# lib/expo_controller_web/router.ex
scope "/api", ExpoControllerWeb do
  pipe_through [:api, :require_api_key]
  get "/builds/:id/metadata", BuildController, :get_metadata
end

# lib/expo_controller_web/controllers/build_controller.ex
def get_metadata(conn, %{"id" => build_id}) do
  case Builds.get_build(build_id) do
    nil -> conn |> put_status(:not_found) |> json(%{error: "Not found"})
    build -> json(conn, %{metadata: build.metadata})
  end
end
```

**2. Worker (Swift):**

```swift
// WorkerService.swift
private func fetchMetadata(_ buildId: String) async throws -> BuildMetadata {
    let url = URL(string: "\(controllerURL)/api/builds/\(buildId)/metadata")!
    var request = URLRequest(url: url)
    request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw WorkerError.fetchFailed
    }

    return try JSONDecoder().decode(BuildMetadata.self, from: data)
}
```

**3. CLI (TypeScript):**

```typescript
// api-client.ts
async getMetadata(buildId: string): Promise<BuildMetadata> {
  const response = await fetch(`${this.baseURL}/api/builds/${buildId}/metadata`, {
    headers: {
      'X-API-Key': this.apiKey
    }
  });

  if (!response.ok) {
    throw new Error(`Failed to fetch metadata: ${response.statusText}`);
  }

  return await response.json();
}
```

**4. Tests:**

```elixir
# test/expo_controller_web/controllers/build_controller_test.exs
test "GET /api/builds/:id/metadata returns metadata", %{conn: conn} do
  build = insert(:build, metadata: %{version: "1.0.0"})

  conn = get(conn, "/api/builds/#{build.id}/metadata")

  assert json_response(conn, 200) == %{
    "metadata" => %{"version" => "1.0.0"}
  }
end
```

---

### Adding Database Migration

```bash
cd packages/controller-elixir

# Generate migration
mix ecto.gen.migration add_metadata_to_builds

# Edit migration file
# priv/repo/migrations/YYYYMMDDHHMMSS_add_metadata_to_builds.exs
```

```elixir
defmodule ExpoController.Repo.Migrations.AddMetadataToBuilds do
  use Ecto.Migration

  def change do
    alter table(:builds) do
      add :metadata, :map, default: %{}
    end

    create index(:builds, [:metadata], using: :gin)  # For JSONB queries
  end
end
```

```bash
# Run migration
mix ecto.migrate

# Rollback if needed
mix ecto.rollback
```

**Update schema:**

```elixir
# lib/expo_controller/builds/build.ex
schema "builds" do
  field :metadata, :map, default: %{}
  # ... existing fields
end

def changeset(build, attrs) do
  build
  |> cast(attrs, [:metadata])
  |> validate_required([...])
end
```

---

### Adding Worker Configuration Option

**1. Add to schema:**

```swift
// WorkerConfiguration.swift
public struct WorkerConfiguration: Codable {
    // Existing fields...
    public var newSetting: Bool = false

    enum CodingKeys: String, CodingKey {
        // ... existing keys
        case newSetting = "new_setting"
    }
}
```

**2. Add UI setting:**

```swift
// SettingsView.swift
Toggle("Enable New Feature", isOn: $configuration.newSetting)
    .onChange(of: configuration.newSetting) { _, _ in
        try? configuration.save()
    }
```

**3. Use in worker:**

```swift
// WorkerService.swift
if configuration.newSetting {
    // New behavior
} else {
    // Existing behavior
}
```

---

### Debugging Build Failures

**1. Check controller logs:**

```bash
# Elixir controller
cd packages/controller-elixir
tail -f _build/dev/lib/expo_controller/ebin/expo_controller.log

# Or live console
iex -S mix phx.server
```

**2. Check worker logs:**

```bash
# Swift worker
tail -f ~/Library/Logs/FreeAgent/worker.log

# Or run with verbose output
swift run FreeAgent --verbose
```

**3. Check VM logs:**

```bash
# Bootstrap logs
cat /mnt/build-config/bootstrap.log

# Build logs
cat /tmp/build-{id}/build.log
```

**4. Database inspection:**

```bash
psql -d expo_controller_dev

SELECT id, status, worker_id, submitted_at, completed_at
FROM builds
WHERE status != 'completed'
ORDER BY submitted_at DESC
LIMIT 10;

SELECT id, name, status, last_seen_at
FROM workers
ORDER BY last_seen_at DESC;
```

---

## Testing Strategy

### Unit Tests

**Elixir:**
```bash
cd packages/controller-elixir
mix test

# Specific test
mix test test/expo_controller/builds_test.exs

# With coverage
mix test --cover
```

**TypeScript:**
```bash
cd packages/cli
bun test

# Watch mode
bun test --watch
```

---

### Integration Tests

**End-to-end flow:**
```bash
# Requires running controller
./test-e2e.sh

# Or manual steps:
# 1. Start controller
cd packages/controller-elixir && mix phx.server

# 2. Start worker
cd free-agent && swift run FreeAgent

# 3. Submit build
cd packages/cli && bun run dev submit test/fixtures/simple-app
```

---

### Race Condition Tests

**Concurrent worker polling:**
```bash
cd packages/controller-elixir
mix test test/expo_controller/builds_test.exs:concurrency_test

# Should pass: 20 workers competing for 10 builds → exactly 10 succeed
```

**Concurrency test structure:**
```elixir
test "concurrent workers compete for builds without race conditions" do
  # Create 10 pending builds
  builds = for _ <- 1..10, do: insert(:build, status: :pending)

  # Create 20 workers
  workers = for _ <- 1..20, do: insert(:worker)

  # All poll simultaneously
  tasks = Enum.map(workers, fn worker ->
    Task.async(fn ->
      Builds.next_pending_for_update()
      |> Builds.assign_to_worker(worker.id)
    end)
  end)

  results = Enum.map(tasks, &Task.await/1)

  # Exactly 10 should succeed
  successes = Enum.count(results, &match?({:ok, _}, &1))
  assert successes == 10
end
```

---

## Architecture Patterns to Follow

### 1. Atomic Database Operations

**Always use transactions for multi-step operations:**

```elixir
# ✅ CORRECT - Transaction
def assign_build(build_id, worker_id) do
  Repo.transaction(fn ->
    with {:ok, build} <- get_and_lock_build(build_id),
         {:ok, worker} <- validate_worker(worker_id),
         {:ok, _} <- update_build_status(build, :assigned),
         {:ok, _} <- update_worker_status(worker, :building) do
      build
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end)
end

# ❌ WRONG - Separate queries (race condition)
def assign_build(build_id, worker_id) do
  build = get_build(build_id)
  update_build_status(build, :assigned)  # Another worker might claim it here
  update_worker_status(worker_id, :building)
end
```

---

### 2. Token Rotation Pattern

**Always rotate tokens on authenticated requests:**

```elixir
# ✅ CORRECT - Rotate on poll
def poll(conn, _params) do
  worker = conn.assigns.worker  # Authenticated via token

  # Rotate token (new token, new expiration)
  {:ok, updated_worker} = Workers.heartbeat_worker(worker)

  # Return new token in response
  json(conn, %{
    job: try_assign_build(worker.id),
    access_token: updated_worker.access_token  # Client updates
  })
end

# ❌ WRONG - Static token
def poll(conn, _params) do
  worker = conn.assigns.worker
  json(conn, %{job: try_assign_build(worker.id)})  # Token never rotates
end
```

---

### 3. Path Traversal Protection

**Always validate file paths:**

```elixir
# ✅ CORRECT - Safe join
def read_build_file(build_id, filename) do
  base_path = FileStorage.builds_path()
  file_path = Path.join([base_path, build_id, filename])

  case FileStorage.safe_join(base_path, file_path) do
    {:ok, safe_path} -> File.read!(safe_path)
    {:error, :unsafe} -> raise "Path traversal attempt"
  end
end

# ❌ WRONG - Direct concatenation
def read_build_file(build_id, filename) do
  # Vulnerable to: filename = "../../etc/passwd"
  File.read!("/data/builds/#{build_id}/#{filename}")
end
```

---

### 4. Streaming Large Files

**Never buffer entire file in memory:**

```elixir
# ✅ CORRECT - Stream
def download_source(conn, %{"id" => build_id}) do
  {:ok, stream} = FileStorage.read_stream(build_id, "source.zip")

  conn
  |> put_resp_content_type("application/zip")
  |> send_chunked(200)
  |> stream_file(stream)
end

defp stream_file(conn, stream) do
  Enum.reduce_while(stream, conn, fn chunk, conn ->
    case Plug.Conn.chunk(conn, chunk) do
      {:ok, conn} -> {:cont, conn}
      {:error, :closed} -> {:halt, conn}
    end
  end)
end

# ❌ WRONG - Load into memory
def download_source(conn, %{"id" => build_id}) do
  file_data = File.read!("/data/builds/#{build_id}/source.zip")  # 500MB RAM!
  send_resp(conn, 200, file_data)
end
```

---

### 5. Error Handling with `with`

**Use `with` for chained operations:**

```elixir
# ✅ CORRECT - with clause
def complete_build(build_id, result_path) do
  Repo.transaction(fn ->
    with {:ok, build} <- get_build(build_id),
         {:ok, _} <- validate_result(result_path),
         {:ok, build} <- update_build(build, :completed, result_path),
         {:ok, _} <- update_worker(build.worker_id, :idle) do
      build
    else
      {:error, :not_found} -> Repo.rollback(:build_not_found)
      {:error, reason} -> Repo.rollback(reason)
    end
  end)
end

# ❌ WRONG - Nested case statements
def complete_build(build_id, result_path) do
  case get_build(build_id) do
    {:ok, build} ->
      case validate_result(result_path) do
        {:ok, _} ->
          case update_build(build, :completed, result_path) do
            {:ok, build} ->
              # ... more nesting
          end
      end
  end
end
```

---

## Common Pitfalls to Avoid

### 1. Race Conditions

**Problem:** Multiple workers claiming same build

**Solution:** Use `SELECT FOR UPDATE SKIP LOCKED`

```elixir
# ✅ Atomic
from(b in Build,
  where: b.status == :pending,
  limit: 1,
  lock: "FOR UPDATE SKIP LOCKED"
)
|> Repo.one()

# ❌ Race condition
from(b in Build, where: b.status == :pending, limit: 1)
|> Repo.one()
```

---

### 2. Token Expiration

**Problem:** Worker token expires mid-operation

**Solution:** Always re-register on 401/404

```swift
// ✅ Auto-recovery
else if httpResponse.statusCode == 401 {
    configuration.accessToken = nil
    try await registerWorker()
    return try await pollForJob()  // Retry with new token
}

// ❌ Crash on expiration
else if httpResponse.statusCode == 401 {
    throw WorkerError.unauthorized  // Worker stops working
}
```

---

### 3. Path Traversal

**Problem:** User input in file paths

**Solution:** Always use `safe_join()`

```elixir
# ✅ Safe
FileStorage.safe_join(base_path, user_input)

# ❌ Vulnerable
Path.join([base_path, user_input])
```

---

### 4. Memory Buffering

**Problem:** Loading 500MB file into memory

**Solution:** Stream with chunked transfer

```elixir
# ✅ Streaming
send_chunked(conn, 200) |> stream_file(file_stream)

# ❌ Buffering
send_resp(conn, 200, File.read!(large_file))
```

---

### 5. Certificate Persistence

**Problem:** Certificates stored on disk after build

**Solution:** Ephemeral keychain in VM, destroyed with VM

```bash
# ✅ Ephemeral
security create-keychain -p pwd build.keychain
# ... use keychain
tart delete vm-{id}  # Keychain destroyed

# ❌ Persistent
security import cert.p12 -k login.keychain  # Persists across builds!
```

---

## Documentation Requirements

### When to Create ADR

Create Architecture Decision Record (ADR) when:
- Choosing between architectural patterns
- Selecting frameworks/libraries/tools
- Defining API contracts or data models
- Establishing security policies
- Making performance trade-offs
- Changing core infrastructure

**ADR Template:** `docs/adr/template.md`

**Example ADRs:**
- [ADR-0009: Elixir Migration](./docs/adr/0009-migrate-controller-to-elixir.md) - Controller rewrite
- [ADR-0007: Polling Protocol](./docs/adr/0007-polling-based-worker-protocol.md) - Communication pattern
- [ADR-0010: Token Rotation](./docs/adr/0010-worker-token-rotation.md) - Security mechanism

---

### When to Update Architecture Docs

Update [ARCHITECTURE.md](./ARCHITECTURE.md) when:
- Adding new component
- Changing authentication flow
- Modifying data flow
- Adding new phase to build lifecycle
- Changing technology stack

**Update locations:**
- Component diagrams
- Flow diagrams (ASCII art)
- Authentication chain
- Technology stack table
- Performance characteristics

---

### When to Update README

Update [README.md](./README.md) when:
- Adding user-facing feature
- Changing CLI commands
- Modifying installation steps
- Adding new deployment option
- Changing system requirements

**Keep user-focused:** README is for developers using the system, not contributors.

---

## Agent Workflow Checklist

Before implementing a feature:
- [ ] Read [ARCHITECTURE.md](./ARCHITECTURE.md) to understand system design
- [ ] Check [ADRs](./docs/adr/) for related decisions
- [ ] Review existing code in same area
- [ ] Identify atomic operations needed (database transactions)
- [ ] Plan authentication/authorization flow
- [ ] Consider race conditions and concurrent access
- [ ] Design with failure recovery in mind

During implementation:
- [ ] Follow patterns from similar existing code
- [ ] Use `with` clause for chained operations
- [ ] Add transactions for multi-step database ops
- [ ] Validate and sanitize all inputs
- [ ] Stream large files (no buffering)
- [ ] Test with concurrent requests
- [ ] Add error handling for all failure modes

After implementation:
- [ ] Write/update tests (unit + integration)
- [ ] Update relevant documentation
- [ ] Create ADR if architectural decision made
- [ ] Verify builds pass (`bun run test:all`)
- [ ] Test manually with running system
- [ ] Check for race conditions (concurrent test)

---

## Getting Help

**Documentation:**
- [ARCHITECTURE.md](./ARCHITECTURE.md) - System design
- [docs/INDEX.md](./docs/INDEX.md) - All documentation
- [ADRs](./docs/adr/) - Architecture decisions
- [CLAUDE.md](./CLAUDE.md) - Agent rules

**Code examples:**
- Controller: `packages/controller-elixir/lib/expo_controller/`
- Worker: `free-agent/Sources/`
- CLI: `packages/cli/src/`

**Tests:**
- Controller: `packages/controller-elixir/test/`
- CLI: `packages/cli/__tests__/`
- E2E: `test-e2e.sh`

**Issues:**
- [GitHub Issues](https://github.com/expo/expo-free-agent/issues) - Bug reports
- [GitHub Discussions](https://github.com/expo/expo-free-agent/discussions) - Questions

---

## Final Reminders

1. **Read CLAUDE.md** - Mandatory rules for all agents
2. **Follow existing patterns** - Don't invent new approaches
3. **Test concurrently** - Race conditions are real
4. **Document decisions** - Create ADRs for significant choices
5. **Think critically** - Challenge assumptions, explore alternatives
6. **Fail fast** - No silent failures or degraded modes
7. **Stream, don't buffer** - Memory efficiency matters
8. **Atomic operations** - Transactions prevent race conditions

**Most important:** Understand the "why" behind patterns, not just the "how". The architecture documentation explains rationale for every decision.

---

**Expo Free Agent** - Built with precision, documented with care.
