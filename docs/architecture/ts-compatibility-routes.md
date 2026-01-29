# TypeScript Controller Path Compatibility

This document describes the route aliases implemented to maintain backward compatibility with the TypeScript controller API while preserving Phoenix REST conventions.

## Problem

The Elixir controller migration initially broke path compatibility with the existing TypeScript controller. Workers and CLI clients expected specific paths that no longer existed:

- `POST /api/builds/submit` (TS) vs `POST /api/builds` (Phoenix)
- `GET /api/builds/:id/status` (TS) vs `GET /api/builds/:id` (Phoenix)
- `GET /api/builds/:id/download` (TS) vs `GET /api/builds/:id/download/:type` (Phoenix)
- `POST /api/workers/upload` (TS) vs `POST /api/workers/result` (Phoenix)

## Solution

Implemented route aliases so **both** path styles work simultaneously:

### 1. Build Submission

**Both paths work:**
- `POST /api/builds/submit` → `BuildController.create` (TS compatibility)
- `POST /api/builds` → `BuildController.create` (Phoenix convention)

### 2. Build Status

**TS-specific endpoint:**
- `GET /api/builds/:id/status` → `BuildController.status` (TS format with numeric timestamps)

**Phoenix endpoint:**
- `GET /api/builds/:id` → `BuildController.show` (full details with ISO8601 timestamps)

**Key difference:** The `/status` endpoint returns numeric timestamps (milliseconds since epoch) matching TS controller format:

```json
{
  "id": "abc123",
  "status": "building",
  "platform": "ios",
  "worker_id": "worker-1",
  "submitted_at": 1706400000000,  // numeric
  "started_at": 1706400120000,    // numeric
  "completed_at": null,
  "error_message": null
}
```

### 3. Build Download

**Both paths work:**
- `GET /api/builds/:id/download` → `BuildController.download_default` (defaults to "result" type, TS compatibility)
- `GET /api/builds/:id/download/:type` → `BuildController.download` (explicit type, Phoenix convention)

Supported types:
- `result` - The final build artifact (IPA/APK)
- `source` - The original source zip

### 4. Worker Upload

**Both paths work:**
- `POST /api/workers/upload` → `WorkerController.upload_result` (TS compatibility)
- `POST /api/workers/result` → `WorkerController.upload_result` (Phoenix convention)

## Implementation Details

### Router Configuration

`lib/expo_controller_web/router.ex`:

```elixir
scope "/api", ExpoControllerWeb do
  pipe_through :api

  # Build endpoints
  post "/builds/submit", BuildController, :create  # TS alias

  resources "/builds", BuildController, only: [:index, :show, :create] do
    get "/status", BuildController, :status                # TS endpoint
    get "/download", BuildController, :download_default    # TS alias
    get "/download/:type", BuildController, :download      # Phoenix explicit
  end

  # Worker endpoints
  post "/workers/upload", WorkerController, :upload_result  # TS alias
  post "/workers/result", WorkerController, :upload_result  # Phoenix
end
```

### Controller Actions

**`BuildController.status/2`** - New action for TS compatibility:
- Returns subset of build data
- Uses numeric timestamps (milliseconds)
- Same auth as `show` (build token or API key)

**`BuildController.download_default/2`** - New action for TS compatibility:
- Delegates to `download/2` with `type: "result"`
- Same auth and behavior as `download/2`

**Helper function** `datetime_to_timestamp/1`:
- Converts `DateTime` to Unix milliseconds
- Handles `nil` values
- Used only by `status` action

### Authentication

All new endpoints follow existing auth patterns:

- `status`: Requires build token or API key (via `BuildAuth` plug)
- `download_default`: Requires build token or API key (via `BuildAuth` plug)

Updated plug configuration includes new actions:
```elixir
plug ExpoControllerWeb.Plugs.Auth, :require_api_key
  when action not in [:logs, :download, :download_default, :retry, :status]

plug ExpoControllerWeb.Plugs.BuildAuth, :require_build_or_admin_access
  when action in [:logs, :download, :download_default, :retry, :status]
```

## Testing

Comprehensive tests in `test/expo_controller_web/controllers/ts_compatibility_test.exs`:

1. **Route registration** - Verifies all path aliases are registered
2. **Response formats** - Validates TS format (numeric timestamps) vs Phoenix format (ISO8601)
3. **Both paths work** - Tests both TS and Phoenix paths for same functionality
4. **Error handling** - Ensures error responses match expected formats

Run tests:
```bash
cd packages/controller_elixir
MIX_ENV=test mix test test/expo_controller_web/controllers/ts_compatibility_test.exs
```

## Migration Strategy

### For CLI/Workers

**No changes required.** Continue using existing TS paths:
- `POST /api/builds/submit`
- `GET /api/builds/:id/status`
- `GET /api/builds/:id/download`
- `POST /api/workers/upload`

### For New Integrations

Use Phoenix conventions:
- `POST /api/builds`
- `GET /api/builds/:id`
- `GET /api/builds/:id/download/:type`
- `POST /api/workers/result`

### Deprecation Plan

1. **Phase 1 (Current):** Both paths work
2. **Phase 2 (Future):** Update CLI/workers to use Phoenix paths
3. **Phase 3 (Later):** Remove TS aliases after migration complete

## Verification

To verify both paths work:

```bash
# TS path
curl -X POST https://controller/api/builds/submit \
  -H "X-API-Key: $KEY" \
  -F "platform=ios" \
  -F "source=@source.zip"

# Phoenix path
curl -X POST https://controller/api/builds \
  -H "X-API-Key: $KEY" \
  -F "platform=ios" \
  -F "source=@source.zip"

# Both should return same response format
```

## Related Files

- `lib/expo_controller_web/router.ex` - Route definitions
- `lib/expo_controller_web/controllers/build_controller.ex` - Controller actions
- `lib/expo_controller_web/controllers/worker_controller.ex` - Worker actions
- `test/expo_controller_web/controllers/ts_compatibility_test.exs` - Compatibility tests
