# Elixir Controller Migration - Path Parity Matrix

**Status**: IN PROGRESS
**Date**: 2026-01-28
**Goal**: 100% API path compatibility between TypeScript and Elixir controllers

## Critical Requirement

**The Elixir controller MUST maintain exact path parity with the TypeScript controller.**
Workers, CLI clients, and tests depend on these exact paths.

## Path Parity Matrix

| TypeScript Path | Method | Elixir Path | Status | Notes |
|----------------|--------|-------------|--------|-------|
| **Build Routes** |
| `/api/builds/submit` | POST | `/api/builds` | ❌ BROKEN | Path changed - must be `/api/builds/submit` |
| `/api/builds/` | GET | `/api/builds` | ✅ OK | List builds |
| `/api/builds/active` | GET | MISSING | ❌ MISSING | Must implement |
| `/api/builds/:id/status` | GET | `/api/builds/:id` | ❌ BROKEN | Path changed - must be `/api/builds/:id/status` |
| `/api/builds/:id/logs` | GET | `/api/builds/:id/logs` | ✅ OK | Get logs |
| `/api/builds/:id/logs` | POST | MISSING | ❌ MISSING | Stream logs from worker |
| `/api/builds/:id/download` | GET | `/api/builds/:id/download/:type` | ❌ BROKEN | Extra :type param breaks CLI |
| `/api/builds/:id/source` | GET | MISSING | ❌ MISSING | Worker downloads source |
| `/api/builds/:id/certs` | GET | MISSING | ❌ MISSING | Worker downloads certs |
| `/api/builds/:id/certs-secure` | GET | MISSING | ❌ MISSING | Worker gets certs as JSON |
| `/api/builds/:id/heartbeat` | POST | MISSING | ❌ MISSING | Worker heartbeat |
| `/api/builds/:id/telemetry` | POST | MISSING | ❌ MISSING | VM telemetry |
| `/api/builds/:id/cancel` | POST | `/api/builds/:id/cancel` | ✅ OK | Cancel build |
| `/api/builds/:id/retry` | POST | MISSING | ❌ MISSING | Retry failed build |
| **Worker Routes** |
| `/api/workers/register` | POST | `/api/workers/register` | ✅ OK | Register worker |
| `/api/workers/poll` | GET | `/api/workers/poll` | ✅ OK | Poll for jobs |
| `/api/workers/upload` | POST | `/api/workers/result` | ❌ BROKEN | Path changed - must be `/api/workers/upload` |
| `/api/workers/:id/stats` | GET | MISSING | ❌ MISSING | Worker statistics |
| **Stats Routes** |
| `/api/stats/` | GET | `/api/stats` | ✅ OK | Public stats |
| **Diagnostics Routes** |
| `/api/diagnostics/report` | POST | MISSING | ❌ MISSING | Save diagnostic report |
| `/api/diagnostics/:worker_id` | GET | MISSING | ❌ MISSING | Get worker diagnostics |
| `/api/diagnostics/:worker_id/latest` | GET | MISSING | ❌ MISSING | Get latest diagnostic |
| **System Routes** |
| `/health` | GET | MISSING | ❌ MISSING | Health check |
| `/` | GET | `/` | ✅ OK | Web UI dashboard |

## Summary

- **Total Endpoints**: 23
- **Exact Match**: 6 (26%)
- **Path Broken**: 4 (17%)
- **Missing**: 13 (57%)

## Critical Path Breaks

These path changes will break existing clients:

1. **`/api/builds/submit` → `/api/builds`**
   - CLI sends POST to `/api/builds/submit`
   - Elixir expects `/api/builds`
   - **Fix**: Add route alias or rename

2. **`/api/builds/:id/status` → `/api/builds/:id`**
   - CLI polls `/api/builds/:id/status`
   - Elixir only has `/api/builds/:id`
   - **Fix**: Add `/status` alias or implement separate endpoint

