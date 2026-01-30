# API Compatibility Guide

**Goal**: 100% wire-protocol compatibility between TypeScript and Elixir controllers.
**Status**: Core paths implemented, legacy aliases added.

---

## Complete Endpoint Mapping

### Build Endpoints

| TypeScript Path | Elixir Path | Method | Auth | Status | Notes |
|-----------------|-------------|--------|------|--------|-------|
| `/api/builds/submit` | `/api/builds/submit` | POST | API Key | ✅ | Alias to `/api/builds` |
| `/api/builds/` | `/api/builds` | GET | API Key | ✅ | List builds |
| `/api/builds/active` | `/api/builds?status=building` | GET | API Key | ✅ | Query param filter |
| `/api/builds/:id/status` | `/api/builds/:id/status` | GET | API Key OR Build Token | ✅ | Dedicated endpoint |
| `/api/builds/:id` | `/api/builds/:id` | GET | API Key | ✅ | Full build details |
| `/api/builds/:id/logs` | `/api/builds/:id/logs` | GET | API Key OR Build Token | ✅ | Build logs |
| `/api/builds/:id/logs` | `/api/builds/:id/logs` | POST | Worker ID | ⏳ | Stream logs from worker |
| `/api/builds/:id/download` | `/api/builds/:id/download` | GET | API Key OR Build Token | ✅ | Downloads result by default |
| `/api/builds/:id/download/:type` | `/api/builds/:id/download/:type` | GET | API Key OR Build Token | ✅ | Explicit type (source/result) |
| `/api/builds/:id/source` | `/api/builds/:id/download/source` | GET | Worker ID | ⏳ | Worker downloads source |
| `/api/builds/:id/certs` | `/api/builds/:id/download/certs` | GET | Worker ID | ⏳ | Worker downloads certs |
| `/api/builds/:id/certs-secure` | `/api/builds/:id/certs-secure` | GET | Worker ID | ⏳ | Certs as JSON (no file) |
| `/api/builds/:id/heartbeat` | `/api/builds/:id/heartbeat` | POST | Worker ID | ⏳ | Worker heartbeat |
| `/api/builds/:id/telemetry` | `/api/builds/:id/telemetry` | POST | Worker ID | ⏳ | VM telemetry |
| `/api/builds/:id/cancel` | `/api/builds/:id/cancel` | POST | API Key | ✅ | Cancel build |
| `/api/builds/:id/retry` | `/api/builds/:id/retry` | POST | API Key | ⏳ | Retry failed build |

### Worker Endpoints

| TypeScript Path | Elixir Path | Method | Auth | Status | Notes |
|-----------------|-------------|--------|------|--------|-------|
| `/api/workers/register` | `/api/workers/register` | POST | None | ✅ | Register new worker |
| `/api/workers/poll` | `/api/workers/poll` | GET | Worker ID | ✅ | Get next build |
| `/api/workers/upload` | `/api/workers/upload` | POST | Worker ID | ✅ | Alias to `/api/workers/result` |
| `/api/workers/result` | `/api/workers/result` | POST | Worker ID | ✅ | Upload build result |
| `/api/workers/fail` | `/api/workers/fail` | POST | Worker ID | ✅ | Report build failure |
| `/api/workers/heartbeat` | `/api/workers/heartbeat` | POST | Worker ID | ✅ | Worker heartbeat |
| `/api/workers/:id/stats` | `/api/workers/:id/stats` | GET | API Key | ⏳ | Worker statistics |

### System Endpoints

| TypeScript Path | Elixir Path | Method | Auth | Status | Notes |
|-----------------|-------------|--------|------|--------|-------|
| `/api/stats` | `/api/stats` | GET | None | ✅ | Public stats |
| `/public/stats` | `/public/stats` | GET | None | ✅ | Public stats (primary) |
| `/health` | `/health` | GET | None | ⏳ | Health check |
| `/` | `/` | GET | None | ✅ | LiveView dashboard |

### Diagnostics Endpoints

| TypeScript Path | Elixir Path | Method | Auth | Status | Notes |
|-----------------|-------------|--------|------|--------|-------|
| `/api/diagnostics/report` | N/A | POST | Worker ID | ⏳ | Save diagnostic report |
| `/api/diagnostics/:worker_id` | N/A | GET | API Key | ⏳ | Get diagnostics |
| `/api/diagnostics/:worker_id/latest` | N/A | GET | API Key | ⏳ | Latest diagnostic |

