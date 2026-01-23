# Central Controller Code Review
**Date:** 2026-01-23
**Reviewer:** Claude Opus 4.5
**Files:** server.ts, routes.ts, JobQueue.ts, FileStorage.ts, Database.ts

---

## Critical Issues

### 1. Path Traversal Vulnerability in FileStorage.createReadStream
**Location:** `/packages/controller/src/services/FileStorage.ts:94-96`
```typescript
createReadStream(filePath: string): Readable {
  return createReadStream(filePath);
}
```
**Problem:** `createReadStream(filePath)` accepts arbitrary paths with no validation. The routes pass `build.result_path`, `build.source_path`, etc. directly from the database. If an attacker can manipulate database entries (or if file paths are ever user-controlled), they can read any file on the system.
**Impact:** Full filesystem read access. Certificates, keys, `/etc/passwd`, source code.
**Solution:**
```typescript
createReadStream(filePath: string): Readable {
  const normalized = path.resolve(filePath);
  if (!normalized.startsWith(this.storagePath)) {
    throw new Error('Path traversal attempt blocked');
  }
  return createReadStream(normalized);
}
```

### 2. Route Path Collision - `/api/workers/poll` is Unreachable
**Location:** `/packages/controller/src/api/routes.ts:201`
```typescript
router.get('/api/workers/poll', (req: Request, res: Response) => {
```
**Problem:** Route defined as `/api/workers/poll` but router is mounted at `/api` (server.ts:54). This creates path `/api/api/workers/poll`. Workers will 404.
**Impact:** Workers cannot poll for jobs. System non-functional.
**Solution:** Change line 201 to `/workers/poll` (remove `/api/` prefix).

### 3. No File Size Limits on Uploads
**Location:** `/packages/controller/src/api/routes.ts:8`
```typescript
const upload = multer({ storage: multer.memoryStorage() });
```
**Problem:** `multer({ storage: multer.memoryStorage() })` with no `limits` config. A malicious actor can submit a 10GB "source" file, exhausting server memory instantly.
**Impact:** Trivial DoS. One request kills the server.
**Solution:**
```typescript
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 500 * 1024 * 1024 } // 500MB reasonable for iOS apps
});
```

### 4. No Upload Validation - File Content Not Verified
**Location:** `/packages/controller/src/api/routes.ts:43-52`
**Problem:** Files are saved directly without validating they are actual zip files. Malicious binaries can be stored and potentially served back.
**Impact:** Malware storage/distribution vector.
**Solution:** Validate magic bytes (`504B0304` for zip), reject non-zips.

### 5. Missing Authorization on All Endpoints
**Location:** All routes
**Problem:** No authentication. Any network-accessible actor can:
- Submit builds (steal compute)
- Register workers (receive source code and certificates)
- Download build artifacts (steal IPAs with embedded certs)
- Download source code and signing certs via `/api/builds/:id/source` and `/api/builds/:id/certs`
**Impact:** Even for "trust network," this is catastrophic if exposed beyond localhost.
**Solution:** Minimum: shared secret in header. Better: per-worker API keys stored in DB.

### 6. Credentials Exposed Without Worker Verification
**Location:** `/packages/controller/src/api/routes.ts:292-304`
```typescript
router.get('/builds/:id/certs', (req: Request, res: Response) => {
  const build = db.getBuild(req.params.id);

  if (!build || !build.certs_path) {
    return res.status(404).json({ error: 'Certs not found' });
  }

  res.setHeader('Content-Disposition', `attachment; filename="${build.id}-certs.zip"`);
  res.setHeader('Content-Type', 'application/zip');

  const stream = storage.createReadStream(build.certs_path);
  stream.pipe(res);
});
```
**Problem:** `/builds/:id/certs` endpoint serves signing certificates to anyone who knows the build ID. Build IDs are nanoid (21 chars) but predictable if enumerated.
**Impact:** Signing certificate theft enables unauthorized app distribution.
**Solution:** Require `worker_id` header, verify worker is assigned to this build.

