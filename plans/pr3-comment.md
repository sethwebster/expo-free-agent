# Code Review: Build Statistics with CPU Tracking

**Files Changed:** 14 files, +533/-18 lines

---

## :red_circle: Critical Issues

### 1. Missing Input Validation on CPU Snapshot Data

**Location:** `packages/controller/src/api/builds/index.ts:457-467`

The telemetry endpoint inserts CPU snapshots without validating payload structure. While `requireWorkerAccess` verifies the worker, actual data values (`cpu_percent`, `memory_mb`) are inserted without sanitization or bounds checking.

```typescript
// Current code - no validation on data values
if (type === 'cpu_snapshot' && data?.cpu_percent !== undefined && data?.memory_mb !== undefined) {
  db.addCpuSnapshot({
    build_id: buildId,
    timestamp: Date.now(),
    cpu_percent: data.cpu_percent,  // Could be NaN, Infinity, negative, or massive
    memory_mb: data.memory_mb,       // Same issue
  });
}
```

**Impact:**
- Data integrity issues: Workers could send `NaN`, `Infinity`, or extreme values
- Stats calculation (`getTotalCpuCycles`) would return corrupted results
- No rate limiting = potential DB spam (5-second interval is client-enforced only)

**Fix:** Add bounds validation before insert:
```typescript
const cpuPercent = Number(data.cpu_percent);
const memoryMb = Number(data.memory_mb);

if (!Number.isFinite(cpuPercent) || cpuPercent < 0 || cpuPercent > 1000) {
  fastify.log.warn(`Invalid cpu_percent: ${data.cpu_percent}`);
  return reply.send({ status: 'ok' });
}
if (!Number.isFinite(memoryMb) || memoryMb < 0 || memoryMb > 1_000_000) {
  fastify.log.warn(`Invalid memory_mb: ${data.memory_mb}`);
  return reply.send({ status: 'ok' });
}
```

---

### 2. Unbounded Database Growth - No Cleanup Strategy

**Location:** `packages/controller/src/db/schema.sql:40-47`, `Database.ts`

The `cpu_snapshots` table grows unbounded:
- 12 snapshots/minute
- 5-minute build = 60 snapshots
- 1 million builds = ~60 million rows (~60GB)

No automatic cleanup, retention policy, or index on timestamp for efficient purging.

**Impact:** SQLite performance degradation, disk exhaustion, query slowdowns.

**Fix:** Add cleanup method:
```typescript
purgeCpuSnapshotsOlderThan(daysOld: number): number {
  const cutoff = Date.now() - (daysOld * 24 * 60 * 60 * 1000);
  const stmt = this.db.prepare('DELETE FROM cpu_snapshots WHERE timestamp < ?');
  return stmt.run(cutoff).changes;
}
```

---

### 3. SQL Aggregation Performance Issue

**Location:** `packages/controller/src/db/Database.ts:362-378`

`getTotalCpuCycles()` performs full table scan with `AVG()` on potentially millions of rows, called on every stats request.

**Impact:** O(n) query where n = total snapshots ever recorded.

**Fix:** Consider pre-computed aggregates or add warning comment about scale limits.

---

## :yellow_circle: Architecture Concerns

### 4. Stats Endpoint Has Mixed Real/Demo Data Logic

**Location:** `packages/controller/src/api/stats/index.ts:96-139`

Two completely separate code paths with same calculation duplicated. Demo values don't match real calculation formula.

**Fix:** Extract constants and calculation into shared utility.

---

### 5. Swift Actor Lacks Error Recovery for Telemetry Failures

**Location:** `free-agent/Sources/BuildVM/VMResourceMonitor.swift:140-169`

When telemetry POST fails, code logs but continues silently. No exponential backoff or circuit breaker.

**Impact:** If controller is unreachable, worker spams failed requests every 5 seconds.

