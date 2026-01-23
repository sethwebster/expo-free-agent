# P0 Security Fixes - 2026-01-23

## Overview

Fixed all P0 blocking bugs identified in code review. System now has basic security posture suitable for localhost-only trusted network deployment.

## Fixed Issues

### 1. Route Collision (P0) ✅

**Issue:** Worker poll endpoint unreachable at `/api/api/workers/poll` due to double `/api` prefix.

**Fix:** Changed route from `/api/workers/poll` to `/workers/poll` since router already mounted at `/api`.

**Files:**
- `/packages/controller/src/api/routes.ts:201`

**Impact:** Workers can now successfully poll for jobs.

---

### 2. Upload Size Limits (P0) ✅

**Issue:** No multer file size limits - trivial DoS attack possible with large uploads.

**Fix:** Configured separate multer instances with size limits:
- Source files: 500MB (large iOS apps)
- Certificate files: 10MB (certs are small)
- Build results: 1GB (built IPAs can be large)

**Files:**
- `/packages/controller/src/api/routes.ts:23-45`
- `/packages/controller/src/domain/Config.ts:19-22`

**Impact:** Server protected from memory exhaustion attacks.

---

### 3. Authentication (P0) ✅

**Issue:** No authentication on any endpoint - anyone on network can submit builds, steal certs.

**Fix:** Implemented API key authentication:
- All `/api/*` routes require `X-API-Key` header
- Shared secret configurable via env var or CLI flag
- Minimum key length: 16 characters
- Default key shows warning on startup

**Files:**
- `/packages/controller/src/middleware/auth.ts` (new)
- `/packages/controller/src/domain/Config.ts` (new)
- `/packages/controller/src/api/routes.ts:47`

**Configuration:**
```bash
# Environment variable
export CONTROLLER_API_KEY="your-secure-key-min-16-chars"

# CLI flag
expo-controller start --api-key "your-secure-key-min-16-chars"
```

**Impact:** Prevents unauthorized access to all API endpoints.

---

### 4. Worker Access Control (P0) ✅

**Issue:** Any worker could download source/certs for any build - credential theft vector.

**Fix:** Added `requireWorkerAccess` middleware:
- `/builds/:id/source` requires `X-Worker-Id` header
- `/builds/:id/certs` requires `X-Worker-Id` header
- Validates worker is assigned to build OR build is pending
- Prevents workers from accessing other workers' builds

**Files:**
- `/packages/controller/src/middleware/auth.ts:32-64`
- `/packages/controller/src/api/routes.ts:288,307`

**Impact:** Prevents credential theft between workers.

---

### 5. Path Traversal (P1) ✅

**Issue:** `FileStorage.createReadStream()` accepted arbitrary paths - could read `/etc/passwd`, keys, etc.

**Fix:** Validates all paths are inside storage directory:
- Normalizes paths with `path.resolve()`
- Checks normalized path starts with storage root
- Rejects any path outside storage directory
- Returns explicit error on traversal attempt

**Files:**
- `/packages/controller/src/services/FileStorage.ts:94-108`

**Tests:**
- `/packages/controller/src/services/__tests__/FileStorage.test.ts`
- 6 tests covering various traversal attacks

**Impact:** Prevents arbitrary file read from server filesystem.

---

### 6. Race Condition (P1) ✅

**Issue:** Two workers polling simultaneously could both claim same build - DB/queue inconsistency.

**Fix:** Atomic job assignment with database transaction:
- `db.assignBuildToWorker()` uses `BEGIN IMMEDIATE` transaction
- Checks build is still pending before assignment
- Updates build status and worker status atomically
- Rolls back if build already assigned

**Files:**
- `/packages/controller/src/db/Database.ts:198-231`
- `/packages/controller/src/api/routes.ts:246-256`

**Impact:** Eliminates race condition in job assignment.

---

### 7. Queue Persistence (P1) ✅

**Issue:** In-memory queue lost on server restart - builds stuck forever.

**Fix:** Queue state restored from database on startup:
- `queue.restoreFromDatabase()` called in server constructor
- Loads pending builds from DB and re-queues
- Loads assigned builds and restores worker assignments
- Orphaned builds (worker gone) reset to pending

**Files:**
- `/packages/controller/src/services/JobQueue.ts:21-50`
- `/packages/controller/src/server.ts:33-40`
- `/packages/controller/src/db/Database.ts:191-196`

**Impact:** Server restarts no longer lose builds.

---

### 8. Stream Error Handling (P2) ✅

**Issue:** `stream.pipe(res)` without error handling - hung connections on file read errors.

