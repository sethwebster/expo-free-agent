# Elixir Controller Migration Overview

**Status**: Core implementation complete (Week 1-3)
**Target**: Replace TypeScript/Fastify controller with Elixir/Phoenix
**Goal**: Improved concurrency, reliability, performance via OTP

---

## Why Elixir?

### OTP Concurrency
- **Before**: Single-threaded Node.js, 10 concurrent builds max (SQLite bottleneck)
- **After**: BEAM VM handles 100+ concurrent builds via connection pooling
- **Benefits**: Handle peak loads, better resource utilization

### Process Isolation
- **Before**: Crash in any endpoint kills entire server
- **After**: Supervisor restarts failed processes automatically
- **Benefits**: One worker failure doesn't affect others

### Race Condition Prevention
- **Before**: In-memory queue + async DB writes = double assignment possible
- **After**: `SELECT FOR UPDATE SKIP LOCKED` in PostgreSQL transaction
- **Benefits**: Atomic assignment, guaranteed correctness

### Memory Management
- **Before**: Buffer entire file in memory (500MB+ IPAs)
- **After**: Stream files directly to disk
- **Benefits**: Constant memory usage regardless of file size

### Production Readiness
- **Before**: Manual restart, log scraping for monitoring
- **After**: Built-in LiveDashboard, telemetry, metrics
- **Benefits**: Real-time observability, automatic recovery

---

## What Changed

### Technology Stack

| Component | TypeScript | Elixir |
|-----------|-----------|--------|
| Runtime | Node.js 20 | Elixir 1.18 + OTP 28 |
| Framework | Fastify | Phoenix 1.7 |
| Database | SQLite | PostgreSQL 16 |
| ORM | Raw SQL | Ecto 3.13 |
| File Uploads | Multipart streaming | Plug.Upload |
| Queue | In-memory array | GenServer + PubSub |
| Monitoring | None | LiveDashboard + Telemetry |

### Architecture

**Before (TypeScript)**:
```
Express App
├── REST Endpoints
├── SQLite Connection (single)
├── In-memory Queue
└── File Storage (local)
```

**After (Elixir)**:
```
Supervision Tree
├── Endpoint (HTTP)
├── Repo (PostgreSQL Pool)
├── QueueManager (GenServer)
├── HeartbeatMonitor (GenServer)
├── PubSub (Phoenix.PubSub)
└── Telemetry
```

### Security Improvements

**API Key Validation**:
- **Before**: `if (key !== apiKey)` (timing attack vulnerable)
- **After**: `Plug.Crypto.secure_compare(key, apiKey)` (constant-time)

**Worker Authentication**:
- **Before**: Basic header check
- **After**: Build ownership validation in transactions

**Path Traversal**:
- **Before**: String manipulation
- **After**: `Path.absname()` + prefix validation

---

## Path Parity Guarantees

**Critical**: All TypeScript paths preserved via route aliases.

### Maintained Paths

| TypeScript Path | Elixir Path | Status |
|-----------------|-------------|--------|
| `POST /api/builds/submit` | `POST /api/builds/submit` | ✅ Alias to `/api/builds` |
| `GET /api/builds/:id/status` | `GET /api/builds/:id/status` | ✅ Separate endpoint |
| `GET /api/builds/:id/download` | `GET /api/builds/:id/download` | ✅ Defaults to `result` |
| `POST /api/workers/upload` | `POST /api/workers/upload` | ✅ Alias to `/api/workers/result` |
| `GET /api/stats` | `GET /api/stats` | ✅ Public endpoint |
| `GET /health` | `GET /health` | ⏳ Planned |

See [API_COMPATIBILITY.md](./API_COMPATIBILITY.md) for complete mapping.

---

## Deployment Strategy

### Phase 1: Parallel Deployment (Current)

Run both controllers side-by-side:

```
┌──────────────┐
│ Load Balancer│
└──────┬───────┘
       │
       ├─ /api/v2/* → Elixir (port 4000)
       └─ /api/*    → TypeScript (port 3000)
```

**Benefits**:
- Zero-downtime migration
- Gradual worker migration
- Easy rollback
- A/B testing

### Phase 2: Shadowing (Week 4-5)

Dual-write builds to both databases:
- Primary: TypeScript (existing)
- Shadow: Elixir (new)
- Compare results, validate correctness

### Phase 3: Full Cutover (Week 6+)

Switch primary to Elixir:
1. Update load balancer routing
2. Migrate workers to new endpoints
3. Archive TypeScript controller (read-only)

---

## Testing Requirements

### Pre-Deployment Checklist

**Unit Tests** (ExUnit):
- [ ] Build lifecycle (create, assign, complete, fail, cancel)
- [ ] Worker registration and heartbeat
- [ ] Queue assignment atomicity
- [ ] File storage operations
- [ ] Authentication (API key, worker access)

