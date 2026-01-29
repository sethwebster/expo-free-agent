# ADR-0009: Migrate Controller from TypeScript to Elixir

**Status:** Accepted

**Date:** 2026-01-29 (Merge commit d409a1f)

## Context

TypeScript/Bun/SQLite controller (v0.1.x) successfully validated core concept but hit fundamental limitations:

### Performance Bottlenecks
- **SQLite single-writer:** Max ~10 builds/second throughput
- **Build assignment race conditions:** Multiple workers could receive same build
- **In-memory queue:** Lost state on crash, required manual restart
- **File buffering:** 500MB memory per build upload/download

### Reliability Issues
- **Race condition:** Build assignment not atomic (SELECT + UPDATE in separate transactions)
- **Queue data loss:** Transient failures removed builds from queue
- **Manual recovery:** Crashes required operator intervention
- **No supervision:** Process failures crashed entire controller

### Concurrency Tests Failing
```
Test: 20 workers compete for 10 builds
Expected: 10 succeed, 10 get "no builds available"
Actual: 12-14 succeed (double assignment)
```

TypeScript cannot solve these without fundamental architecture changes.

## Decision

Migrate controller to **Elixir/Phoenix/PostgreSQL** with OTP supervision.

### Technology Choices

**Elixir/OTP:**
- Erlang VM provides battle-tested concurrency primitives
- OTP supervision trees for automatic crash recovery
- GenServer for serialized queue access
- Pattern matching for readable business logic

**Phoenix Framework:**
- REST API via Phoenix controllers
- Ecto for database access
- Connection pooling (100+ connections vs SQLite single-writer)
- Excellent observability (LiveDashboard)

**PostgreSQL:**
- `SELECT FOR UPDATE SKIP LOCKED` prevents race conditions atomically
- JSON support for build metadata
- Full-text search for logs
- LISTEN/NOTIFY for real-time updates (future)

### Architecture

```
Phoenix Router
  ↓
Controller (request handling)
  ↓
Context Layer (business logic)
  ├─ Builds (build lifecycle)
  ├─ Workers (worker management)
  └─ Diagnostics (monitoring)
  ↓
Ecto Schema (data access)
  ↓
PostgreSQL
```

**OTP Supervision Tree:**
```
Application Supervisor
  ├─ Phoenix Endpoint
  ├─ Ecto Repo
  └─ QueueManager GenServer
```

QueueManager handles queue state recovery from database on startup.

## Consequences

### Positive

#### Performance
- **10x throughput:** 100+ builds/second vs 10/second (PostgreSQL connection pooling)
- **4x faster assignment:** 50ms vs 200ms latency
- **50x memory efficiency:** 10MB per build vs 500MB (streaming file uploads)
- **Concurrent workers:** 100+ workers polling simultaneously without contention

#### Reliability
- **Zero race conditions:** `SELECT FOR UPDATE SKIP LOCKED` guarantees atomicity
- **Automatic recovery:** OTP supervisors restart crashed processes
- **Queue restoration:** QueueManager rebuilds state from database on boot
- **Graceful degradation:** Worker failures don't crash controller

#### Correctness
- **Concurrency test passes:** 20 workers competing for 10 builds → exactly 10 succeed
- **Transaction boundaries:** Multi-step operations atomic (assign + update + log)
- **Error handling:** Transient errors (worker busy) vs permanent errors (build invalid)

### Negative

#### Deployment Complexity
- **PostgreSQL required:** Cannot run controller without database (no in-memory mode)
- **Migration complexity:** Must migrate existing SQLite data or start fresh
- **E2E testing:** Tests must manually start controller (cannot auto-spawn like TypeScript)
- **More moving parts:** Application supervisor + Ecto + Phoenix vs single Bun process

#### Development Experience
- **Learning curve:** Team must learn Elixir/OTP patterns
- **Longer compilation:** Mix compilation slower than Bun transpilation
- **Ecosystem:** Smaller package ecosystem than npm
- **Debugging:** Erlang stack traces different from JavaScript

#### Path Parity
- **23 endpoints to port:** Initial migration only 7/23 compatible
- **Route aliases needed:** TypeScript used `/api/builds/submit`, Elixir uses RESTful `/api/builds`
- **Storage stats missing:** Health endpoint returns empty storage object (vs detailed TypeScript stats)

### Migration Status

**Completed (Merge d409a1f):**
- ✅ Core build lifecycle (submit, assign, upload, download)
- ✅ Worker management (register, poll, heartbeat)
- ✅ Build token authentication
- ✅ Transaction boundaries (zero race conditions)
- ✅ FileStorage module with path traversal protection
- ✅ Concurrency tests (20 workers competing)
- ✅ E2E verification script (`test-e2e-elixir.sh`)
- ✅ Worker token rotation with 90s TTL

