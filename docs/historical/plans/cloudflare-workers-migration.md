# Cloudflare Workers Migration Plan

## Critical Issues

### CRITICAL-1: Durable Object Queue State Loss on Error
**Location:** BuildQueue.assignToWorker() (lines 29-46)
**Problem:** Queue shifts build from pending array BEFORE writing to storage. If transaction fails, build is lost forever.
**Impact:** Data loss. Builds silently disappear with no recovery path.
**Fix:** Read-modify-write must be atomic. Only remove from pending after successful write.

### CRITICAL-2: No Durable Object State Persistence to D1
**Location:** Entire BuildQueue implementation
**Problem:** Durable Object state is ephemeral. DO can be evicted from memory and lose all in-progress state. Plan shows no sync between DO state and D1.
**Impact:** Queue state completely lost on DO eviction. Pending builds vanish.
**Fix:** D1 must be source of truth. DO is coordination layer only. All state changes must write-through to D1.

### CRITICAL-3: Upload Confirmation Race Condition
**Location:** handleBuildConfirm() (lines 193-207)
**Problem:** No verification that files actually exist in R2 before enqueuing. Client can call confirm without uploading.
**Impact:** Workers assigned builds with missing source files. Build system grinds to halt.
**Fix:** HEAD request to R2 to verify object existence before confirming.

### CRITICAL-4: Missing Presigned URL Authentication
**Location:** generateUploadUrl() (lines 116-127)
**Problem:** Any buildId generates valid upload URL. No verification caller owns/submitted this build.
**Impact:** Attacker can overwrite source files for any pending build with malicious code.
**Fix:** Include authentication token in presigned URL path or use signed cookies.

### CRITICAL-5: Timing Attack on API Key Validation
**Location:** Auth middleware (lines 139-143)
**Problem:** Direct string comparison `apiKey !== env.CONTROLLER_API_KEY` is vulnerable to timing attacks.
**Impact:** API key can be brute-forced by measuring response times.
**Fix:** Use constant-time comparison (crypto.subtle.timingSafeEqual).

### CRITICAL-6: Missing Build Status Transition Guards
**Location:** handleBuildConfirm(), handleWorkerPoll()
**Problem:** No validation of current build status before transitions. Can confirm already-building build, assign already-assigned build.
**Impact:** State corruption, duplicate work, inconsistent data.
**Fix:** Atomic compare-and-swap on status field.

### CRITICAL-7: No Heartbeat Timeout Detection
**Location:** Not implemented in plan
**Problem:** Original system has heartbeat mechanism. Plan mentions heartbeats but no timeout detection/cleanup.
**Impact:** Workers crash mid-build, builds stuck in 'assigned' forever. Queue blocked.
**Fix:** Need Durable Object alarm or cron trigger to check for stale builds.

### CRITICAL-8: Unbounded Log Storage
**Location:** build_logs table design (lines 91-99)
**Problem:** No pagination, no cleanup, no max entries per build. D1 has 500MB/database limit.
**Impact:** Database fills up, new builds fail.
**Fix:** Add TTL, max logs per build, pagination with LIMIT/OFFSET.

---

## Overview

Migrate Expo Free Agent Controller from Express/Bun server to Cloudflare Workers serverless architecture for cost efficiency and global distribution.

## Architecture

### Current Stack -> Cloudflare Stack

| Component | Current | Cloudflare |
|-----------|---------|------------|
| Server | Express on Bun | Workers (edge functions) |
| Database | SQLite (file) | D1 (distributed SQLite) |
| Queue | In-memory JS | Durable Object |
| Storage | Local filesystem | R2 (S3-compatible) |
| Auth | Express middleware | Workers middleware |

## Core Components

### 1. Durable Object: BuildQueue

**Purpose:** Atomic job assignment, preventing race conditions

