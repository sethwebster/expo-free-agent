# Code Review: Elixir Controller Migration Plan

**Date:** 2026-01-27
**Reviewer:** Claude Code
**Files Reviewed:** 28 files in `packages/controller-elixir/`
**Severity Levels:** Critical / High / Medium / Low / Nitpick

---

## Executive Summary

The Elixir migration demonstrates solid OTP fundamentals and addresses key issues from the TypeScript version (race conditions, memory exhaustion, timing attacks). However, several **critical security vulnerabilities**, **architectural flaws**, and **data integrity risks** require attention before production deployment.

**Verdict:** Not production-ready. Requires fixes to Critical and High severity issues.

---

## Critical Issues

### C1. API Key Not Configured - Application Crashes on nil Comparison

**Location:** `/packages/controller-elixir/lib/expo_controller_web/plugs/auth.ex:16-19`

**Problem:** If `api_key` config is not set, `Plug.Crypto.secure_compare(provided_key, nil)` will crash.

```elixir
def require_api_key(conn, _opts) do
  api_key = Application.get_env(:expo_controller, :api_key)  # Could be nil
  provided_key = get_req_header(conn, "x-api-key") |> List.first()

  if provided_key && Plug.Crypto.secure_compare(provided_key, api_key) do  # CRASH if api_key is nil
```

**Impact:** Production crash on any authenticated request if env var missing.

**Solution:** Add startup validation in `Application.start/2`:
```elixir
api_key = Application.get_env(:expo_controller, :api_key)
unless api_key && byte_size(api_key) >= 32 do
  raise "CONTROLLER_API_KEY must be set and at least 32 characters"
end
```

---

### C2. Race Condition in QueueManager - In-Memory Queue Diverges from DB

**Location:** `/packages/controller-elixir/lib/expo_controller/orchestration/queue_manager.ex:78-91`

**Problem:** The `next_for_worker` function maintains an in-memory queue that can diverge from database state. If assignment fails, the build is removed from the queue anyway:

```elixir
[build_id | rest] ->
  case assign_build_to_worker(build_id, worker_id) do
    {:ok, build} ->
      new_state = %{state | queue: rest}  # Removed from queue
      ...
    {:error, reason} ->
      Logger.warning("Failed to assign build #{build_id}: #{inspect(reason)}")
      new_state = %{state | queue: rest}  # ALSO removed from queue - BUILD LOST
      {:reply, {:error, reason}, new_state}
```

**Impact:** Build requests silently disappear. Users submit builds that never execute.

**Solution:** On assignment failure, either keep in queue or re-query database for actual pending builds:
```elixir
{:error, reason} ->
  # Build may have been cancelled/completed - refresh from DB
  {:reply, {:error, reason}, restore_queue_from_db()}
```

---

### C3. Missing Transaction in Worker Poll Endpoint

**Location:** `/packages/controller-elixir/lib/expo_controller_web/controllers/worker_controller.ex:54-68`

**Problem:** `try_assign_build/1` calls `next_pending_for_update()` outside a transaction:

```elixir
defp try_assign_build(worker_id) do
  case Builds.next_pending_for_update() do  # SELECT FOR UPDATE outside transaction
    nil -> {:error, :no_pending_builds}
    build -> Builds.assign_to_worker(build, worker_id)  # Transaction starts HERE
  end
end
```

**Impact:** The `SELECT FOR UPDATE SKIP LOCKED` is useless without an enclosing transaction. The lock is released immediately. Two workers can get the same build.

**Solution:** Wrap entire operation in transaction:
```elixir
defp try_assign_build(worker_id) do
  Repo.transaction(fn ->
    case Builds.next_pending_for_update() do
      nil -> {:error, :no_pending_builds}
      build -> Builds.assign_to_worker(build, worker_id)
    end
  end)
end
```

---

### C4. Path Traversal Validation Insufficient

**Location:** `/packages/controller-elixir/lib/expo_controller/storage/file_storage.ex:107-113`

**Problem:** Path validation only checks for `..` substring:

```elixir
defp validate_path(path) do
  if String.contains?(path, "..") do
    {:error, :invalid_path}
  else
    :ok
  end
end
```

**Impact:** Attacker can use `build_id` like `/etc/passwd` or absolute paths to read/write arbitrary files. The `build_id` flows directly into path construction:

```elixir
defp source_path(build_id) do
  "builds/#{build_id}/source.tar.gz"  # build_id = "../../../etc/passwd" passes validation
```

Wait - actually `..` IS checked. But what about `build_id = "../../etc"` ? That contains `..` so it would be blocked. Let me re-check...

Actually the issue is different: `validate_path` is called AFTER `ensure_directory` and with `dest_path`, not `build_id`. The build_id is interpolated into paths without validation.

**Solution:** Validate build_id is a UUID format before use:
```elixir
defp validate_build_id(build_id) do
  case Ecto.UUID.cast(build_id) do
    {:ok, _} -> :ok
    :error -> {:error, :invalid_build_id}
  end
end
```

---

### C5. Sensitive Data in Error Responses

**Location:** `/packages/controller-elixir/lib/expo_controller_web/controllers/worker_controller.ex:94-96`

**Problem:** Internal errors leak to clients:

```elixir
{:error, reason} ->
  conn
  |> put_status(:internal_server_error)
  |> json(%{error: "Upload failed", reason: inspect(reason)})
```

**Impact:** Stack traces, database errors, file paths exposed to attackers.

**Solution:** Log internally, return generic error:
```elixir
{:error, reason} ->
  Logger.error("Upload failed: #{inspect(reason)}")
  conn
  |> put_status(:internal_server_error)
  |> json(%{error: "Upload failed"})
```

Same issue in `build_controller.ex:43-45`, `worker_controller.ex:111-112`, `build_controller.ex:143-146`.

---

## High Severity Issues

### H1. Supervision Strategy Too Aggressive - Single Failure Cascades

**Location:** `/packages/controller-elixir/lib/expo_controller/application.ex:24`

**Problem:** `:one_for_one` strategy with QueueManager and HeartbeatMonitor depending on Repo:

```elixir
children = [
  ExpoControllerWeb.Telemetry,
  ExpoController.Repo,               # If this dies...
  {Phoenix.PubSub, ...},
  {ExpoController.Orchestration.QueueManager, []},      # ...this crashes on DB call
  {ExpoController.Orchestration.HeartbeatMonitor, []},  # ...this too
  ExpoControllerWeb.Endpoint
]
opts = [strategy: :one_for_one, ...]
```

**Impact:** If Repo restarts, GenServers crash trying to query DB before Repo is ready.

**Solution:** Use `:rest_for_one` or add explicit dependency handling in GenServer init:
```elixir
def init(_opts) do
  # Wait for Repo to be available
  Process.sleep(100)
  ...
end
```

Better: Use `:rest_for_one` strategy.

---

### H2. Worker Registration Allows ID Collision

**Location:** `/packages/controller-elixir/lib/expo_controller/workers.ex:31-35`

**Problem:** `register_worker` always does `Repo.insert()`. If worker_id already exists, it errors instead of updating.

```elixir
def register_worker(attrs \\ %{}) do
  attrs
  |> Worker.registration_changeset()
  |> Repo.insert()  # FAILS if ID exists
end
```

**Impact:** Workers cannot re-register after restart. Must manually delete from DB.

**Solution:** Use `Repo.insert_or_update/1` or ON CONFLICT clause:
```elixir
def register_worker(attrs) do
  attrs
  |> Worker.registration_changeset()
  |> Repo.insert(
    on_conflict: {:replace, [:name, :capabilities, :status, :last_seen_at]},
    conflict_target: :id
  )
end
```

---

### H3. No File Upload Size Limit

**Location:** `/packages/controller-elixir/lib/expo_controller/storage/file_storage.ex:12-15`

**Problem:** No validation of uploaded file sizes. Attackers can exhaust disk space.

```elixir
def save_source(build_id, %Plug.Upload{} = upload) do
  path = source_path(build_id)
  save_file(upload, path)  # No size check
end
```

**Impact:** Disk exhaustion DoS.

**Solution:** Add size validation before save:
```elixir
@max_source_size 500 * 1024 * 1024  # 500MB

def save_source(build_id, %Plug.Upload{} = upload) do
  with :ok <- validate_file_size(upload.path, @max_source_size) do
    ...
  end
end

defp validate_file_size(path, max) do
  case File.stat(path) do
    {:ok, %{size: size}} when size <= max -> :ok
    {:ok, _} -> {:error, :file_too_large}
    {:error, _} = err -> err
  end
end
```