**Deferred (Future work):**
- ⏳ Real-time build logs (WebSocket/SSE)
- ⏳ Storage statistics in health endpoint
- ⏳ Admin UI rebuild in LiveView
- ⏳ Background job cleanup (old builds/logs)

## Race Condition Fix

### Before (TypeScript - Broken)
```typescript
// Separate queries, race window between them
const build = await db.query("SELECT * FROM builds WHERE status='pending' LIMIT 1")
if (build) {
  await db.query("UPDATE builds SET status='building', worker_id=? WHERE id=?", [workerId, build.id])
}
```

**Race:** Worker A and Worker B both execute SELECT, both see build #123, both UPDATE it.

### After (Elixir - Correct)
```elixir
Repo.transaction(fn ->
  case Builds.next_pending_for_update() do  # SELECT FOR UPDATE SKIP LOCKED
    nil -> Repo.rollback(:no_pending_builds)
    build ->
      case Builds.assign_to_worker(build, worker_id) do
        {:ok, assigned} -> assigned
        {:error, reason} -> Repo.rollback(reason)
      end
  end
end, timeout: 5_000)
```

**Guarantee:** PostgreSQL row lock ensures only one worker gets build #123. Other workers skip locked row, get different build or nil.

## Performance Benchmarks

**Build assignment latency:**
- TypeScript: 150-250ms (SQLite write lock contention)
- Elixir: 40-60ms (PostgreSQL row locking)

**Concurrent worker polling:**
- TypeScript: Fails at 20+ workers (database locked errors)
- Elixir: Handles 100+ workers (connection pool = 100)

**Memory per build:**
- TypeScript: 500MB (buffers entire file in memory)
- Elixir: 10MB (streams file to disk)

**Queue recovery time:**
- TypeScript: Manual (queue lost on crash)
- Elixir: <1 second (QueueManager rebuilds from database)

## Migration Path for TypeScript Users

**Option 1: Fresh start (recommended)**
1. Deploy Elixir controller
2. Workers register fresh
3. Migrate existing builds via API (if needed)

**Option 2: Data migration**
1. Export SQLite builds table to CSV
2. Import to PostgreSQL via SQL script
3. Regenerate access tokens (security best practice)

**Option 3: Parallel deployment**
1. Run both controllers simultaneously
2. Route new traffic to Elixir
3. TypeScript handles in-flight builds
4. Decommission TypeScript when queue empty

## Alternatives Considered

### Keep TypeScript, Fix Race Conditions

**Approach:** Add distributed locks (Redis) or use PostgreSQL with TypeScript.

**Pros:**
- No language change
- Smaller migration effort
- Keep existing team knowledge

**Cons:**
- Still requires PostgreSQL (main migration effort)
- No automatic crash recovery (still need supervisor)
- Manual concurrency management (vs built-in OTP)
- Less battle-tested patterns

**Rejected:** If migrating to PostgreSQL anyway, get OTP benefits.

### Migrate to Go

**Approach:** Go with PostgreSQL and goroutines for concurrency.

**Pros:**
- Compiled language, fast performance
- Strong typing
- Goroutines for concurrency

**Cons:**
- Manual supervision (vs OTP built-in)
- Less readable than pattern matching
- No LiveView (admin UI requires separate frontend)
- No REPL (vs iex for debugging)

**Rejected:** OTP supervision trees solve crash recovery, Go requires custom solution.

### Migrate to Rust

**Approach:** Rust with Actix/Rocket and async/await.

**Pros:**
- Memory safety guarantees
- Excellent performance
- Strong typing

**Cons:**
- Steeper learning curve than Elixir
- Manual supervision (vs OTP)
- Async ecosystem still maturing
- Longer development time

**Rejected:** OTP provides 30+ years of proven patterns, Rust requires greenfield design.

## Documentation

**Comprehensive docs created:**
- `packages/controller_elixir/ARCHITECTURE.md` - System design
- `packages/controller_elixir/MIGRATION.md` - Migration guide
- `packages/controller_elixir/API.md` - API reference
- `packages/controller_elixir/SETUP.md` - Development setup
- `packages/controller_elixir/TESTING.md` - Test strategy
- `packages/controller_elixir/CONCURRENCY.md` - Race condition fixes
- `docs/architecture/build-pickup-flow.md` - Protocol flow
- `plans/race-condition-fixes-before-after.md` - Before/after comparison

## References

- Migration branch: `seth/elixir-controller-migration`
- Merge commit: `d409a1f`
- E2E verification: `test-e2e-elixir.sh`
- Controller directory: `packages/controller_elixir/`
- Race condition analysis: `plans/race-condition-fixes-before-after.md`