**Fix:** Add circuit breaker pattern:
```swift
private var consecutiveFailures = 0
private let maxConsecutiveFailures = 5

// Stop trying after 5 consecutive failures
guard consecutiveFailures < maxConsecutiveFailures else { return }
```

---

### 6. NetworkStats Interface Duplicated Across 5 Files

**Location:**
- `packages/controller/src/api/stats/index.ts:8-14`
- `packages/landing-page/src/contexts/NetworkContext.tsx:5-12`
- `packages/landing-page/src/hooks/useNetworkStats.ts:3-10`
- `packages/landing-page/src/hooks/useNetworkStatsFromSync.ts:8-15`
- `packages/landing-page/src/services/networkSync.ts` (implicit)

**Impact:** Future field additions require changes in 5 files. Risk of drift.

**Fix:** Create `packages/landing-page/src/types/stats.ts` and import from single source.

---

## :green_circle: DRY Opportunities

### 7. Demo Stats Calculation Duplicated 5 Times

Same `AVG_BUILD_TIME_MS` / `AVG_CPU_PERCENT` calculation appears in 5 locations. Extract to shared utility function.

### 8. Format Functions in App.tsx Should Be Extracted

`formatBuildTime()` and `formatCpuCycles()` are pure utilities that clutter App.tsx. Move to `utils/formatters.ts`.

---

## :blue_circle: Maintenance Improvements

### 9. No Tests for New Database Methods

Four new methods with zero test coverage:
- `addCpuSnapshot()`
- `getCpuSnapshots()`
- `getTotalBuildTimeMs()`
- `getTotalCpuCycles()`

**Fix:** Add unit tests covering edge cases (empty table, NULL values, overflow).

---

### 10. Swift `process.waitUntilExit()` Blocks Thread

**Location:** `free-agent/Sources/BuildVM/VMResourceMonitor.swift:77, 108`

`waitUntilExit()` is synchronous blocking inside async actor method.

**Fix:** Use `Process` with async/await bridge via `terminationHandler`.

---

### 11. CPU_SNAPSHOT_IMPLEMENTATION.md Should Not Be Committed

Implementation guide with "Status: IMPLEMENTED" markers. Will become stale.

**Recommendation:** Delete or merge relevant parts into ARCHITECTURE.md.

---

## :white_circle: Nitpicks

- **"CPU Cycles" is a misnomer** - Actually measuring CPU-seconds, not processor cycles
- **Removed test target from Package.swift** - Makes adding tests harder
- **5-second interval not configurable** - Extract to constant

---

## :white_check_mark: Strengths

1. **Proper actor isolation**: `VMResourceMonitor` correctly uses Swift actors for thread safety
2. **Good index design**: `idx_cpu_snapshots_build` and `idx_cpu_snapshots_timestamp` will support common queries efficiently
3. **Graceful degradation**: Monitor continues operating even when telemetry sends fail
4. **Clean integration**: Worker integration is minimal (24 lines in TartVMManager)
5. **Foreign key constraint**: `cpu_snapshots.build_id` has FK to `builds(id)` ensuring referential integrity
6. **Correct stats caching**: Reuses existing 10-second cache TTL pattern

---

## Verdict

**Request Changes** - The PR has good intentions but needs fixes before merge:

| Priority | Issue |
|----------|-------|
| **MUST FIX** | Input validation on CPU snapshot data |
| **MUST FIX** | Add database cleanup strategy |
| **SHOULD FIX** | Extract duplicated NetworkStats interface |
| **SHOULD FIX** | Add basic test coverage for new DB methods |

The core functionality is sound and follows project patterns. Once validation and cleanup issues are addressed, this is ready to merge.

---

## Unresolved Questions

- Is 5-second polling interval appropriate? (bandwidth vs granularity tradeoff)
- Should we add a `--no-telemetry` flag for workers on metered connections?
- CPU cycles formula: is this the right calculation for the landing page's "impressive number"?