---

## Architecture Concerns

### 7. Race Condition in Job Assignment
**Location:** `/packages/controller/src/api/routes.ts:232-246` and `/packages/controller/src/services/JobQueue.ts:33-41`
```typescript
// routes.ts:233
const build = queue.assignToWorker(worker);

// JobQueue.ts:33-41
assignToWorker(worker: Worker): Build | undefined {
  const build = this.pendingBuilds.shift();
  if (!build) return undefined;

  this.activeAssignments.set(build.id, { build, worker });
  this.emit('job:assigned', build, worker);

  return build;
}
```
**Problem:** Two workers can poll simultaneously, both call `assignToWorker()`, first one gets the job, second gets `undefined`. But the DB `updateBuildStatus` and `updateWorkerStatus` happen AFTER the queue assignment. If the first worker crashes between queue assignment and DB update, the build is orphaned.
**Impact:** Builds stuck in limbo, inconsistent state between queue and DB.
**Solution:** Use database transactions. The queue should not be the source of truth; DB should be. Or add mutex around assignment.

### 8. Queue/Database Inconsistency on Server Restart
**Location:** `/packages/controller/src/server.ts:29` and `/packages/controller/src/services/JobQueue.ts`
**Problem:** `JobQueue` is purely in-memory. On server restart:
- Pending builds in DB are not reloaded into queue
- Active assignments are lost
- Builds stuck in `assigned` status forever
**Impact:** Server restart loses all in-flight work.
**Solution:** On startup, query DB for `status = 'pending'` builds and enqueue them. Query `status = 'assigned'` builds and either reassign or reset to pending.

### 9. Worker Capability Matching Not Implemented
**Location:** `/packages/controller/src/api/routes.ts:233`
**Problem:** `queue.assignToWorker(worker)` ignores `worker.capabilities`. A Linux worker (if added later) would receive iOS builds.
**Impact:** Builds fail on incompatible workers.
**Solution:** Filter queue by `build.platform` matching worker capabilities before assignment.

### 10. No Build Timeout / Heartbeat
**Location:** JobQueue, routes
**Problem:** Once a worker takes a build, there's no timeout. If worker crashes, goes offline, or hangs, the build is stuck in `assigned` forever.
**Impact:** Builds never complete, queue blocked.
**Solution:** Add `assigned_at` timestamp, periodic sweep marks builds as failed if no heartbeat for N minutes.

### 11. Worker Heartbeat Updates Status Incorrectly
**Location:** `/packages/controller/src/api/routes.ts:215`
```typescript
// Update last seen
db.updateWorkerStatus(worker_id, 'idle', Date.now());
```
**Problem:** `db.updateWorkerStatus(worker_id, 'idle', Date.now())` is called on every poll, even when worker is actively building. This overwrites `building` status with `idle`.
**Impact:** Worker appears idle in UI while building. Could cause double-assignment bugs.
**Solution:** Only update `last_seen_at`, not status. Or check current status first.

---

## DRY Opportunities

### 12. Repeated `require('stream').Readable.from()` Pattern
**Location:** `/packages/controller/src/api/routes.ts:44`, `50`, `337`
```typescript
const sourceStream = require('stream').Readable.from(files.source[0].buffer);
// ...
const certsStream = require('stream').Readable.from(files.certs[0].buffer);
// ...
const resultStream = require('stream').Readable.from(file.buffer);
```
**Problem:** Three identical constructs for converting buffer to stream.
**Solution:**
```typescript
import { Readable } from 'stream';

function bufferToStream(buffer: Buffer): Readable {
  return Readable.from(buffer);
}
```
Also: `Readable.from()` is native to Node, no need for `require('stream')`.