---

### H4. Build Logs Unbounded - Memory/Storage DoS

**Location:** `/packages/controller-elixir/lib/expo_controller/builds.ex:232-236`

**Problem:** No limit on log entries per build:

```elixir
def add_log(build_id, level, message) do
  build_id
  |> BuildLog.create_changeset(level, message)
  |> Repo.insert()  # Unlimited inserts
end
```

**Impact:** Malicious worker can spam millions of log entries, exhausting database.

**Solution:** Add counter and reject after limit:
```elixir
@max_logs_per_build 10_000

def add_log(build_id, level, message) do
  count = Repo.aggregate(from(l in BuildLog, where: l.build_id == ^build_id), :count)
  if count >= @max_logs_per_build do
    {:error, :log_limit_exceeded}
  else
    ...
  end
end
```

---

### H5. No Timeout on Database Transactions

**Location:** `/packages/controller-elixir/lib/expo_controller/builds.ex:80-89`

**Problem:** Transactions have no timeout, can hold locks indefinitely:

```elixir
Repo.transaction(fn ->
  with {:ok, worker} <- get_and_validate_worker(worker_id),
       {:ok, build} <- update_build_assignment(build, worker_id),
       ...
end)
```

**Impact:** Slow operations block other workers from getting builds.

**Solution:** Add transaction timeout:
```elixir
Repo.transaction(fn -> ... end, timeout: 5_000)
```

---

### H6. String.to_integer Without Validation

**Location:** `/packages/controller-elixir/lib/expo_controller_web/controllers/build_controller.ex:84`

**Problem:** Direct `String.to_integer/1` on user input:

```elixir
def logs(conn, %{"id" => id} = params) do
  limit = Map.get(params, "limit", "100") |> String.to_integer()  # CRASH on "abc"
```

**Impact:** Any non-numeric `limit` crashes the endpoint.

**Solution:** Use `Integer.parse/1`:
```elixir
limit =
  case Integer.parse(Map.get(params, "limit", "100")) do
    {n, ""} when n > 0 and n <= 1000 -> n
    _ -> 100
  end
```

---

## Medium Severity Issues

### M1. Counter Increment Race Condition

**Location:** `/packages/controller-elixir/lib/expo_controller/workers/worker.ex:77-79`

**Problem:** Counters incremented via read-modify-write:

```elixir
def increment_completed_changeset(worker) do
  change(worker, builds_completed: worker.builds_completed + 1)
end
```

**Impact:** Lost updates under concurrency. Counter underreports.

**Solution:** Use database-level increment:
```elixir
def increment_completed(worker_id) do
  from(w in Worker, where: w.id == ^worker_id)
  |> Repo.update_all(inc: [builds_completed: 1])
end
```

---

### M2. `list_builds` Has No Pagination

**Location:** `/packages/controller-elixir/lib/expo_controller/builds.ex:14-20`

**Problem:** Returns all builds without limit:

```elixir
def list_builds(filters \\ %{}) do
  Build
  |> apply_filters(filters)
  |> order_by([b], desc: b.submitted_at)
  |> Repo.all()  # Could be millions of rows
  |> Repo.preload(:worker)
end
```

**Impact:** Memory exhaustion, slow responses, database strain.

**Solution:** Add mandatory pagination:
```elixir
def list_builds(filters \\ %{}, opts \\ []) do
  limit = Keyword.get(opts, :limit, 50)
  offset = Keyword.get(opts, :offset, 0)

  Build
  |> apply_filters(filters)
  |> order_by([b], desc: b.submitted_at)
  |> limit(^limit)
  |> offset(^offset)
  |> Repo.all()
  |> Repo.preload(:worker)
end
```

---

### M3. timer.send_interval Leaks on Reconnect

**Location:** `/packages/controller-elixir/lib/expo_controller_web/live/dashboard_live.ex:18`

**Problem:** Each mount creates new interval timer:

```elixir
if connected?(socket) do
  ...
  :timer.send_interval(5000, self(), :refresh_stats)
end
```

**Impact:** If LiveView reconnects rapidly, timers accumulate causing duplicate refreshes.