**Fix:** Added `pipeStreamSafely()` helper:
- Attaches error handler to stream
- Returns 500 error if stream fails
- Prevents response from hanging
- Applied to all download endpoints

**Files:**
- `/packages/controller/src/api/routes.ts:10-20`
- Applied to routes at lines 142, 293, 312

**Impact:** Graceful error handling for file downloads.

---

### 9. Heartbeat Status Bug (P2) ✅

**Issue:** Worker poll overwrote status to 'idle' even when building - could cause double-assignment.

**Fix:** Only update `last_seen_at`, preserve current status:
- Get current worker status from DB
- Update last_seen with same status
- Don't reset 'building' workers to 'idle'

**Files:**
- `/packages/controller/src/api/routes.ts:218-224`

**Impact:** Worker status remains accurate during builds.

---

### 10. DRY Improvements ✅

**Issue:** Repeated `require('stream').Readable.from()` pattern, magic imports.

**Fix:**
- Created `bufferToStream()` helper function
- Imported `Readable` at top of file
- Replaced all `require('stream')` calls

**Files:**
- `/packages/controller/src/api/routes.ts:5,10-12,51,55,352`

**Impact:** Cleaner code, no dynamic requires.

---

## New Files Created

1. `/packages/controller/src/domain/Config.ts` - Configuration value object with validation
2. `/packages/controller/src/middleware/auth.ts` - Authentication middleware
3. `/packages/controller/src/services/__tests__/FileStorage.test.ts` - Path traversal tests
4. `/packages/controller/src/__tests__/integration.test.ts` - Integration tests
5. `/packages/controller/SECURITY.md` - Security documentation

## Configuration Changes

### Environment Variables

```bash
# API key for authentication (required for production)
CONTROLLER_API_KEY="your-secure-key-min-16-chars"
```

### CLI Flags

```bash
expo-controller start \
  --port 3000 \
  --db ./data/controller.db \
  --storage ./storage \
  --api-key "your-secure-key-min-16-chars"
```

## Breaking Changes

### Workers Must Send Headers

All API requests now require:

```bash
# Authentication
-H "X-API-Key: your-api-key"

# Source/cert downloads also need
-H "X-Worker-Id: worker-xyz"
```

### Example Worker Requests

```bash
# Register
curl -X POST http://localhost:3000/api/workers/register \
  -H "X-API-Key: your-api-key" \
  -H "Content-Type: application/json" \
  -d '{"name":"Worker 1","capabilities":{"platforms":["ios"]}}'

# Poll
curl http://localhost:3000/api/workers/poll?worker_id=abc123 \
  -H "X-API-Key: your-api-key"

# Download source
curl http://localhost:3000/api/builds/build-123/source \
  -H "X-API-Key: your-api-key" \
  -H "X-Worker-Id: abc123" \
  -o source.zip
```

## Testing

### Unit Tests
```bash
cd packages/controller
bun test src/services/__tests__/FileStorage.test.ts
# 6 pass, 0 fail
```

### Integration Tests
```bash
bun test src/__tests__/integration.test.ts
# 4 pass, 0 fail
```

### Build
```bash
bun run build
# Success - no errors
```

## Migration Guide

### Updating Existing Workers

1. Add API key to worker config
2. Send `X-API-Key` header on all requests
3. Send `X-Worker-Id` header when downloading source/certs

### Updating Controller

1. Set `CONTROLLER_API_KEY` environment variable
2. Restart controller
3. Update all workers with new API key

## Security Posture

### Now Protected Against
- ✅ Unauthorized API access
- ✅ Worker credential theft
- ✅ Path traversal attacks
- ✅ DoS via large uploads
- ✅ Race conditions in job assignment
- ✅ Build loss on restart

### Still Vulnerable To (Production TODO)
- ❌ No HTTPS (localhost-only assumption)
- ❌ Shared API key (no per-worker auth)
- ❌ No rate limiting
- ❌ No file validation (zip magic bytes)
- ❌ No malware scanning

**See SECURITY.md for complete security documentation.**

## Verification Checklist

- [x] Route collision fixed - workers can poll
- [x] Upload size limits prevent DoS
- [x] API key authentication on all endpoints
- [x] Worker access control on source/certs
- [x] Path traversal blocked
- [x] Race condition eliminated
- [x] Queue persisted on restart
- [x] Stream errors handled gracefully
- [x] Tests pass (10/10)
- [x] Build succeeds
- [x] Documentation complete

## Next Steps

1. Update worker client to send required headers
2. Deploy updated controller to test environment
3. Verify end-to-end build flow
4. Monitor logs for auth failures
5. Plan production security enhancements (see SECURITY.md)