```typescript
// REVIEW: Single global DO = single point of failure + 1000 req/s limit
// REVIEW: State not persisted to D1 - will lose queue on DO eviction
export class BuildQueue {
  state: DurableObjectState
  env: Env // ADDED: Need env for D1 access

  constructor(state: DurableObjectState, env: Env) {
    this.state = state
    this.env = env
  }

  async assignToWorker(workerId: string): Promise<Build | null> {
    // Single-threaded execution = no race conditions
    const pending = await this.state.storage.get<Build[]>('pending') || []

    if (pending.length === 0) return null

    // CRITICAL BUG: shift() mutates array before transaction succeeds
    // If transaction fails, build is lost forever
    const build = pending.shift()!
    build.worker_id = workerId
    build.status = 'assigned'
    build.started_at = Date.now()

    // FIXED VERSION:
    // const build = pending[0]
    // const updatedBuild = { ...build, worker_id: workerId, status: 'assigned', started_at: Date.now() }
    // await this.state.storage.transaction(async txn => {
    //   await txn.put('pending', pending.slice(1))  // Remove first item AFTER write succeeds
    //   await txn.put(`active:${build.id}`, updatedBuild)
    // })
    // // CRITICAL: Also update D1 to prevent state loss on DO eviction
    // await this.env.DB.prepare('UPDATE builds SET status = ?, worker_id = ?, started_at = ? WHERE id = ?')
    //   .bind('assigned', workerId, updatedBuild.started_at, build.id).run()

    await this.state.storage.transaction(async txn => {
      await txn.put('pending', pending)
      await txn.put(`active:${build.id}`, build)
    })

    return build
  }

  async enqueue(build: Build) {
    const pending = await this.state.storage.get<Build[]>('pending') || []
    pending.push(build)
    await this.state.storage.put('pending', pending)
    // MISSING: D1 write-through
  }

  async complete(buildId: string) {
    await this.state.storage.delete(`active:${buildId}`)
    // MISSING: D1 write-through
  }

  // MISSING: Heartbeat timeout alarm
  // async alarm() {
  //   const activeBuilds = await this.state.storage.list({ prefix: 'active:' })
  //   const now = Date.now()
  //   const TIMEOUT = 5 * 60 * 1000 // 5 min
  //   for (const [key, build] of activeBuilds) {
  //     if (now - build.started_at > TIMEOUT && !build.last_heartbeat_at) {
  //       // Requeue stale build
  //       await this.fail(build.id, true)
  //     }
  //   }
  //   await this.state.storage.setAlarm(Date.now() + 60000) // Check every minute
  // }
}
```

### 2. D1 Database Schema

**Migration from SQLite:**
```sql
-- Same schema, but deployed to D1
CREATE TABLE workers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  status TEXT NOT NULL,
  capabilities TEXT NOT NULL,
  registered_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  builds_completed INTEGER DEFAULT 0,
  builds_failed INTEGER DEFAULT 0
);

CREATE TABLE builds (
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL,
  platform TEXT NOT NULL,
  source_path TEXT NOT NULL,
  certs_path TEXT,
  result_path TEXT,
  worker_id TEXT,
  submitted_at INTEGER NOT NULL,
  started_at INTEGER,
  completed_at INTEGER,
  error_message TEXT,
  last_heartbeat_at INTEGER,
  -- ADDED: Retry tracking
  retry_count INTEGER DEFAULT 0,
  max_retries INTEGER DEFAULT 3,
  FOREIGN KEY (worker_id) REFERENCES workers(id)
);

CREATE TABLE build_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  build_id TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  level TEXT NOT NULL,
  message TEXT NOT NULL,
  FOREIGN KEY (build_id) REFERENCES builds(id)
);

-- MISSING: Indexes for common queries
CREATE INDEX idx_builds_status ON builds(status);
CREATE INDEX idx_builds_worker ON builds(worker_id);
CREATE INDEX idx_logs_build ON build_logs(build_id);
CREATE INDEX idx_builds_submitted ON builds(submitted_at);
-- ADDED: For heartbeat timeout detection
CREATE INDEX idx_builds_heartbeat ON builds(last_heartbeat_at) WHERE status = 'assigned';
```

### 3. R2 Storage Structure

**Bucket layout:**
```
expo-free-agent-builds/
   builds/
      {buildId}/
         source.zip
         certs.zip
         result.ipa
```