**Solution:** Store timer ref and cancel on terminate:
```elixir
def mount(...) do
  if connected?(socket) do
    ref = :timer.send_interval(5000, self(), :refresh_stats)
    socket = assign(socket, :timer_ref, ref)
  end
end

def terminate(_reason, socket) do
  if socket.assigns[:timer_ref] do
    :timer.cancel(socket.assigns.timer_ref)
  end
end
```

---

### M4. Missing Index on last_heartbeat_at

**Location:** `/packages/controller-elixir/priv/repo/migrations/20260127024523_create_workers.exs`

**Problem:** `mark_stuck_builds_as_failed` queries on `last_heartbeat_at`:

```elixir
from(b in Build,
  where: b.status in [:assigned, :building],
  where: b.last_heartbeat_at < ^cutoff or is_nil(b.last_heartbeat_at)
)
```

No index exists for this column.

**Impact:** Full table scan on every heartbeat check.

**Solution:** Add composite index:
```elixir
create index(:builds, [:status, :last_heartbeat_at])
```

---

### M5. Application.compile_env for Storage Root

**Location:** `/packages/controller-elixir/lib/expo_controller/storage/file_storage.ex:7`

**Problem:** `@storage_root` uses compile-time config:

```elixir
@storage_root Application.compile_env(:expo_controller, :storage_root, "./storage")
```

**Impact:** Cannot change storage path without recompilation. Production releases ignore runtime config.

**Solution:** Use `Application.get_env/3` at runtime:
```elixir
defp storage_root do
  Application.get_env(:expo_controller, :storage_root, "./storage")
end
```

---

### M6. Public Dashboard Exposes Internal Data

**Location:** `/packages/controller-elixir/lib/expo_controller_web/router.ex:18-23`

**Problem:** Dashboard accessible without authentication:

```elixir
scope "/", ExpoControllerWeb do
  pipe_through :browser
  live "/", DashboardLive  # No auth
end
```

**Impact:** Anyone can see build IDs, worker names, queue status.

**Solution:** Add basic auth or restrict to internal network.

---

### M7. builds_today Calculation Wrong

**Location:** `/packages/controller-elixir/lib/expo_controller_web/controllers/public_controller.ex:21`

**Problem:** `builds_today` calculates wrong value:

```elixir
builds_today = build_stats.completed + build_stats.failed  # ALL TIME, not today
```

Comment even acknowledges this:
```elixir
# Calculate builds today (placeholder - would need date filtering in real impl)
```

**Impact:** Misleading statistics on landing page.

**Solution:** Add proper date-filtered query in Builds context.

---

## Low Severity Issues

### L1. No Request Rate Limiting

**Location:** Router/endpoint level

**Problem:** No rate limiting configured. Mentioned as Phase 4-6 TODO.

**Impact:** DoS via request flooding.

**Solution:** Add `PlugAttack` or `Hammer` before production.

---

### L2. WebSocket Authentication Doesn't Validate Worker State

**Location:** `/packages/controller-elixir/lib/expo_controller_web/channels/worker_socket.ex:20`

**Problem:** Only checks worker exists, not status:

```elixir
!ExpoController.Workers.exists?(worker_id) ->
  {:error, :worker_not_found}
```

**Impact:** Offline workers can connect via WebSocket.

**Solution:** Check worker status is not `:offline`.

---

### L3. Missing Telemetry for Critical Operations

**Location:** All contexts

**Problem:** No `:telemetry.execute/3` calls for build assignments, completions, failures.

**Impact:** Cannot monitor system health via metrics.

**Solution:** Add telemetry events:
```elixir
:telemetry.execute(
  [:expo_controller, :build, :assigned],
  %{system_time: System.system_time()},
  %{build_id: build.id, worker_id: worker_id}
)
```

---

### L4. Hard-coded Magic Numbers

**Location:** Multiple files

**Problem:** Timeouts scattered as raw numbers:
- `5_000` (stats broadcast interval)
- `60_000` (heartbeat check interval)
- `300` (build/worker timeout)
- `64_000` (file stream chunk size)

**Solution:** Define as module attributes or config values with documentation.

---

### L5. No Health Check Endpoint

**Location:** Router

**Problem:** No `/health` or `/ready` endpoint for load balancer/k8s probes.