### 13. Duplicated Build Lookup + 404 Pattern
**Location:** `/packages/controller/src/api/routes.ts:93-97`, `116-120`, `145-149`, `275-279`, `293-296`
**Problem:** Same pattern repeated 5 times:
```typescript
const build = db.getBuild(req.params.id);
if (!build) {
  return res.status(404).json({ error: 'Build not found' });
}
```
**Solution:** Middleware or helper:
```typescript
function requireBuild(db: DatabaseService) {
  return (req: Request, res: Response, next: NextFunction) => {
    const build = db.getBuild(req.params.id);
    if (!build) return res.status(404).json({ error: 'Build not found' });
    (req as any).build = build;
    next();
  };
}
```

### 14. Timestamp Pattern Repeated
**Location:** Multiple locations in routes.ts
**Problem:** `const timestamp = Date.now()` appears 5+ times, sometimes called multiple times in same handler.
**Solution:** Call once at handler start, reuse.

---

## Maintenance Improvements

### 15. Sync `require()` Inside Async Handler
**Location:** `/packages/controller/src/api/routes.ts:44`, `50`, `337`
**Problem:** Dynamic `require('stream')` is a CommonJS pattern in ESM code. Causes runtime overhead and linting issues.
**Impact:** Minor perf hit, code smell.
**Solution:** Import at top: `import { Readable } from 'stream';`

### 16. Missing Error Handling on Stream Pipe
**Location:** `/packages/controller/src/api/routes.ts:136-138`, `284-286`, `302-304`
```typescript
const stream = storage.createReadStream(build.result_path);
stream.pipe(res);
```
**Problem:** `stream.pipe(res)` without error handling. If file doesn't exist or read fails, response hangs or crashes.
**Impact:** Silent failures, hung connections.
**Solution:**
```typescript
stream.on('error', (err) => {
  console.error('Stream error:', err);
  if (!res.headersSent) {
    res.status(500).json({ error: 'File read failed' });
  }
});
stream.pipe(res);
```

### 17. No Graceful Shutdown
**Location:** `/packages/controller/src/server.ts:129-131`
```typescript
stop() {
  this.db.close();
}
```
**Problem:** `stop()` only closes DB. No HTTP server close, no queue drain.
**Impact:** In-flight requests dropped on shutdown.
**Solution:**
```typescript
private server?: http.Server;

start(): Promise<void> {
  return new Promise((resolve) => {
    this.server = this.app.listen(this.config.port, () => resolve());
  });
}

async stop() {
  if (this.server) {
    await new Promise<void>(r => this.server!.close(() => r()));
  }
  this.db.close();
}
```

### 18. Console Logging Instead of Structured Logging
**Location:** Throughout
**Problem:** `console.log` and `console.error` with string interpolation. No log levels, no structured data, no log rotation.
**Impact:** Hard to debug, hard to monitor.
**Solution:** Use `pino` or `winston` with JSON output.

### 19. DB Queries Return Unvalidated Types
**Location:** `/packages/controller/src/db/Database.ts:82`, `87`, etc.
```typescript
return stmt.get(id) as Worker | undefined;
```
**Problem:** `stmt.get(id) as Worker | undefined` - trusting SQLite returns correct shape without validation.
**Impact:** Runtime crashes if schema drifts.
**Solution:** Use Zod or similar to validate DB returns.

### 20. Unbounded `getAllBuilds()` and `getAllWorkers()`
**Location:** `/packages/controller/src/db/Database.ts:130-133`, `85-88`
```typescript
getAllBuilds(): Build[] {
  const stmt = this.db.prepare('SELECT * FROM builds ORDER BY submitted_at DESC');
  return stmt.all() as Build[];
}
```
**Problem:** No pagination. Returns every record ever.
**Impact:** Memory exhaustion as builds accumulate.
**Solution:** Add `LIMIT/OFFSET` or cursor pagination.

---

## Nitpicks

### 21. Inconsistent Error Response Format
**Location:** Various
**Problem:** Some errors: `{ error: 'message' }`, some: `{ error: 'message', details: ... }`. Inconsistent.
**Solution:** Standardize: `{ error: { code: string, message: string } }`.