3. **`/api/builds/:id/download` → `/api/builds/:id/download/:type`**
   - CLI calls `/api/builds/:id/download`
   - Elixir requires `/api/builds/:id/download/result`
   - **Fix**: Make `:type` optional, default to `result`

4. **`/api/workers/upload` → `/api/workers/result`**
   - Workers POST to `/api/workers/upload`
   - Elixir expects `/api/workers/result`
   - **Fix**: Add route alias or rename

## Missing Critical Routes

These routes are completely missing from Elixir:

### Build Routes (9 missing)
1. `GET /api/builds/active` - List active builds
2. `POST /api/builds/:id/logs` - Stream logs from worker
3. `GET /api/builds/:id/source` - Download source (worker auth)
4. `GET /api/builds/:id/certs` - Download certs (worker auth)
5. `GET /api/builds/:id/certs-secure` - Get certs as JSON (worker auth)
6. `POST /api/builds/:id/heartbeat` - Worker heartbeat
7. `POST /api/builds/:id/telemetry` - VM telemetry
8. `POST /api/builds/:id/retry` - Retry failed build

### Worker Routes (1 missing)
9. `GET /api/workers/:id/stats` - Worker statistics

### Diagnostics Routes (3 missing)
10. `POST /api/diagnostics/report` - Save diagnostic report
11. `GET /api/diagnostics/:worker_id` - Get worker diagnostics
12. `GET /api/diagnostics/:worker_id/latest` - Get latest diagnostic

### System Routes (1 missing)
13. `GET /health` - Health check

## Authentication Requirements

| Endpoint | Auth Type | TS Implementation | Elixir Status |
|----------|-----------|-------------------|---------------|
| `/api/builds/submit` | API Key | ✅ | ✅ |
| `/api/builds/:id/status` | API Key OR Build Token | ✅ | ❌ Build token not impl |
| `/api/builds/:id/download` | API Key OR Build Token | ✅ | ❌ Build token not impl |
| `/api/builds/:id/source` | Worker ID match | ✅ | ❌ Missing route |
| `/api/builds/:id/certs` | Worker ID match | ✅ | ❌ Missing route |
| `/api/workers/upload` | None (body verified) | ✅ | ❌ Path broken |
| `/health` | None | ✅ | ❌ Missing route |

## Response Format Parity

### TypeScript: `/api/builds/submit` Response
```json
{
  "id": "abc123",
  "status": "pending",
  "submitted_at": 1234567890,
  "access_token": "xyz..."
}
```

### Elixir: `/api/builds` Response
```json
{
  "id": "abc123",
  "status": "pending",
  "platform": "ios",
  "submitted_at": "2026-01-28T12:00:00Z"
}
```

**Issues**:
- Missing `access_token` field ❌
- `submitted_at` format different (timestamp vs ISO8601) ⚠️

## Action Items

1. **Fix Path Breaks** (Priority 1 - Blocking)
   - Add `/api/builds/submit` → create alias
   - Add `/api/builds/:id/status` → show alias
   - Make `/api/builds/:id/download` work without `:type`
   - Add `/api/workers/upload` → result alias

2. **Implement Missing Routes** (Priority 1 - Blocking)
   - All build worker-auth routes (source, certs, certs-secure, heartbeat, telemetry)
   - Build retry endpoint
   - Worker stats endpoint
   - Health check endpoint
   - Active builds endpoint
   - POST logs endpoint

3. **Add Build Token Auth** (Priority 1 - Security)
   - Generate access tokens on submit
   - Validate tokens in middleware
   - Support API Key OR Build Token auth

4. **Implement Diagnostics** (Priority 2)
   - Add diagnostics routes
   - Add database schema for reports

5. **Response Format Standardization** (Priority 2)
   - Ensure all responses match TS format exactly
   - Timestamps: decide on format (epoch ms vs ISO8601)
   - Add missing fields (access_token, etc.)
