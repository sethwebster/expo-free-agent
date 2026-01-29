# Code Review: PR #3 - Build Statistics with CPU Tracking

**Reviewer:** Claude (Opus 4.5)
**Date:** 2026-01-28
**PR:** Stats here are wrong. (vibe-kanban)
**Files Changed:** 14 files, +533/-18 lines

---

## Summary

This PR adds build statistics tracking including:
- New `cpu_snapshots` table for CPU/memory telemetry
- `VMResourceMonitor` Swift actor for process monitoring
- Stats API enhancements for total build time and CPU cycles
- Landing page display of new metrics

---

## Critical Issues

### 1. MISSING AUTHENTICATION ON CPU SNAPSHOT INSERTION

**Location:** `packages/controller/src/api/builds/index.ts:457-467`

**Problem:** The telemetry endpoint inserts CPU snapshots into the database without validating the `data` payload structure. While `requireWorkerAccess` verifies the worker, the actual data values (`cpu_percent`, `memory_mb`) are inserted without sanitization or bounds checking.

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

**Solution:**
```typescript
if (type === 'cpu_snapshot' && data?.cpu_percent !== undefined && data?.memory_mb !== undefined) {
  const cpuPercent = Number(data.cpu_percent);
  const memoryMb = Number(data.memory_mb);

  // Validate bounds
  if (!Number.isFinite(cpuPercent) || cpuPercent < 0 || cpuPercent > 1000) {
    fastify.log.warn(`Invalid cpu_percent: ${data.cpu_percent}`);
    return reply.send({ status: 'ok' }); // Silently ignore invalid data
  }
  if (!Number.isFinite(memoryMb) || memoryMb < 0 || memoryMb > 1_000_000) {
    fastify.log.warn(`Invalid memory_mb: ${data.memory_mb}`);
    return reply.send({ status: 'ok' });
  }

  db.addCpuSnapshot({
    build_id: buildId,
    timestamp: Date.now(),
    cpu_percent: cpuPercent,
    memory_mb: memoryMb,
  });
}
```

---

### 2. UNBOUNDED DATABASE GROWTH - NO CLEANUP STRATEGY

**Location:** `packages/controller/src/db/schema.sql:40-47`, `Database.ts`

**Problem:** The `cpu_snapshots` table grows unbounded. Per the PR's own documentation:
- 12 snapshots/minute
- 5-minute build = 60 snapshots
- 1 million builds = ~60 million rows (~60GB)

There is no:
- Automatic cleanup/archival
- Retention policy enforcement
- Index on `timestamp` for efficient purging

**Impact:**
- SQLite performance degradation over time
- Disk exhaustion on controller host
- Query slowdowns in `getTotalCpuCycles()` which scans entire table

**Solution:**
1. Add a cleanup method in `DatabaseService`:
```typescript
purgeCpuSnapshotsOlderThan(daysOld: number): number {
  const cutoff = Date.now() - (daysOld * 24 * 60 * 60 * 1000);
  const stmt = this.db.prepare('DELETE FROM cpu_snapshots WHERE timestamp < ?');
  const result = stmt.run(cutoff);
  return result.changes;
}
```

2. Call periodically (e.g., daily cron or on controller startup)

3. The `idx_cpu_snapshots_timestamp` index is correctly added in schema.sql - good.

---

### 3. SQL AGGREGATION PERFORMANCE ISSUE

**Location:** `packages/controller/src/db/Database.ts:362-378`

**Problem:** `getTotalCpuCycles()` performs a full table scan with `AVG()` on potentially millions of rows, called on every stats request.

```typescript
getTotalCpuCycles(): number {
  const stmt = this.db.prepare(`
    SELECT AVG(cpu_percent) as avg_cpu, COUNT(*) as snapshot_count
    FROM cpu_snapshots  // <-- Full table scan
  `);
  // ...
}
```

**Impact:** As the table grows, this query will become progressively slower (O(n) where n = total snapshots ever recorded).

**Solution:** Pre-compute and cache aggregates:

