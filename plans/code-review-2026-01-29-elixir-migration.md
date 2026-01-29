# Code Review: Elixir Controller Migration + Token Rotation

**Date**: 2026-01-29
**Reviewer**: Claude Opus 4.5
**Scope**: Worker token rotation, graceful shutdown, Elixir controller changes

---

## Summary

This is an in-progress migration from the Bun/TypeScript controller to an Elixir/Phoenix controller, with a major new feature: short-lived rotating access tokens for worker authentication. The work is **functionally complete but not production-ready** due to several issues.

---

## What's Been Done

1. **Token-based worker authentication**: Workers receive 90-second access tokens that rotate on each poll. This is a significant security improvement over static worker IDs.

2. **Graceful worker shutdown**: Workers now call `POST /api/workers/unregister` on shutdown, which reassigns any active builds back to pending status.

3. **Database migrations**: Two migrations add `access_token` and `access_token_expires_at` columns to the workers table.

4. **Swift worker updates**: `WorkerService.swift` and `WorkerConfiguration.swift` updated to handle token storage, rotation, and automatic re-registration on 401/404.

5. **Comprehensive documentation**: `docs/architecture/build-pickup-flow.md` is excellent - detailed sequence diagrams, code examples, and debugging guides.

---

## RED ISSUES: Critical (Must Fix Before Commit)

### 1. FileStorage API Mismatch - Breaks Builds.retry_build

**Location**: `/packages/controller_elixir/lib/expo_controller/builds.ex` lines 385-424

**Problem**: The code calls `FileStorage.exists?/1`, `FileStorage.copy_source/2`, and `FileStorage.copy_certs/2` - none of which exist. The actual API is `FileStorage.file_exists?/1` and there are no copy functions.

**Impact**: `retry_build/1` function will crash at runtime. This is a compile warning visible in `mix compile` output.

**Solution**: Either:
- Remove the `retry_build` functionality if not needed
- Implement the missing `copy_source/2` and `copy_certs/2` functions in FileStorage
- Fix the function call to use `file_exists?/1`

```elixir
# In file_storage.ex, add:
def copy_source(source_path, new_build_id) do
  new_path = source_path(new_build_id)
  copy_file_internal(source_path, new_path)
end

def copy_certs(certs_path, new_build_id) do
  new_path = certs_path(new_build_id)
  copy_file_internal(certs_path, new_path)
end

defp copy_file_internal(source, dest) do
  full_source = Path.join(@storage_root, source)
  full_dest = Path.join(@storage_root, dest)

  with :ok <- ensure_directory(full_dest),
       {:ok, _} <- File.copy(full_source, full_dest) do
    {:ok, dest}
  else
    {:error, reason} -> {:error, {:copy_failed, reason}}
  end
end
```

### 2. Unused/Broken Helper Functions

**Location**: `/packages/controller_elixir/lib/expo_controller_web/controllers/worker_controller.ex` lines 269-275

**Problem**: `build_download_url/3` calls `Routes.build_url/4` which doesn't exist (Phoenix 1.8+ uses verified routes). These are unused but indicate incomplete refactoring.

**Solution**: Delete these dead functions:
```elixir
# DELETE these lines (269-275):
defp build_download_url(conn, build_id, type) do
  Routes.build_url(conn, :download, build_id, type)
end

defp build_certs_url(build) do
  if build.certs_path, do: "/api/builds/#{build.id}/certs", else: nil
end
```

### 3. Poll Endpoint Missing API Key Validation

**Location**: `/packages/controller_elixir/lib/expo_controller_web/controllers/worker_controller.ex` line 7-9