**Solution:** Add lightweight endpoint:
```elixir
get "/health", fn conn, _ ->
  send_resp(conn, 200, "ok")
end
```

---

## DRY Opportunities

### D1. Duplicate Error Handling Pattern

**Location:** `worker_controller.ex` and `build_controller.ex`

**Problem:** Repeated pattern:
```elixir
{:error, :not_found} ->
  conn
  |> put_status(:not_found)
  |> json(%{error: "X not found"})
```

**Solution:** Create error handling plug or fallback controller.

---

### D2. Duplicate get_build Helper

**Location:** `worker_controller.ex:141-145` and `build_controller.ex:210-214`

Identical functions in both controllers.

**Solution:** Move to shared helper module or Builds context.

---

### D3. Duplicate get_upload Pattern

**Location:** `worker_controller.ex:148-152` and `build_controller.ex:164-168`

Similar functions with slight differences.

**Solution:** Unify in shared module.

---

### D4. Statistics Query Fragments Duplicated

**Location:** `builds.ex:276-285` and `workers.ex:99-107`

Same CASE/SUM pattern for status counting.

**Solution:** Create macro or shared function for aggregation queries.

---

## Testing Gaps

### T1. No Test Files Present

The migration plan mentions ExUnit tests as Phase 4-6 TODO. Current state:
- 0 test files
- No test helpers
- No factory/fixture setup

**Required test coverage:**
1. Authentication plug tests (API key validation, timing attack resistance)
2. Transaction isolation tests (concurrent worker polling)
3. File storage tests (path traversal attempts)
4. GenServer tests (queue restoration, heartbeat detection)
5. Integration tests (full build lifecycle)
6. Load tests (concurrent workers)

---

### T2. No Property-Based Testing for Edge Cases

Build IDs, worker IDs, and file paths should be tested with StreamData for:
- Unicode handling
- Very long strings
- Empty strings
- Special characters

---

## Strengths

1. **SELECT FOR UPDATE SKIP LOCKED** - Correct PostgreSQL pattern for queue contention (when used in transaction)
2. **Constant-time API key comparison** - `Plug.Crypto.secure_compare` prevents timing attacks
3. **Streaming file downloads** - `send_chunked` prevents memory exhaustion
4. **Proper OTP structure** - Supervision tree, GenServers, PubSub
5. **Phoenix Channels for push** - Eliminates polling overhead
6. **LiveView dashboard** - Real-time monitoring without JavaScript
7. **Ecto Enum types** - Type safety for status fields
8. **UTC timestamps throughout** - No timezone confusion

---

## Production Readiness Checklist

| Item | Status | Notes |
|------|--------|-------|
| API key validation | FAIL | Crashes on nil |
| Race condition fix | FAIL | Missing transaction wrapper |
| Path traversal | WARN | Needs build_id validation |
| File size limits | FAIL | No limits |
| Pagination | FAIL | Unbounded queries |
| Rate limiting | FAIL | Not implemented |
| Error sanitization | FAIL | Leaks internals |
| Health endpoint | FAIL | Missing |
| Tests | FAIL | None exist |
| Telemetry | WARN | Basic only |
| S3 storage | FAIL | Local only |
| TLS | WARN | Dev only |

---

## Recommended Fix Priority

1. **Immediate (Block deployment):**
   - C1: API key nil crash
   - C3: Transaction wrapper for poll
   - C5: Error sanitization
   - H3: File size limits

2. **Before production:**
   - C2: Queue/DB divergence
   - H1: Supervision strategy
   - H2: Worker re-registration
   - M2: Pagination
   - L5: Health endpoint

3. **Post-launch:**
   - L1: Rate limiting
   - L3: Telemetry
   - Testing suite
   - S3 integration

---

## Conclusion

The Elixir migration addresses the fundamental architectural issues of the TypeScript version (race conditions, memory exhaustion) but introduces new risks through incomplete implementation. The transaction boundary error (C3) actually reintroduces the race condition it claims to fix.

Primary concerns:
1. **Security**: Error leakage, missing input validation
2. **Data integrity**: Queue divergence, counter races
3. **Availability**: No rate limiting, unbounded queries, crash on missing config
4. **Observability**: No health checks, minimal telemetry

The foundation is solid. With the critical fixes applied, this will be a significant improvement over the TypeScript version.
