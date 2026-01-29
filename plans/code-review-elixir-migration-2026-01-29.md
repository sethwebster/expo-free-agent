# Code Review: Elixir Controller Migration

**Date**: 2026-01-29
**Reviewer**: Code Review Agent
**Scope**: Worker registration, build pickup, API contract parity between Bun/Express and Elixir/Phoenix controllers

---

## Executive Summary

The Elixir migration has **critical API contract violations** that break worker registration and build pickup. Workers cannot authenticate, poll for jobs, or download build sources due to response format mismatches, authentication header inconsistencies, and missing response fields.

**Root Cause**: The Swift worker expects specific response formats and fields that the Elixir controller does not provide, and the authentication model changed incompatibly.

---

## 🔴 Critical Issues

### 1. **BLOCKER: Poll Response Missing `baseImageId` Field**

**Location**: `/Users/sethwebster/Development/expo/expo-free-agent/packages/controller_elixir/lib/expo_controller_web/controllers/worker_controller.ex` (lines 131-149)

**Problem**: The Swift worker expects `baseImageId` in the poll response, but Elixir controller doesn't include it.

**Swift Expectation** (from `WorkerService.swift` line 318):
```swift
let templateImage = job.baseImageId ?? "ghcr.io/sethwebster/expo-free-agent-base:0.1.23"
```

**TypeScript Response** (from `workers/index.ts` lines 139-147):
```typescript
return reply.send({
  job: {
    id: build.id,
    platform: build.platform,
    source_url: `/api/builds/${build.id}/source`,
    certs_url: build.certs_path ? `/api/builds/${build.id}/certs` : null,
    baseImageId: config.baseImageId,  // <-- MISSING IN ELIXIR
  },
});
```

**Elixir Response** (lines 132-141):
```elixir
json(conn, %{
  job: %{
    id: build.id,
    platform: build.platform,
    source_url: "/api/builds/#{build.id}/source",
    certs_url: if(build.certs_path, do: "/api/builds/#{build.id}/certs", else: nil),
    submitted_at: DateTime.to_iso8601(build.submitted_at)
    # MISSING: baseImageId
  },
  access_token: updated_worker.access_token
})
```

**Impact**: Workers will use hardcoded fallback image, potentially causing build failures if image version is stale.

**Fix**:
```elixir
# Add to config/config.exs:
config :expo_controller, :base_image_id, "ghcr.io/sethwebster/expo-free-agent-base:0.1.23"

# In poll response:
base_image_id = Application.get_env(:expo_controller, :base_image_id)
json(conn, %{
  job: %{
    ...
    baseImageId: base_image_id
  },
  ...
})
```

---

### 2. **BLOCKER: Registration Response Missing Required Fields**

**Location**: `/Users/sethwebster/Development/expo/expo-free-agent/packages/controller_elixir/lib/expo_controller_web/controllers/worker_controller.ex` (lines 54-61)

**Problem**: TypeScript controller returns `baseImageId` in registration response, Elixir doesn't.

**TypeScript Response** (`workers/index.ts` lines 62-66):
```typescript
return reply.send({
  id: workerId,
  status: 'registered',
  baseImageId: config.baseImageId,  // <-- MISSING IN ELIXIR
});
```

**Elixir Response** (lines 54-61):
```elixir
json(conn, %{
  id: worker.id,
  access_token: worker.access_token,  # NEW - not in TS
  status: "registered",
  message: "Worker registered successfully"  # NEW - not in TS
})
```

**Impact**: While Swift worker doesn't use `baseImageId` from registration response currently, the inconsistency breaks API contract parity.

---

### 3. **BLOCKER: Authentication Model Mismatch**

**Location**: `/Users/sethwebster/Development/expo/expo-free-agent/packages/controller_elixir/lib/expo_controller_web/plugs/auth.ex` and `/Users/sethwebster/Development/expo/expo-free-agent/packages/controller_elixir/lib/expo_controller_web/controllers/worker_controller.ex`

**Problem**: The Elixir controller uses a **token-based auth** model (`X-Worker-Token` header) that the Swift worker supports, but:

1. The auth plug on `/api/workers/register` requires `require_api_key` (correct), but the registration returns `access_token` which is a **new concept** not in the TS controller.

2. The TypeScript controller uses `X-Worker-Id` for worker authentication on source/certs downloads. The Elixir controller uses `X-Worker-Token` for poll but the build controller's `download_source` has **NO authentication**:

**Elixir `download_source`** (line 417-430):
```elixir
@doc """
GET /api/builds/:id/source
Download build source (for workers).
No authentication required - workers get URL from poll response.
"""
def download_source(conn, %{"id" => build_id}) do
  # NO AUTH CHECK!
```

**TypeScript `download_source`** (lines 363-383):
```typescript
fastify.get<{ Params: BuildParams }>(
  '/:id/source',
  {
    preHandler: requireWorkerAccess(db),  // REQUIRES X-Worker-Id!
  },
  ...
)
```