**Presigned URLs for uploads:**
```typescript
// SECURITY ISSUE: No authentication - any buildId works
// Attacker can overwrite source for any pending build
async function generateUploadUrl(buildId: string, type: 'source' | 'certs') {
  // MISSING: Verify caller owns this buildId
  // const build = await env.DB.prepare('SELECT submitted_by FROM builds WHERE id = ?').bind(buildId).first()
  // if (!build || build.submitted_by !== authenticatedUserId) {
  //   throw new Error('Unauthorized')
  // }

  const key = `builds/${buildId}/${type}.zip`

  // Cloudflare R2 presigned URL
  const url = await env.STORAGE.sign(key, {
    method: 'PUT',
    expiresIn: 3600, // 1 hour
  })

  return url
}
```

### 4. Worker Routes

**API structure:**
```typescript
// src/index.ts
export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url)

    // TIMING ATTACK: String comparison leaks key via timing
    const apiKey = request.headers.get('X-API-Key')
    if (apiKey !== env.CONTROLLER_API_KEY) {
      return new Response('Unauthorized', { status: 401 })
    }

    // FIXED:
    // const apiKey = request.headers.get('X-API-Key') || ''
    // const keyBuffer = new TextEncoder().encode(apiKey)
    // const expectedBuffer = new TextEncoder().encode(env.CONTROLLER_API_KEY)
    // if (keyBuffer.length !== expectedBuffer.length ||
    //     !crypto.subtle.timingSafeEqual(keyBuffer, expectedBuffer)) {
    //   return new Response('Unauthorized', { status: 401 })
    // }

    // Route handlers
    if (url.pathname === '/api/builds/submit') {
      return handleBuildSubmit(request, env)
    }

    if (url.pathname.startsWith('/api/workers/poll')) {
      return handleWorkerPoll(request, env)
    }

    // ... other routes

    return new Response('Not found', { status: 404 })
  }
}
```

### 5. Build Submission Flow

**New multi-step flow (due to 30s timeout):**

```typescript
// Step 1: Client requests upload URLs
async function handleBuildSubmit(request: Request, env: Env) {
  const { platform } = await request.json()
  const buildId = nanoid()

  // MISSING: Validate platform
  // if (!['ios', 'android'].includes(platform)) {
  //   return new Response('Invalid platform', { status: 400 })
  // }

  // Generate presigned URLs for direct R2 upload
  const sourceUrl = await generateUploadUrl(buildId, 'source')
  const certsUrl = await generateUploadUrl(buildId, 'certs')

  // Create build record (pending upload)
  await env.DB.prepare(`
    INSERT INTO builds (id, status, platform, submitted_at)
    VALUES (?, 'pending_upload', ?, ?)
  `).bind(buildId, platform, Date.now()).run()

  return Response.json({
    buildId,
    uploadUrls: {
      source: sourceUrl,
      certs: certsUrl,
    },
  })
}

// Step 2: Client uploads directly to R2 via presigned URLs
// (bypasses Worker size limits)

// Step 3: Client confirms upload
async function handleBuildConfirm(request: Request, env: Env) {
  const { buildId } = await request.json()

  // CRITICAL BUG: No verification files exist in R2
  // Client can confirm without uploading, workers get empty jobs

  // MISSING: Check R2 for source file
  // const sourceExists = await env.STORAGE.head(`builds/${buildId}/source.zip`)
  // if (!sourceExists) {
  //   return new Response('Source file not uploaded', { status: 400 })
  // }

  // MISSING: Verify build is in correct state
  // const build = await env.DB.prepare('SELECT status FROM builds WHERE id = ?').bind(buildId).first()
  // if (!build || build.status !== 'pending_upload') {
  //   return new Response('Invalid build state', { status: 400 })
  // }

  // Update build status to pending
  await env.DB.prepare(`
    UPDATE builds SET status = 'pending' WHERE id = ?
  `).bind(buildId).run()

  // Enqueue build
  const queueId = env.QUEUE.idFromName('global')
  const queue = env.QUEUE.get(queueId)
  await queue.enqueue(buildId)

  return Response.json({ status: 'queued' })
}
```

### 6. Worker Polling