Option A: Materialized view pattern (compute on insert):
```typescript
// Add to schema.sql
CREATE TABLE IF NOT EXISTS cpu_stats_cache (
  id INTEGER PRIMARY KEY CHECK (id = 1),  -- Singleton row
  total_cpu_seconds REAL DEFAULT 0,
  total_snapshots INTEGER DEFAULT 0,
  last_updated INTEGER
);

// Update on each insert
addCpuSnapshot(snapshot: Omit<CpuSnapshot, 'id'>) {
  // Insert snapshot...

  // Update running totals
  this.db.prepare(`
    UPDATE cpu_stats_cache
    SET total_cpu_seconds = total_cpu_seconds + (? / 100 * 5),  -- 5s interval
        total_snapshots = total_snapshots + 1,
        last_updated = ?
    WHERE id = 1
  `).run(snapshot.cpu_percent, Date.now());
}
```

Option B: Cache with TTL in stats endpoint (simpler, already has 10s cache):
```typescript
// Already cached for 10s, just add warning comment
// Note: This query is O(n) on cpu_snapshots table. Consider migration to
// pre-computed aggregates if table exceeds 1M rows.
```

---

## Architecture Concerns

### 4. STATS ENDPOINT HAS MIXED REAL/DEMO DATA LOGIC

**Location:** `packages/controller/src/api/stats/index.ts:96-139`

**Problem:** The stats endpoint has two completely separate code paths:
1. Real data path (lines 66-103) - uses actual DB queries
2. Demo data path (lines 106-142) - generates fake numbers

The new `totalBuildTimeMs` and `totalCpuCycles` fields are added to BOTH paths, but:
- Real path: Calls `db.getTotalBuildTimeMs()` and `db.getTotalCpuCycles()`
- Demo path: Calculates fake values using hardcoded assumptions

```typescript
// Demo path (lines 132-136)
const AVG_BUILD_TIME_MS = 300_000;
const AVG_CPU_PERCENT = 40;
const totalBuildTimeMs = totalBuilds * AVG_BUILD_TIME_MS;
const totalCpuCycles = (totalBuilds * AVG_BUILD_TIME_MS / 1000) * (AVG_CPU_PERCENT / 100);
```

**Impact:**
- DRY violation: Same calculation duplicated in 4 places (stats API, 2 hooks, 1 sync service)
- Demo values don't match real calculation formula
- Confusing when debugging ("why are my stats wrong?")

**Solution:** Extract constants and calculation into shared utility:
```typescript
// packages/controller/src/utils/statsHelpers.ts
export const DEMO_AVG_BUILD_TIME_MS = 300_000;
export const DEMO_AVG_CPU_PERCENT = 40;

export function computeDemoCpuMetrics(totalBuilds: number) {
  return {
    totalBuildTimeMs: totalBuilds * DEMO_AVG_BUILD_TIME_MS,
    totalCpuCycles: (totalBuilds * DEMO_AVG_BUILD_TIME_MS / 1000) * (DEMO_AVG_CPU_PERCENT / 100),
  };
}
```

---

### 5. SWIFT ACTOR LACKS ERROR RECOVERY FOR TELEMETRY FAILURES

**Location:** `free-agent/Sources/BuildVM/VMResourceMonitor.swift:140-169`

**Problem:** When telemetry POST fails, the code logs but continues silently. This is acceptable for transient failures, but:
1. No exponential backoff on repeated failures
2. No circuit breaker to stop hammering a dead controller
3. HTTP errors logged to stdout only (no structured logging)

```swift
private func sendCpuSnapshot(cpuPercent: Double, memoryMB: Double) async {
  // ...
  do {
    let (_, response) = try await URLSession.shared.data(for: request)
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
      print("Failed to send CPU snapshot: HTTP \(httpResponse.statusCode)")  // Just prints
    }
  } catch {
    print("Error sending CPU snapshot: \(error)")  // Just prints
  }
}
```

**Impact:**
- If controller is unreachable, worker spams failed requests every 5 seconds
- No visibility into telemetry health from worker UI
- Logs are unstructured (hard to grep/parse)

**Solution:**
```swift
private var consecutiveFailures = 0
private let maxConsecutiveFailures = 5

private func sendCpuSnapshot(cpuPercent: Double, memoryMB: Double) async {
  guard consecutiveFailures < maxConsecutiveFailures else {
    // Circuit breaker: stop trying after 5 consecutive failures
    return
  }

  // ... existing send logic ...

  do {
    let (_, response) = try await URLSession.shared.data(for: request)
    if let httpResponse = response as? HTTPURLResponse {
      if httpResponse.statusCode == 200 {
        consecutiveFailures = 0  // Reset on success
      } else {
        consecutiveFailures += 1
        // Consider: emit structured log or notification
      }
    }
  } catch {
    consecutiveFailures += 1
  }
}
```

---