**Swift Worker Expectation** (lines 378-384):
```swift
request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")
if let workerID = configuration.workerID {
    request.setValue(workerID, forHTTPHeaderField: "X-Worker-Id")
}
```

**Impact**:
- Security regression - source downloads are unauthenticated in Elixir
- Workers will include `X-Worker-Id` header that Elixir ignores

---

### 4. **BLOCKER: Token Rotation on Every Heartbeat Causes Poll Failures**

**Location**: `/Users/sethwebster/Development/expo/expo-free-agent/packages/controller_elixir/lib/expo_controller/workers/worker.ex` (lines 68-78) and `worker_controller.ex` (line 128)

**Problem**: The Elixir controller rotates the access token on **every heartbeat** (poll), with a short 90-second TTL. Combined with:
1. Network latency
2. The Swift worker's 30-second poll interval
3. Token not being persisted atomically before next poll

This creates a race condition where:
- Worker polls, gets token T1
- Controller rotates to T2
- Worker's next poll uses T1 (stale)
- Controller rejects as unauthorized

**Worker Token Lifecycle**:
```elixir
# worker.ex
@token_ttl_seconds 90  # Only 90 seconds!

def heartbeat_changeset(worker) do
  now = DateTime.utc_now() |> DateTime.truncate(:second)
  expires_at = DateTime.add(now, @token_ttl_seconds, :second)
  change(worker,
    last_seen_at: now,
    access_token: generate_token(),  # NEW TOKEN ON EVERY HEARTBEAT
    access_token_expires_at: expires_at
  )
end
```

**TypeScript Controller**: Does NOT rotate tokens. Worker ID is stable.

**Impact**: Workers will get 401 Unauthorized on polls after initial registration works.

**Fix**: Either:
1. Extend token TTL significantly (e.g., 24 hours)
2. Don't rotate token on heartbeat, only on explicit token refresh
3. Return to the simpler TS model of just using worker_id

---

### 5. **CRITICAL: Unregister Endpoint Requires Wrong Auth**

**Location**: `/Users/sethwebster/Development/expo/expo-free-agent/packages/controller_elixir/lib/expo_controller_web/controllers/worker_controller.ex` (line 8)

**Problem**:
```elixir
plug ExpoControllerWeb.Plugs.Auth, :require_worker_token when action in [:unregister]
```

But the Swift worker sends BOTH `X-API-Key` AND `X-Worker-Token`:
```swift
request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")
request.setValue(accessToken, forHTTPHeaderField: "X-Worker-Token")
```

The auth plug only checks for `X-Worker-Token`, but doesn't require `X-API-Key`. This is fine, but the TS controller also required API key for all `/api/*` routes.

**Impact**: Inconsistent auth model, but functionally works.

---

### 6. **CRITICAL: Upload/Result Endpoint Has No Worker Validation**

**Location**: `/Users/sethwebster/Development/expo/expo-free-agent/packages/controller_elixir/lib/expo_controller_web/controllers/worker_controller.ex` (lines 161-202)

**Problem**: The `upload_result` function accepts `build_id` in params but doesn't validate that the calling worker is the one assigned to the build.

**TypeScript Controller** (lines 197-209):
```typescript
const worker = db.getWorker(worker_id);
if (!worker) {
  return reply.status(404).send({ error: 'Worker not found' });
}
```

**Elixir Controller** (lines 161-202):
```elixir
def upload_result(conn, %{"build_id" => build_id} = params) do
  # NO VALIDATION that worker_id matches build.worker_id!
  success = params["success"] || "true"
  ...
```

**Impact**: Any caller can mark any build as completed/failed.

---

## 🟡 Architecture Concerns

### 7. **Token-Based Auth Adds Unnecessary Complexity**

The original TypeScript controller used a simple model:
- Workers register, get an ID
- Workers include `worker_id` in requests
- Controller validates worker exists

The Elixir controller adds:
- Access tokens with expiration
- Token rotation on every heartbeat
- Two separate auth mechanisms (`X-Worker-Token` vs `X-Worker-Id`)

This complexity creates more failure modes without meaningful security benefit in a trusted-network controller.

---

### 8. **Router Has Duplicate/Conflicting Route Definitions**

**Location**: `/Users/sethwebster/Development/expo/expo-free-agent/packages/controller_elixir/lib/expo_controller_web/router.ex` (lines 47-83)

```elixir
scope "/api", ExpoControllerWeb do
  pipe_through :api

  # Worker endpoints - these WORK
  post "/workers/register", WorkerController, :register
  ...

  # Build endpoints with resources macro
  resources "/builds", BuildController, only: [:index, :show, :create] do
    get "/status", BuildController, :status
    ...
  end

  # Worker-authenticated build endpoints - SEPARATE SCOPE
  scope "/builds/:id" do
    post "/logs", BuildController, :stream_logs
    ...
  end
end
```

The nested routes inside `resources "/builds"` will generate paths like:
- `GET /api/builds/:build_id/status` (param is `:build_id`)

But the separate `scope "/builds/:id"` generates:
- `POST /api/builds/:id/logs` (param is `:id`)