```typescript
async function handleWorkerPoll(request: Request, env: Env) {
  const url = new URL(request.url)
  const workerId = url.searchParams.get('worker_id')

  if (!workerId) {
    return new Response('worker_id required', { status: 400 })
  }

  // MISSING: Verify worker exists
  // const worker = await env.DB.prepare('SELECT * FROM workers WHERE id = ?').bind(workerId).first()
  // if (!worker) {
  //   return new Response('Worker not found', { status: 404 })
  // }

  // Update last_seen_at
  await env.DB.prepare(`
    UPDATE workers SET last_seen_at = ? WHERE id = ?
  `).bind(Date.now(), workerId).run()

  // Get next job from Durable Object queue
  const queueId = env.QUEUE.idFromName('global')
  const queue = env.QUEUE.get(queueId)

  const build = await queue.assignToWorker(workerId)

  if (!build) {
    return Response.json({ job: null })
  }

  // Generate presigned download URLs
  const sourceUrl = await env.STORAGE.sign(`builds/${build.id}/source.zip`, {
    method: 'GET',
    expiresIn: 3600,
  })

  const certsUrl = build.certs_path
    ? await env.STORAGE.sign(`builds/${build.id}/certs.zip`, { method: 'GET', expiresIn: 3600 })
    : null

  return Response.json({
    job: {
      id: build.id,
      platform: build.platform,
      source_url: sourceUrl,
      certs_url: certsUrl,
    },
  })
}
```

### 7. Missing: Result Upload Handler

```typescript
// NOT IN PLAN - Critical for build completion
async function handleResultUpload(request: Request, env: Env) {
  const url = new URL(request.url)
  const buildId = url.searchParams.get('build_id')
  const workerId = url.searchParams.get('worker_id')
  const success = url.searchParams.get('success') === 'true'

  // Verify worker owns this build
  const build = await env.DB.prepare('SELECT * FROM builds WHERE id = ?').bind(buildId).first()
  if (!build || build.worker_id !== workerId) {
    return new Response('Unauthorized', { status: 403 })
  }

  if (success) {
    // Generate upload URL for result
    const resultUrl = await env.STORAGE.sign(`builds/${buildId}/result.ipa`, {
      method: 'PUT',
      expiresIn: 3600,
    })
    return Response.json({ uploadUrl: resultUrl })
  } else {
    // Mark build as failed
    const errorMessage = url.searchParams.get('error') || 'Build failed'
    await env.DB.prepare(`
      UPDATE builds SET status = 'failed', error_message = ?, completed_at = ?
      WHERE id = ?
    `).bind(errorMessage, Date.now(), buildId).run()

    // Notify queue
    const queueId = env.QUEUE.idFromName('global')
    const queue = env.QUEUE.get(queueId)
    await queue.complete(buildId)

    return Response.json({ status: 'failed' })
  }
}
```

### 8. Missing: Heartbeat Handler

```typescript
// NOT IN PLAN - Critical for detecting dead workers
async function handleHeartbeat(request: Request, env: Env) {
  const { buildId, workerId, progress } = await request.json()

  // Verify ownership
  const build = await env.DB.prepare('SELECT worker_id FROM builds WHERE id = ?').bind(buildId).first()
  if (!build || build.worker_id !== workerId) {
    return new Response('Unauthorized', { status: 403 })
  }

  // Update heartbeat
  const timestamp = Date.now()
  await env.DB.prepare(`
    UPDATE builds SET last_heartbeat_at = ? WHERE id = ?
  `).bind(timestamp, buildId).run()

  return Response.json({ status: 'ok', timestamp })
}
```

### 9. Missing: Stale Build Cleanup (Cron Trigger)

```typescript
// Scheduled trigger to clean up stale builds
export default {
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext) {
    const HEARTBEAT_TIMEOUT = 5 * 60 * 1000 // 5 minutes
    const staleThreshold = Date.now() - HEARTBEAT_TIMEOUT

    // Find stale assigned builds
    const staleBuilds = await env.DB.prepare(`
      SELECT id, worker_id, retry_count, max_retries
      FROM builds
      WHERE status = 'assigned'
      AND (last_heartbeat_at IS NULL OR last_heartbeat_at < ?)
      AND started_at < ?
    `).bind(staleThreshold, staleThreshold).all()

    for (const build of staleBuilds.results) {
      if (build.retry_count < build.max_retries) {
        // Requeue
        await env.DB.prepare(`
          UPDATE builds
          SET status = 'pending', worker_id = NULL, retry_count = retry_count + 1
          WHERE id = ?
        `).bind(build.id).run()

        // Re-enqueue in DO
        const queueId = env.QUEUE.idFromName('global')
        const queue = env.QUEUE.get(queueId)
        await queue.enqueue(build.id)
      } else {
        // Max retries exceeded
        await env.DB.prepare(`
          UPDATE builds
          SET status = 'failed', error_message = 'Max retries exceeded', completed_at = ?
          WHERE id = ?
        `).bind(Date.now(), build.id).run()
      }
    }
  }
}

// wrangler.toml:
// [triggers]
// crons = ["* * * * *"]  # Every minute
```