**Integration Tests**:
- [ ] Full build submission → completion flow
- [ ] Worker poll → assignment → upload
- [ ] Concurrent build assignment (no double-assign)
- [ ] Heartbeat timeout detection
- [ ] Build cancellation

**Load Tests**:
- [ ] 100 concurrent build submissions
- [ ] 50 workers polling simultaneously
- [ ] Large file uploads (1GB+)
- [ ] Database connection pool stress

**Compatibility Tests**:
- [ ] Existing CLI can submit builds
- [ ] Existing workers can poll and upload
- [ ] Response formats match TypeScript exactly

### Critical Concurrent Assignment Test

```elixir
test "prevents double assignment under concurrent load" do
  build = build_fixture(status: :pending)

  # Spawn 10 workers simultaneously
  tasks = Enum.map(1..10, fn i ->
    Task.async(fn ->
      worker = worker_fixture(name: "worker-#{i}")
      Builds.assign_to_worker(build, worker.id)
    end)
  end)

  results = Task.await_many(tasks)

  # Exactly 1 success, 9 failures
  assert Enum.count(results, &match?({:ok, _}, &1)) == 1
  assert Enum.count(results, &match?({:error, _}, &1)) == 9
end
```

---

## Rollback Plan

### Emergency Rollback (< 5 minutes)

**If Elixir controller fails in production:**

1. **Revert load balancer routing**:
   ```nginx
   # Nginx config
   location /api/ {
     proxy_pass http://typescript:3000;  # Back to old
   }
   ```

2. **Update workers** (if already migrated):
   ```bash
   # Via worker management API
   curl -X PATCH /api/workers/config \
     -d '{"controller_url": "http://old-controller:3000"}'
   ```

3. **Monitor TypeScript controller**:
   - Check SQLite database integrity
   - Verify queue state
   - Resume pending builds

### Partial Rollback

**If only some workers fail:**

1. Keep Elixir running
2. Downgrade specific workers to TypeScript endpoints
3. Investigate failures in isolation
4. Fix and re-migrate workers individually

### Data Recovery

**If database corruption occurs:**

1. **Stop both controllers**
2. **PostgreSQL backup restore**:
   ```bash
   pg_restore -d expo_controller backup.dump
   ```
3. **SQLite fallback** (if PostgreSQL lost):
   ```bash
   # Export from last SQLite snapshot
   sqlite3 controller.db .dump > fallback.sql
   ```

---

## Migration Checklist

### Pre-Migration

- [ ] Run all TypeScript tests (ensure baseline works)
- [ ] Backup SQLite database
- [ ] Set up PostgreSQL instance
- [ ] Configure Elixir environment variables
- [ ] Run Elixir migrations (`mix ecto.migrate`)
- [ ] Validate API key matches TypeScript

### During Migration

- [ ] Deploy Elixir controller to staging
- [ ] Run smoke tests (see [TESTING.md](./TESTING.md))
- [ ] Load test with realistic traffic
- [ ] Deploy Elixir to production (parallel mode)
- [ ] Migrate 1-2 test workers
- [ ] Monitor for 24 hours

### Post-Migration

- [ ] Migrate remaining workers gradually (10% daily)
- [ ] Compare metrics (build times, success rates)
- [ ] Archive TypeScript controller logs
- [ ] Update documentation
- [ ] Decommission TypeScript controller (after 2 weeks)

---

## Success Metrics

### Performance

- **Build assignment latency**: < 50ms (vs 200ms TypeScript)
- **Concurrent builds**: 100+ (vs 10 TypeScript)
- **Memory per build**: < 10MB (vs 500MB TypeScript)
- **Queue throughput**: 1000 builds/minute (vs 100 TypeScript)

### Reliability

- **Crash recovery**: Automatic (vs manual restart)
- **Double assignment rate**: 0% (vs 0.1% TypeScript)
- **Heartbeat false positives**: < 1% (vs 5% TypeScript)

### Observability

- **Dashboard uptime**: Real-time LiveView (vs manual logs)
- **Metrics collection**: Automatic telemetry (vs none)
- **Alerting**: Built-in (vs custom scripts)

---

## Unresolved Questions

1. **Database migration**: Incremental migration vs full export/import?
2. **Worker downtime**: Acceptable maintenance window for updates?
3. **API versioning**: Keep `/api/v2` or merge into `/api`?
4. **TypeScript retirement**: Archive builds or migrate to PostgreSQL?
5. **S3 storage**: When to migrate from local filesystem?

---

## Resources

- [Architecture Documentation](./ARCHITECTURE.md)
- [API Compatibility Guide](./API_COMPATIBILITY.md)
- [Development Setup](./DEVELOPMENT.md)
- [Testing Guide](./TESTING.md)
- [Deployment Guide](./DEPLOYMENT.md)
- [Troubleshooting](./TROUBLESHOOTING.md)

---

**Migration Owner**: Engineering team
**Timeline**: 6 weeks (3 complete, 3 remaining)
**Status**: Phase 1 complete, ready for testing