### 6. INTERFACE TYPE DUPLICATED ACROSS 5 FILES

**Location:**
- `packages/controller/src/api/stats/index.ts:8-14`
- `packages/landing-page/src/contexts/NetworkContext.tsx:5-12`
- `packages/landing-page/src/hooks/useNetworkStats.ts:3-10`
- `packages/landing-page/src/hooks/useNetworkStatsFromSync.ts:8-15`
- `packages/landing-page/src/services/networkSync.ts` (implicit)

**Problem:** The `NetworkStats` interface is copy-pasted across all these files. When adding `totalBuildTimeMs` and `totalCpuCycles`, the PR correctly updated all 5 locations, but this is a maintenance nightmare.

```typescript
// Duplicated in 4+ places:
interface NetworkStats {
  nodesOnline: number;
  buildsQueued: number;
  activeBuilds: number;
  buildsToday: number;
  totalBuilds: number;
  totalBuildTimeMs: number;  // Added in each file
  totalCpuCycles: number;    // Added in each file
}
```

**Impact:**
- Future field additions require changes in 5 files
- Risk of drift if one file is missed
- Violates DRY principle

**Solution:** Create shared types package or export from single source:
```typescript
// packages/landing-page/src/types/stats.ts
export interface NetworkStats {
  nodesOnline: number;
  buildsQueued: number;
  activeBuilds: number;
  buildsToday: number;
  totalBuilds: number;
  totalBuildTimeMs: number;
  totalCpuCycles: number;
}

// All other files import from here:
import { NetworkStats } from '../types/stats';
```

---

## DRY Opportunities

### 7. DEMO STATS CALCULATION DUPLICATED 4 TIMES

**Location:**
- `packages/controller/src/api/stats/index.ts:132-136`
- `packages/landing-page/src/hooks/useNetworkStats.ts:33-36`
- `packages/landing-page/src/hooks/useNetworkStats.ts:74-77`
- `packages/landing-page/src/hooks/useNetworkStatsFromSync.ts:45-49`
- `packages/landing-page/src/hooks/useNetworkStatsFromSync.ts:113-117`

**Problem:** The same calculation appears 5 times:
```typescript
const AVG_BUILD_TIME_MS = 300_000;
const AVG_CPU_PERCENT = 40;
const totalBuildTimeMs = totalBuilds * AVG_BUILD_TIME_MS;
const totalCpuCycles = (totalBuilds * AVG_BUILD_TIME_MS / 1000) * (AVG_CPU_PERCENT / 100);
```