**Impact**: Inconsistent parameter naming causes confusion and potential routing bugs.

---

### 9. **Missing `assigned_at` Timestamp in Build Assignment**

**Location**: `/Users/sethwebster/Development/expo/expo-free-agent/packages/controller_elixir/lib/expo_controller/builds.ex` (line 102-105)

```elixir
defp update_build_assignment(build, worker_id) do
  build
  |> Build.assign_changeset(worker_id)  # Only sets status and worker_id
  |> Repo.update()
end
```

**TypeScript Controller** (line 124):
```typescript
const assigned = db.assignBuildToWorker(build.id, worker_id, timestamp);
// This sets assigned_at = timestamp
```

**Impact**: No `assigned_at` timestamp means can't track time-to-start metrics.

---

## 🟢 DRY Opportunities

### 10. **Duplicate Error Response Formatting**

Multiple controllers have similar error response patterns:
```elixir
conn
|> put_status(:not_found)
|> json(%{error: "Build not found"})
```

Should consolidate into a helper:
```elixir
defp error_response(conn, status, message) do
  conn
  |> put_status(status)
  |> json(%{error: message})
end
```

---

### 11. **Duplicate Worker Token Validation Logic**

The poll endpoint (lines 104-115) manually handles token auth instead of using the auth plug:

```elixir
def poll(conn, params) do
  token = get_req_header(conn, "x-worker-token") |> List.first()
  worker_id = params["worker_id"]

  worker = cond do
    token -> Workers.get_worker_by_token(token)
    worker_id -> Workers.get_worker(worker_id)
    true -> nil
  end
```

This duplicates logic that could be in a plug with optional auth.

---

## 🔵 Maintenance Improvements

### 12. **IO.puts Debug Statements Throughout**

**Locations**: Multiple files

Examples:
- `worker_controller.ex` line 23: `IO.puts("Re-registering existing worker: #{existing_id}")`
- `worker_controller.ex` line 35: `IO.puts("Worker ID provided but not found...")`
- `build_controller.ex` line 418: `IO.puts("Worker downloading source for build #{build_id}")`

**Impact**: Production noise, no log levels, no structured logging.

**Fix**: Use `Logger.info/debug/warn/error` with metadata:
```elixir
require Logger
Logger.info("Worker registration", worker_id: existing_id, action: :re_register)
```

---

### 13. **Missing Tests for Critical Paths**

No test files visible for:
- Worker registration flow
- Poll -> assign -> upload lifecycle
- Token rotation
- Auth plug behavior

---

### 14. **Config Values Hardcoded**

**Location**: `/Users/sethwebster/Development/expo/expo-free-agent/packages/controller_elixir/lib/expo_controller/workers/worker.ex` (line 29)

```elixir
@token_ttl_seconds 90  # Hardcoded
```

Should be configurable:
```elixir
@token_ttl_seconds Application.compile_env(:expo_controller, :worker_token_ttl, 90)
```

---

## White Nitpicks

### 15. **Inconsistent Status Codes**

- Elixir returns `:forbidden` (403) for invalid API key
- TypeScript returns 401 for missing key, 403 for invalid

---

### 16. **Inconsistent JSON Key Casing**

Elixir responses use snake_case (`access_token`), TypeScript uses camelCase in some places (`baseImageId`). Pick one.

---

## Checkmark Strengths

### 1. **Proper Transaction Usage**

The `try_assign_build` function correctly uses database transactions with `FOR UPDATE SKIP LOCKED`:
```elixir
def next_pending_for_update do
  from(b in Build,
    where: b.status == :pending,
    order_by: [asc: b.submitted_at],
    limit: 1,
    lock: "FOR UPDATE SKIP LOCKED"
  )
  |> Repo.one()
end
```

This prevents race conditions in build assignment.

---

### 2. **Constant-Time API Key Comparison**

```elixir
Plug.Crypto.secure_compare(provided_key, api_key)
```

Prevents timing attacks on API key validation.

---

### 3. **Proper Token Generation**

```elixir
def generate_token do
  Nanoid.generate(32)
end

def generate_access_token do
  :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
end
```

Cryptographically secure token generation.

---

## Summary of Required Fixes (Priority Order)

1. **Add `baseImageId` to poll response** - Workers can't pull correct VM image
2. **Fix authentication model** - Either commit to token-based auth fully or revert to worker_id model
3. **Extend token TTL or stop rotating** - Current 90s TTL + rotation on every poll = guaranteed auth failures
4. **Add worker validation to upload_result** - Security hole allowing any caller to modify builds
5. **Add auth to download_source** - Security regression from TS controller
6. **Add `assigned_at` timestamp** - Metrics regression
7. **Fix route parameter naming** - Inconsistent `:build_id` vs `:id`
8. **Replace IO.puts with Logger** - Production readiness

---

## Questions for User

1. Token rotation: Intentional security enhancement or accidental complexity?
2. Should I fix auth to match TS (worker_id) or commit to new token model?
3. Is the source download auth removal intentional (trusted network assumption)?
