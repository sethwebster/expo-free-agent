# E2E Test Compatibility Analysis: TypeScript vs Elixir Controllers

## Executive Summary

**Status**: Ready for testing after test fixes from previous agent work
**Key Difference**: Port numbers (TS: 3100 in E2E, Elixir: 4000)
**Test Script**: Created `/test-e2e-elixir.sh` for Elixir testing
**Blocking Issue**: 76 Elixir tests failing (timestamp microsecond precision)

## E2E Test Flow Analysis

The E2E test (`test-e2e.sh`) validates the complete build lifecycle:

1. **Start Controller** (TS: port 3100, Elixir: port 4000)
2. **Health Check** → `GET /health`
3. **Create Test Project** (Expo app.json, package.json, index.js)
4. **Submit Build** → `POST /api/builds/submit` with source zip
5. **Start Mock Worker** → Polls for jobs
6. **Worker Registration** → `POST /api/workers/register`
7. **Worker Poll** → `GET /api/workers/poll?worker_id={id}`
8. **Worker Download Source** → Downloads from job.source_url
9. **Worker Upload Result** → `POST /api/workers/upload` with result file
10. **Check Build Status** → `GET /api/builds/{id}/status`
11. **Download Result** → `GET /api/builds/{id}/download`
12. **Verify Logs** → `GET /api/builds/{id}/logs`
13. **Test Concurrent Builds** → Submit 3 builds simultaneously
14. **Verify Queue Stats** → `GET /health` (check pending count)

## API Endpoint Comparison

### Critical Endpoints Required by E2E Test

| Endpoint | TypeScript | Elixir | Status |
|----------|-----------|--------|--------|
| `GET /health` | ✓ | ✓ | Match |
| `POST /api/builds/submit` | ✓ | ✓ (alias for create) | Match |
| `GET /api/builds/:id/status` | ✓ | ✓ (nested route) | Match |
| `GET /api/builds/:id/logs` | ✓ | ✓ (nested route) | Match |
| `GET /api/builds/:id/download` | ✓ | ✓ (defaults to result) | Match |
| `POST /api/workers/register` | ✓ | ✓ | Match |
| `GET /api/workers/poll` | ✓ | ✓ | Match |
| `POST /api/workers/upload` | ✓ | ✓ (alias) | Match |

### Response Format Comparison

#### Health Check
**TypeScript:**
```json
{
  "status": "ok",
  "queue": { "pending": 0, "active": 0 },
  "storage": { /* stats */ }
}
```

**Elixir:**
```json
{
  "status": "ok",
  "queue": { "pending": 0, "active": 0 },
  "storage": {}
}
```
Status: Compatible (storage stats empty but structure matches)

#### Build Submission
Both return:
```json
{
  "id": "build-uuid",
  "status": "pending",
  "platform": "ios",
  ...
}
```
Status: Compatible

## Port Configuration

- **TypeScript E2E**: Uses port 3100 (configurable via `CONTROLLER_PORT`)
- **Elixir Dev**: Uses port 4000 (configured via `PORT` env var or runtime.exs)
- **Test Script**: Created `test-e2e-elixir.sh` hardcoded to port 4000

## Authentication

Both controllers use identical auth mechanism:
- Header: `X-API-Key: {key}`
- Required for all API endpoints except `/health` and `/api/stats`
- Test API Key: `test-api-key-for-e2e-testing-minimum-32-chars`

## Mock Worker Compatibility

The mock worker (`test/mock-worker.ts`) is controller-agnostic:
- Polls via `GET /api/workers/poll?worker_id={id}`
- Downloads source from returned `job.source_url`
- Uploads result to `POST /api/workers/upload`
- Uses `X-API-Key` and `X-Worker-Id` headers

No modifications needed for Elixir compatibility.

## Key Differences Identified

### 1. Port Numbers (Non-Breaking)
- TS E2E: 3100
- Elixir Dev: 4000
- Solution: Created separate `test-e2e-elixir.sh` script