**Legend**:
- ✅ Implemented
- ⏳ Planned
- N/A Not yet started

---

## Request/Response Formats

### POST /api/builds/submit

**Request** (multipart/form-data):
```
Content-Type: multipart/form-data; boundary=----WebKitFormBoundary

------WebKitFormBoundary
Content-Disposition: form-data; name="platform"

ios
------WebKitFormBoundary
Content-Disposition: form-data; name="source"; filename="app.zip"
Content-Type: application/zip

<binary data>
------WebKitFormBoundary
Content-Disposition: form-data; name="certs"; filename="certs.zip"
Content-Type: application/zip

<binary data>
------WebKitFormBoundary--
```

**Response** (TypeScript):
```json
{
  "id": "abc123",
  "status": "pending",
  "submitted_at": 1706400000,
  "access_token": "xyz789"
}
```

**Response** (Elixir - CURRENT):
```json
{
  "id": "abc123",
  "status": "pending",
  "platform": "ios",
  "submitted_at": "2024-01-28T12:00:00Z"
}
```

**⚠️ Breaking Change**: Missing `access_token` field in Elixir response.
**Fix Required**: Add build token generation on submission.

---

### GET /api/builds/:id/status

**Response** (TypeScript):
```json
{
  "id": "abc123",
  "status": "building",
  "platform": "ios",
  "submitted_at": 1706400000,
  "assigned_at": 1706400030,
  "worker_id": "worker-1"
}
```

**Response** (Elixir):
```json
{
  "id": "abc123",
  "status": "building",
  "platform": "ios",
  "submitted_at": "2024-01-28T12:00:00Z",
  "assigned_at": "2024-01-28T12:00:30Z",
  "worker_id": "worker-1"
}
```

**⚠️ Difference**: Timestamp format (epoch seconds vs ISO8601).
**Decision Required**: Keep ISO8601 or add epoch support?

---

### GET /api/workers/poll

**Request Headers**:
```
X-Worker-Id: worker-1
```

**Response** (no build available - TypeScript):
```json
{
  "build": null
}
```

**Response** (no build available - Elixir):
```json
{
  "build": null
}
```

**Response** (build available):
```json
{
  "build": {
    "id": "abc123",
    "platform": "ios",
    "source_path": "/storage/builds/abc123/source.zip",
    "certs_path": "/storage/builds/abc123/certs.zip"
  }
}
```

**✅ Compatible**: No changes required.

---

### POST /api/workers/result

**Request** (multipart/form-data):
```
Content-Type: multipart/form-data; boundary=----WebKitFormBoundary

------WebKitFormBoundary
Content-Disposition: form-data; name="build_id"

abc123
------WebKitFormBoundary
Content-Disposition: form-data; name="result"; filename="app.ipa"
Content-Type: application/octet-stream

<binary data>
------WebKitFormBoundary--
```

**Request Headers**:
```
X-Worker-Id: worker-1
```

**Response**:
```json
{
  "success": true,
  "build_id": "abc123"
}
```

**✅ Compatible**: No changes required.

---

### GET /api/stats

**Response** (TypeScript):
```json
{
  "nodesOnline": 5,
  "buildsQueued": 12,
  "activeBuilds": 3,
  "buildsToday": 84,
  "totalBuilds": 1247
}
```

**Response** (Elixir):
```json
{
  "nodesOnline": 5,
  "buildsQueued": 12,
  "activeBuilds": 3,
  "buildsToday": 84,
  "totalBuilds": 1247
}
```

**✅ Compatible**: No changes required.

---

## Authentication Changes

### API Key Validation

**TypeScript**:
```javascript
const apiKey = req.headers['x-api-key'];
if (apiKey !== config.CONTROLLER_API_KEY) {
  return res.status(401).send({ error: 'Unauthorized' });
}
```

**Elixir**:
```elixir
defp require_api_key(conn, _opts) do
  api_key = get_req_header(conn, "x-api-key") |> List.first()
  expected_key = Application.get_env(:expo_controller, :api_key)

  if Plug.Crypto.secure_compare(api_key || "", expected_key) do
    conn
  else
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "Unauthorized"})
    |> halt()
  end
end
```

**✅ Compatible**: Same HTTP behavior, more secure implementation.

---

### Build Token Authentication (NEW)

**Not yet implemented in Elixir.**