---

## DRY Opportunities

### 1. Presigned URL Generation
Same pattern repeated for source, certs, result. Extract:
```typescript
async function generateSignedUrl(
  env: Env,
  buildId: string,
  type: 'source' | 'certs' | 'result',
  method: 'GET' | 'PUT',
  expiresIn = 3600
): Promise<string> {
  const extension = type === 'result' ? 'ipa' : 'zip'
  const key = `builds/${buildId}/${type}.${extension}`
  return env.STORAGE.sign(key, { method, expiresIn })
}
```

### 2. Build Status Updates
Same D1 update pattern everywhere. Extract:
```typescript
async function updateBuildStatus(
  env: Env,
  buildId: string,
  status: string,
  updates: Record<string, unknown> = {}
): Promise<void> {
  const fields = ['status = ?']
  const values = [status]
  for (const [key, value] of Object.entries(updates)) {
    fields.push(`${key} = ?`)
    values.push(value)
  }
  values.push(buildId)
  await env.DB.prepare(`UPDATE builds SET ${fields.join(', ')} WHERE id = ?`)
    .bind(...values).run()
}
```

### 3. Worker Verification
Same ownership check in heartbeat, upload, etc. Extract:
```typescript
async function verifyWorkerOwnsBuild(
  env: Env,
  buildId: string,
  workerId: string
): Promise<Build | null> {
  const build = await env.DB.prepare('SELECT * FROM builds WHERE id = ?').bind(buildId).first()
  if (!build || build.worker_id !== workerId) return null
  return build
}
```

---

## Migration Strategy

### Phase 1: Setup Infrastructure
1. Create Cloudflare account + Workers plan
2. Create D1 database: `wrangler d1 create expo-builds`
3. Create R2 bucket: `wrangler r2 bucket create expo-free-agent-builds`
4. Apply schema to D1: `wrangler d1 execute expo-builds --file=schema.sql`

### Phase 2: Port Core Logic
1. Create `packages/controller-cf/` directory
2. Port database layer to D1 queries
3. Implement Durable Object queue
4. Implement Workers route handlers
5. Update file storage to use R2

### Phase 3: Update Clients
1. CLI: Update to use presigned URL upload flow
2. Worker: Update polling to handle presigned download URLs
3. Menu bar app: No changes (uses same API)

### Phase 4: Testing
1. Deploy to Workers dev environment
2. Test build submission -> queue -> polling -> completion
3. Load test Durable Object (verify <1000 req/s limit)
4. Test large file uploads (presigned URLs)

### Phase 5: Cutover
1. Update DNS to point to Workers
2. Run both stacks in parallel for 24h
3. Verify metrics match
4. Decommission old server

## Cost Analysis

**Current (CapRover):**
- Server: $10-50/month (VPS)
- Storage: Included

**Cloudflare Workers:**
- Workers: $5/month (10M requests)
- D1: $5/month (5GB storage)
- R2: $0.015/GB stored + $0.36/million read requests
- Durable Objects: $0.15/million requests + $0.20/GB-month storage
- **Estimated: $15-25/month** for moderate usage

**Break-even:** ~100 builds/day

**Hidden costs not in plan:**
- R2 Class A operations (writes): $4.50/million
- D1 row writes: $0.75/million
- Egress for large IPA files (100MB+): Watch closely

## Risk Assessment

### Critical Risk (ADDED)
- **Queue state loss:** DO eviction loses all in-progress assignments
  - Mitigation: D1 write-through for all state changes
  - Mitigation: Cron job to reconcile DO state with D1