### 2. Storage Stats (Non-Breaking)
- TS: Returns detailed storage stats
- Elixir: Returns empty object `{}`
- Impact: None (E2E doesn't validate storage stats)

### 3. Route Aliases (Non-Breaking)
Elixir provides both forms:
- `POST /api/builds/submit` (TS compatibility)
- `POST /api/builds` (RESTful)
- `POST /api/workers/upload` (TS compatibility)
- `POST /api/workers/result` (RESTful)

### 4. Test Database (Blocking)
- TS: Uses in-memory SQLite via `--db` flag
- Elixir: Requires PostgreSQL with connection string
- Test Suite: 76/118 tests failing (microsecond precision issue)
- Impact: Cannot verify E2E until tests pass

## Testing Strategy

### Prerequisites
1. **Fix Elixir tests** (Agent #1 task)
   - Problem: `:utc_datetime` rejects microseconds
   - Solution: Truncate timestamps in tests or schema
   - Status: Blocking E2E verification

2. **Start Elixir Controller**
   ```bash
   cd packages/controller_elixir
   export CONTROLLER_API_KEY="test-api-key-for-e2e-testing-minimum-32-chars"
   export PORT=4000
   mix ecto.reset  # Reset test database
   mix phx.server
   ```

### Run E2E Test
```bash
# From repo root
./test-e2e-elixir.sh
```

### Expected Results
If API is compatible:
- ✓ Health check passes
- ✓ Build submission succeeds
- ✓ Worker registration succeeds
- ✓ Worker polls and receives job
- ✓ Build completes successfully
- ✓ Build download succeeds
- ✓ Build logs contain expected entries
- ✓ Concurrent builds queue properly
- ✓ Queue stats reflect pending builds

## Potential Issues to Monitor

### 1. File Upload/Download
**Risk**: Medium
**Area**: Multipart form parsing, streaming responses
**Test Coverage**: Steps 3, 7, 9
**Symptoms**: Failed uploads, corrupted downloads

### 2. Build State Transitions
**Risk**: Medium
**Area**: `pending → assigned → building → completed/failed`
**Test Coverage**: Steps 5, 10
**Symptoms**: Stuck builds, wrong status

### 3. Worker-Build Assignment
**Risk**: Medium
**Area**: Queue manager assigns jobs to workers
**Test Coverage**: Step 7 (poll returns job)
**Symptoms**: Worker never receives job

### 4. Database Transactions
**Risk**: Low
**Area**: Concurrent build submissions
**Test Coverage**: Step 9 (3 concurrent builds)
**Symptoms**: Lost builds, duplicate IDs

### 5. Error Handling
**Risk**: Low
**Area**: Invalid requests, missing files
**Test Coverage**: Implicit (worker failure path)
**Symptoms**: 500 errors, unhandled exceptions

## Compatibility Assessment

### Blocking Issues
1. **Test Suite Failures** (76/118 tests)
   - Severity: P0 (blocks verification)
   - Owner: Agent #1
   - ETA: In progress

### High Priority (P1)
None identified at design level.

### Medium Priority (P2)
1. **Storage Stats Implementation**
   - Current: Empty object `{}`
   - Expected: File count, size stats
   - Impact: Dashboard may show incomplete info
   - Fix: Implement `get_storage_stats/0` in HealthController

### Low Priority (P3)
1. **Port Standardization**
   - Consider using same port for both (e.g., 3000)
   - Or add `--elixir` flag to original test-e2e.sh
   - Fix: Update docs/config

## Recommendations

### Immediate (Before E2E)
1. **Fix timestamp tests** (Agent #1)
2. **Verify Elixir server starts** without errors
3. **Run health check** manually: `curl http://localhost:4000/health`

### Post E2E Success
1. **Merge test scripts** into single `test-e2e.sh --controller [ts|elixir]`
2. **Add E2E to CI** for both controllers
3. **Implement storage stats** for dashboard parity

### Post E2E Failure
1. **Document exact error** (request/response logs)
2. **Isolate failing endpoint** (health → submit → register → poll)
3. **Add integration test** for specific failing case
4. **Fix Elixir controller** to match TS behavior
5. **Re-run E2E** to verify fix

## Files Modified/Created

1. **Created**: `/test-e2e-elixir.sh`
   - E2E test script for Elixir controller (port 4000)
   - Identical flow to TypeScript version
   - Expects controller already running

2. **Created**: `/docs/testing/e2e-elixir-compatibility.md` (this file)
   - Compatibility analysis
   - API comparison
   - Testing strategy

## Next Steps

**For User:**
1. Wait for Agent #1 to fix test suite (76 failures)
2. Verify `mix phx.server` starts successfully
3. Run `./test-e2e-elixir.sh` to validate E2E flow
4. Report any failures with full error logs

**For Agent #1 (Test Fixes):**
- Focus on timestamp microsecond issue (affects 76 tests)
- Verify all endpoints work with correct auth headers
- Ensure database seeds/fixtures create valid test data

**For Future Work:**
- Merge E2E scripts into single configurable version
- Add E2E to GitHub Actions for both controllers
- Implement storage stats in Elixir health endpoint