**TypeScript**:
```javascript
// Generate on submit
const accessToken = crypto.randomBytes(32).toString('hex');
await db.builds.update({ id: buildId, access_token: accessToken });

// Validate on download
const token = req.headers['x-build-token'];
const build = await db.builds.findOne({ id: buildId });
if (token !== build.access_token) {
  return res.status(403).send({ error: 'Forbidden' });
}
```

**Required for**:
- `/api/builds/:id/status` (allow user polling without API key)
- `/api/builds/:id/download` (allow user download without API key)
- `/api/builds/:id/logs` (allow user log access)

**Implementation Plan**:
1. Add `access_token` field to builds table
2. Generate token on build creation
3. Add `require_build_token_or_api_key` plug
4. Update affected endpoints

---

### Worker Access Validation

**TypeScript**:
```javascript
const workerId = req.headers['x-worker-id'];
const build = await db.builds.findOne({ id: buildId });
if (build.worker_id !== workerId) {
  return res.status(403).send({ error: 'Forbidden' });
}
```

**Elixir**:
```elixir
defp require_worker_access(conn, opts) do
  worker_id = get_req_header(conn, "x-worker-id") |> List.first()

  if opts[:build_id] do
    build = Builds.get_build(conn.params["id"])
    if build && build.worker_id == worker_id do
      conn
    else
      conn |> put_status(:forbidden) |> json(%{error: "Forbidden"}) |> halt()
    end
  else
    # Just verify worker exists
    if Workers.get_worker(worker_id) do
      conn
    else
      conn |> put_status(:forbidden) |> json(%{error: "Forbidden"}) |> halt()
    end
  end
end
```

**✅ Compatible**: Same validation logic.

---

## Breaking Changes Summary

### Critical (Blocks CLI/Worker)

1. **Missing `access_token` in submit response**
   - **Impact**: CLI cannot poll build status without API key
   - **Fix**: Implement build token generation
   - **Priority**: P0

2. **Timestamp format difference**
   - **Impact**: CLI may parse dates incorrectly
   - **Fix**: Support both epoch seconds and ISO8601
   - **Priority**: P1

### Non-Critical (Workarounds Exist)

1. **`/api/builds/:id/download` requires `:type` param**
   - **Impact**: CLI must update to include `?type=result`
   - **Fix**: Default to `result` when type omitted
   - **Priority**: P2 (already implemented with `/download` alias)

2. **Missing `/api/builds/active` endpoint**
   - **Impact**: Dashboard cannot show active builds
   - **Fix**: Use `/api/builds?status=building` query param
   - **Priority**: P2 (query params work)

---

## Migration Checklist for CLI/Worker

### CLI Changes Required

- [ ] Update submit endpoint: `POST /api/builds/submit` (no change needed)
- [ ] Store `access_token` from submit response
- [ ] Use build token for status polling (not API key)
- [ ] Handle ISO8601 timestamps in addition to epoch
- [ ] Update download endpoint: `/api/builds/:id/download` (no change needed with alias)

### Worker Changes Required

- [ ] Update poll endpoint: `GET /api/workers/poll` (no change needed)
- [ ] Update upload endpoint: `POST /api/workers/result` (alias handles `/upload`)
- [ ] Update heartbeat endpoint: `POST /api/workers/heartbeat` (no change needed)
- [ ] Handle ISO8601 timestamps in responses

### Testing Compatibility

**Run against both controllers**:
```bash
# Test TypeScript
CONTROLLER_URL=http://localhost:3000 bun test:integration

# Test Elixir
CONTROLLER_URL=http://localhost:4000 bun test:integration

# Both should pass
```

---

## Deprecation Timeline

### Phase 1 (Current): Dual Support
- TypeScript at `/api/*`
- Elixir at `/api/v2/*` OR `/api/*` (parallel)

### Phase 2 (Week 4-5): Elixir Primary
- Elixir at `/api/*`
- TypeScript at `/api/v1/*` (legacy)

### Phase 3 (Week 6+): TypeScript Decommissioned
- Only Elixir running
- TypeScript archived (read-only backups)

---

## Resources

- [TypeScript API Documentation](../../controller/README.md)
- [Elixir Implementation](./lib/expo_controller_web/router.ex)
- [Path Parity Matrix](../../MIGRATION_PATH_PARITY.md)
- [Migration Overview](./MIGRATION.md)