### 22. Magic Number for multer Memory Storage
**Location:** `/packages/controller/src/api/routes.ts:8`
**Problem:** No explicit limit means default (~Infinity).
**Solution:** Always explicit: `limits: { fileSize: 500 * 1024 * 1024 }`.

### 23. `express.json()` Called Twice
**Location:** `/packages/controller/src/api/routes.ts:167` and `/packages/controller/src/server.ts:38`
**Problem:** `express.json()` middleware applied globally in server, then again on `/workers/register`.
**Impact:** No functional issue, just redundant.

### 24. Views Directory May Not Exist
**Location:** `/packages/controller/src/server.ts:51`
**Problem:** `app.set('views', join(__dirname, 'views'))` - if views folder missing, server crashes on first request.
**Impact:** Confusing error.
**Solution:** Check exists or bundle EJS templates.

### 25. Missing Content-Length Header on Downloads
**Location:** `/packages/controller/src/api/routes.ts:133-138`
**Problem:** No `Content-Length` header set. Clients can't show download progress.
**Impact:** Poor UX.
**Solution:** `stat()` file first, set header.

---

## Strengths

1. **Clean separation of concerns**: Server, routes, services, database are properly modular.
2. **Typed interfaces**: `Build`, `Worker`, `BuildLog` interfaces provide clarity.
3. **Event-driven queue**: `EventEmitter` pattern allows decoupled logging/metrics.
4. **Idempotent schema init**: `CREATE TABLE IF NOT EXISTS` is correct.
5. **Proper foreign keys**: DB schema has correct referential integrity.
6. **Good index coverage**: Indexes on `status`, `worker_id`, `build_id` will prevent slow queries.
7. **Stateless file storage abstraction**: `FileStorage` class makes future S3 migration clean.
8. **Minimal dependencies**: Only express, multer, nanoid, bun:sqlite. Small attack surface.

---

## Missing Features (vs ARCHITECTURE.md)

1. **No Web UI implemented** - routes.ts references `res.render('index')` but template not reviewed. Architecture promises "Web UI to view builds & workers."

2. **No queue recovery on restart** - Architecture says "Job queue (in-memory for prototype)" but doesn't account for durability. This WILL lose builds.

3. **No worker capability filtering** - Architecture mentions "platforms, xcode_version" in capabilities but matching not implemented.

4. **No build cancellation endpoint** - Users can't cancel pending/stuck builds.

5. **No worker deregistration** - Once registered, workers exist forever. No way to remove stale entries.

6. **No storage cleanup** - Old builds accumulate forever. Need retention policy.

---

## Priority Matrix

| Issue | Severity | Effort | Priority |
|-------|----------|--------|----------|
| #2 Route path collision | CRITICAL | 1 min | P0 |
| #3 No upload size limits | CRITICAL | 2 min | P0 |
| #5 No auth on endpoints | CRITICAL | 30 min | P0 |
| #6 Certs exposed | CRITICAL | 10 min | P0 |
| #1 Path traversal | HIGH | 5 min | P1 |
| #7 Race condition | HIGH | 1 hr | P1 |
| #8 Queue lost on restart | HIGH | 30 min | P1 |
| #10 No build timeout | MEDIUM | 1 hr | P2 |
| #11 Heartbeat overwrites status | MEDIUM | 5 min | P2 |
| #9 Capability matching | MEDIUM | 30 min | P2 |

---

## Summary

This is a functional prototype with solid foundations but **not production-safe**, even for a trust network. The route path collision (#2) is a blocking bug - workers literally cannot poll. The missing auth (#5) and exposed certs (#6) mean anyone on the network can steal signing certificates.

Fix #2, #3, #5, #6 before any deployment. Then address #1, #7, #8 before trusting it with real builds.

The code is clean and well-structured. With these fixes, it would be a solid MVP.