- **Build data loss on failed transaction:** Current assignToWorker mutates before commit
  - Mitigation: Copy-on-write pattern, only modify after success

- **Security holes:** Timing attacks, missing auth on presigned URLs
  - Mitigation: Constant-time comparison, ownership verification

### High Risk
- **Durable Object bottleneck:** Single instance = 1000 req/s limit
  - Mitigation: Shard queue by platform (ios-queue, android-queue)

- **30s timeout on uploads:** Large source zips exceed timeout
  - Mitigation: Presigned URLs (implemented in plan)

### Medium Risk
- **D1 eventual consistency:** Multi-region writes
  - Mitigation: Use single-region for writes

- **R2 egress costs:** Large build results downloaded frequently
  - Mitigation: Monitor usage, add CDN caching

### Low Risk
- **Migration complexity:** Full rewrite
  - Mitigation: Phased rollout, parallel stacks

## Cloudflare-Specific Gotchas

### 1. Durable Object Limits
- 1000 req/s per DO instance
- 128MB memory limit
- State storage: 50 items/transaction, 128KB/value
- **Plan assumes single global queue - will hit limits fast**

### 2. D1 Limits
- 500MB per database (Free), 10GB (Paid)
- 10ms query limit (complex queries fail)
- No streaming results
- **build_logs table will hit limits without TTL**

### 3. Workers Limits
- 30s request timeout (Paid), 10ms CPU time
- 128MB memory
- 1MB request body (without streaming)
- **Presigned URLs mandatory for file uploads**

### 4. R2 Gotchas
- No server-side encryption at rest
- Presigned URLs: 7-day max expiry
- List operations return max 1000 objects
- **No atomic multipart upload abort - orphaned parts cost money**

### 5. Cold Starts
- Durable Objects: ~50ms cold start
- Workers: ~5ms cold start
- **First poll after idle period adds latency**

---

## Open Questions

1. ~~Queue sharding strategy:~~ **ANSWERED: Shard by platform mandatory**
2. ~~Heartbeat storage:~~ **ANSWERED: D1 (DO state too volatile)**
3. Log streaming: D1 or separate service (Logflare)?
4. Statistics: Real-time from Durable Object or batch from D1?
5. Build result retention: TTL on R2 objects?
6. **NEW: How to handle DO eviction mid-build?**
7. **NEW: Retry strategy for failed builds?**
8. **NEW: Auth model for presigned URLs?**

## File Structure

```
packages/controller-cf/
   src/
      index.ts              # Main Worker entry
      routes/
         builds.ts         # Build submission/status
         workers.ts        # Worker registration/polling
         diagnostics.ts    # Health checks
      queue.ts              # Durable Object
      db/
         schema.sql        # D1 schema
         queries.ts        # Prepared statements
      storage/
         r2.ts             # R2 helpers
      middleware/
         auth.ts           # API key validation
      utils/
         signed-urls.ts    # ADDED: Presigned URL helpers
         status.ts         # ADDED: Build status transitions
   wrangler.toml             # Cloudflare config
   package.json
   tsconfig.json
```

## Next Steps

1. ~~Review this plan for architectural flaws~~ **DONE - 8 critical issues found**
2. Validate Durable Object limits match use case
3. Prototype queue coordination logic **with D1 write-through**
4. Estimate actual costs with real build sizes
5. Decide: Migrate now or wait for scale?
6. **NEW: Design auth model for presigned URLs**
7. **NEW: Implement stale build cleanup cron**
8. **NEW: Add retry logic with exponential backoff**

---

## Summary of Code Review Findings

| Category | Count | Severity |
|----------|-------|----------|
| Critical Security | 2 | Must fix before production |
| Critical Data Loss | 3 | Must fix before production |
| Critical Missing Features | 3 | Must implement |
| DRY Violations | 3 | Refactor recommended |
| Missing Error Handling | 4 | Should fix |
| Scalability Concerns | 2 | Monitor in production |

**Recommendation:** Do NOT deploy this plan as-is. The queue state loss bug (CRITICAL-1, CRITICAL-2) will cause data loss in production. The security holes (CRITICAL-4, CRITICAL-5) are exploitable. Implement fixes before any production deployment.