**Solution:** Extract to shared utility function (see item #4).

---

### 8. FORMAT FUNCTIONS IN APP.TSX SHOULD BE EXTRACTED

**Location:** `packages/landing-page/src/App.tsx:8-42`

**Problem:** `formatBuildTime()` and `formatCpuCycles()` are defined inline in App.tsx. These are pure utility functions that:
- Have no dependencies on React
- Could be reused elsewhere
- Clutter the main App component file

**Solution:** Move to `packages/landing-page/src/utils/formatters.ts`:
```typescript
export function formatBuildTime(ms: number): string { /* ... */ }
export function formatCpuCycles(cycles: number): string { /* ... */ }
```

---

## Maintenance Improvements

### 9. NO TESTS FOR NEW DATABASE METHODS

**Location:** `packages/controller/src/db/Database.ts:323-378`

**Problem:** Three new methods added with zero test coverage:
- `addCpuSnapshot()`
- `getCpuSnapshots()`
- `getTotalBuildTimeMs()`
- `getTotalCpuCycles()`

**Impact:**
- Regressions will not be caught
- Edge cases untested (empty table, NULL values, overflow)
- Refactoring is risky

**Solution:** Add unit tests:
```typescript
describe('CPU Snapshots', () => {
  it('addCpuSnapshot inserts valid data', () => { /* ... */ });
  it('getCpuSnapshots returns ordered by timestamp', () => { /* ... */ });
  it('getTotalBuildTimeMs handles no completed builds', () => { /* ... */ });
  it('getTotalCpuCycles handles no snapshots', () => { /* ... */ });
  it('getTotalCpuCycles handles NULL avg_cpu', () => { /* ... */ });
});
```

---

### 10. SWIFT PROCESS.WAITUNTILEXIT() BLOCKS THREAD

**Location:** `free-agent/Sources/BuildVM/VMResourceMonitor.swift:77, 108`

**Problem:** The `getTartVMPid()` and `getProcessResourceUsage()` methods use `process.waitUntilExit()` which is a synchronous blocking call. Inside an async actor method, this blocks the actor's thread.

```swift
private func getTartVMPid() async throws -> Int32? {
  let process = Process()
  // ...
  try process.run()
  process.waitUntilExit()  // BLOCKS! Bad in async context
  // ...
}
```

**Impact:**
- Actor thread blocked during shell command execution
- Potential deadlock if multiple methods waiting
- Not truly async-safe

**Solution:** Use `Process` with async/await bridge:
```swift
private func runProcess(_ executable: String, args: [String]) async throws -> String {
  return try await withCheckedThrowingContinuation { continuation in
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = args

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    process.terminationHandler = { _ in
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""
      continuation.resume(returning: output)
    }

    do {
      try process.run()
    } catch {
      continuation.resume(throwing: error)
    }
  }
}
```

---

### 11. CPU_SNAPSHOT_IMPLEMENTATION.MD SHOULD NOT BE COMMITTED

**Location:** `CPU_SNAPSHOT_IMPLEMENTATION.md` (149 lines)

**Problem:** This file is an implementation guide/spec that:
- Contains example code (now implemented)
- Has "Status: IMPLEMENTED" markers
- Duplicates information already in code comments and ARCHITECTURE.md

**Impact:**
- Will become stale as code evolves
- Adds maintenance burden
- Not clear if it's documentation or planning artifact

**Recommendation:** Either:
1. Delete it (implementation is done, code is the source of truth), OR
2. Move relevant parts to ARCHITECTURE.md and delete the file

---

## Nitpicks

### 12. INCONSISTENT NAMING: "CPU CYCLES" IS A MISNOMER

**Location:** Throughout PR

**Problem:** The metric is called "CPU Cycles" but it's actually `avg_cpu_percent * total_time_seconds`. Real CPU cycles would be measured in billions of actual processor cycles. This is more accurately "CPU-seconds" or "CPU time".

**Impact:** Misleading terminology, especially for technical users.

**Recommendation:** Consider renaming to `totalCpuSeconds` or adding a comment explaining the metric.

---

### 13. REMOVED TEST TARGET FROM PACKAGE.SWIFT

**Location:** `free-agent/Package.swift`

```diff
-.testTarget(
-    name: "FreeAgentTests",
-    dependencies: ["FreeAgent", "BuildVM", "WorkerCore"]
-)
```

**Problem:** Test target removed with no explanation. Even if no tests exist yet, removing the target makes it harder to add tests later.

**Recommendation:** Keep the test target or add a comment explaining why tests are not feasible.

---

### 14. MAGIC NUMBER: 5-SECOND INTERVAL NOT CONFIGURABLE

**Location:** `free-agent/Sources/BuildVM/VMResourceMonitor.swift:49,57`

**Problem:** The 5-second polling interval is hardcoded in two places.

**Recommendation:** Extract to constant:
```swift
private let pollingInterval: Duration = .seconds(5)
```

---

## Strengths

1. **Proper actor isolation**: `VMResourceMonitor` correctly uses Swift actors for thread safety
2. **Good index design**: `idx_cpu_snapshots_build` and `idx_cpu_snapshots_timestamp` will support common queries efficiently
3. **Graceful degradation**: Monitor continues operating even when telemetry sends fail
4. **Clean integration**: Worker integration is minimal (24 lines in TartVMManager)
5. **Foreign key constraint**: `cpu_snapshots.build_id` has FK to `builds(id)` ensuring referential integrity
6. **Correct stats caching**: Reuses existing 10-second cache TTL pattern
7. **Comprehensive PR description**: Clear explanation of what/why/how

---

## Verdict

**Request Changes** - The PR has good intentions but needs fixes before merge:

1. **MUST FIX**: Input validation on CPU snapshot data (security)
2. **MUST FIX**: Add database cleanup strategy (operational)
3. **SHOULD FIX**: Extract duplicated NetworkStats interface
4. **SHOULD FIX**: Add basic test coverage for new DB methods

The core functionality is sound and the implementation follows project patterns. Once the validation and cleanup issues are addressed, this is ready to merge.

---

## Unresolved Questions

- Is 5-second polling interval appropriate? (bandwidth vs granularity tradeoff)
- Should we add a `--no-telemetry` flag for workers on metered connections?
- CPU cycles formula: is this the right calculation for the landing page's "impressive number"?