**Problem**: The poll endpoint has no auth plug applied. While it does require a worker token, it bypasses the API key check entirely (comment says "backwards compat" but that's a security hole).

**Current code**:
```elixir
plug ExpoControllerWeb.Plugs.Auth, :require_api_key when action in [:register, :stats]
plug ExpoControllerWeb.Plugs.Auth, :require_worker_token when action in [:unregister]
# Poll endpoint uses optional token auth for backwards compat
```

**Solution**: Add API key requirement to poll:
```elixir
plug ExpoControllerWeb.Plugs.Auth, :require_api_key when action in [:register, :stats, :poll]
plug ExpoControllerWeb.Plugs.Auth, :require_worker_token when action in [:unregister]
```

Or create a combined plug that checks both API key + optional worker token.

---

## YELLOW ISSUES: Architecture Concerns

### 4. Token Rotation on Every Poll Creates Disk I/O Storm

**Location**:
- `/packages/controller_elixir/lib/expo_controller/workers/worker.ex` lines 68-78
- `/free-agent/Sources/WorkerCore/WorkerService.swift` lines 229-234

**Problem**: Every 30-second poll rotates the token and the Swift worker saves to disk (`try? configuration.save()`). With 10 workers polling every 30 seconds, that's 20 disk writes per minute. This is unnecessary overhead.

**Better approach**: Only rotate token on:
- Registration
- Successful build assignment
- Approaching expiration (last 30 seconds of TTL)

```elixir
def heartbeat_changeset(worker) do
  now = DateTime.utc_now() |> DateTime.truncate(:second)

  # Only rotate if token expires within 30 seconds
  should_rotate = DateTime.diff(worker.access_token_expires_at, now) < 30

  if should_rotate do
    expires_at = DateTime.add(now, @token_ttl_seconds, :second)
    change(worker,
      last_seen_at: now,
      access_token: generate_token(),
      access_token_expires_at: expires_at
    )
  else
    change(worker, last_seen_at: now)
  end
end
```

### 5. No Index on access_token_expires_at

**Location**: `/packages/controller_elixir/priv/repo/migrations/20260129031721_add_token_expiration_to_workers.exs`

**Problem**: `get_worker_by_token/1` queries by `access_token` AND `access_token_expires_at > now`. The `access_token` has a unique index (good), but `access_token_expires_at` does not. This may cause slow queries as worker count grows.

**Solution**: Add compound index or just rely on the unique token index (probably fine for < 100 workers).

### 6. Race Condition Window in Re-registration

**Location**: `/free-agent/Sources/WorkerCore/WorkerService.swift` lines 244-267

**Problem**: On 401/404, the worker clears credentials, saves, then re-registers. If the app crashes between save and re-register completion, the worker loses its ID and creates a duplicate entry.

**Current code**:
```swift
configuration.workerID = nil
configuration.accessToken = nil
try? configuration.save()  // <-- Crash here = orphaned worker in DB
try await registerWorker()
```

**Better approach**: Don't clear workerID on re-registration - the controller already handles idempotent re-registration with existing ID:
```swift
configuration.accessToken = nil
try? configuration.save()
try await registerWorker()  // Controller will use existing ID if sent
```

---

## GREEN ISSUES: DRY Opportunities

### 7. Duplicate Multipart Form Building

**Location**: `/free-agent/Sources/WorkerCore/WorkerService.swift` lines 417-473 and 475-520

**Problem**: `uploadBuildResult` and `reportJobFailure` have nearly identical multipart form construction. Only difference is success flag and whether to include file.

**Solution**: Extract a shared helper:
```swift
private func buildMultipartRequest(
    for jobID: String,
    success: Bool,
    errorMessage: String? = nil,
    artifactPath: URL? = nil
) -> URLRequest {
    // Shared implementation
}
```

### 8. Duplicate Auth Validation Pattern

**Location**: `/packages/controller_elixir/lib/expo_controller_web/plugs/auth.ex` lines 125-147

**Problem**: `unauthorized/2`, `forbidden/2`, and `not_found/2` are nearly identical. Could use a generic error helper.

**Minor**: Not blocking, but consider:
```elixir
defp halt_with_error(conn, status, message) do
  conn
  |> put_status(status)
  |> put_view(json: ExpoControllerWeb.ErrorJSON)
  |> render(String.to_atom(to_string(Plug.Conn.Status.code(status))), message: message)
  |> halt()
end
```

---

## BLUE ISSUES: Maintenance Improvements

### 9. @doc on Private Functions

**Location**: `/packages/controller_elixir/lib/expo_controller_web/plugs/auth.ex` lines 26, 45, 70

**Problem**: Compile warnings about `@doc` on private functions. These are noise.

**Solution**: Remove `@doc` from private functions or add `@doc false`.

### 10. Hardcoded API Key in dev.exs

**Location**: `/packages/controller_elixir/config/dev.exs` line 70

**Problem**: `config :expo_controller, :api_key, "test-api-key-demo-1234567890"` is committed. While it says "demo", this pattern encourages copy-paste to production configs.

**Solution**: Use environment variable with fallback:
```elixir
config :expo_controller, :api_key, System.get_env("API_KEY") || "dev-only-key-#{:rand.uniform(1000000)}"
```

### 11. Missing Error Handling for heartbeat_worker

**Location**: `/packages/controller_elixir/lib/expo_controller_web/controllers/worker_controller.ex` line 128

**Problem**: `{:ok, updated_worker} = Workers.heartbeat_worker(worker)` will crash if heartbeat fails (DB error, constraint violation). Need pattern match.

**Solution**:
```elixir
case Workers.heartbeat_worker(worker) do
  {:ok, updated_worker} ->
    # Continue with poll logic
  {:error, reason} ->
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "Heartbeat failed", reason: inspect(reason)})
end
```

### 12. IO.puts Used for Logging

**Location**: Throughout `worker_controller.ex`

**Problem**: Production code should use `Logger` not `IO.puts`. IO.puts is synchronous and doesn't respect log levels.

**Solution**: Replace all `IO.puts` with `Logger.info`:
```elixir
require Logger

# Instead of:
IO.puts("Re-registering existing worker: #{existing_id}")

# Use:
Logger.info("Re-registering existing worker: #{existing_id}")
```

---

## WHITE ISSUES: Nitpicks

### 13. Inconsistent snake_case vs camelCase

- Controller response uses `access_token` (snake_case)
- Swift model uses `access_token` but also `baseImageId` (camelCase)
- Some fields are `source_url`, others might be `sourceUrl`

Recommend standardizing on snake_case for all API responses.

### 14. Token Length Not Validated

`Nanoid.generate(32)` produces 32-character tokens, but there's no validation that the token column can hold it. Should add `validate_length(:access_token, is: 32)` or ensure column is sized appropriately.

---

## STRENGTHS

1. **Token rotation is well-designed**: 90-second TTL with 30-second poll interval provides good security/UX tradeoff.

2. **Atomic build assignment**: `SELECT FOR UPDATE SKIP LOCKED` is the correct pattern for distributed work queues.

3. **Graceful shutdown with build reassignment**: Calling `reassign_worker_builds` before marking offline is the right order of operations.

4. **Comprehensive documentation**: The `build-pickup-flow.md` is excellent - would be helpful for onboarding.

5. **Automatic re-registration**: Swift worker handling 401/404 by re-registering is resilient.

6. **Secure comparison for API keys**: Using `Plug.Crypto.secure_compare` prevents timing attacks.

---

## Recommended Next Steps (Priority Order)

1. **Fix FileStorage API mismatch** (RED - compile warnings, runtime crash)
2. **Delete unused helper functions** (RED - compile warnings)
3. **Add API key check to poll endpoint** (RED - security hole)
4. **Replace IO.puts with Logger** (BLUE - production readiness)
5. **Add error handling for heartbeat_worker** (BLUE - crash prevention)
6. **Remove dev API key hardcoding** (BLUE - security hygiene)
7. **Consider conditional token rotation** (YELLOW - performance)
8. **Fix re-registration race condition** (YELLOW - reliability)

---

## Unresolved Questions

1. Is backward compat for `worker_id` query param actually needed? If not, remove it and simplify poll endpoint.
2. What's the plan for migrating from Bun controller to Elixir? Parallel running? Flag day?
3. Is `retry_build` functionality actually used? If not, remove dead code.
4. Should we add metrics/tracing before production deploy?
