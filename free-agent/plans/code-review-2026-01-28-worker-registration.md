# Code Review: Worker Registration and Polling Flow

**Date**: 2026-01-28
**Reviewer**: Code Review Agent
**Files Reviewed**:
- `/free-agent/Sources/WorkerCore/WorkerService.swift`
- `/free-agent/Sources/WorkerCore/WorkerConfiguration.swift`
- `/free-agent/Sources/FreeAgent/main.swift`
- `/packages/controller/src/api/workers/index.ts`

---

## Summary

The worker registration flow has a critical architectural flaw: **value type semantics combined with async actor isolation create a stale ID race condition**. The bug manifests when:
1. Worker loads configuration with stale/nil workerID
2. Registration succeeds and assigns new ID
3. `configuration.workerID = assignedId` mutates a local copy
4. `configuration.save()` persists to disk but doesn't update the actor's stored copy
5. Subsequent `pollForJob()` reads from the actor's stale `self.configuration`

---

## Critical Issues

### 1. Value Type Mutation in Actor Context (ROOT CAUSE)

**Location**: `WorkerService.swift:135-136`

```swift
// Lines 135-136
configuration.workerID = assignedId
configuration.save()
```

**Problem**: `WorkerConfiguration` is a `struct` (value type). When the actor holds `private var configuration: WorkerConfiguration`, mutating it creates a copy. The `save()` method persists data to disk but:
- The actor's internal `configuration` property is updated (good)
- BUT if any other code path re-initializes from disk or caches the old value, staleness occurs

More critically, examine the initialization flow in `main.swift:159-160`:
```swift
let config = WorkerConfiguration.load()           // Loads from disk (may have stale ID)
workerService = WorkerService(configuration: config)  // Passes copy to actor
```

If `WorkerConfiguration.load()` at line 61-64 generates a new local UUID when `workerID == nil`:
```swift
if config.workerID == nil {
    config.workerID = UUID().uuidString  // LOCAL UUID, not controller-assigned
    config.deviceName = Host.current().localizedName
    config.save()
}
```

This creates the race: The local UUID is saved to disk before the actor even starts. When `registerWorker()` runs, the controller assigns a DIFFERENT ID (`nanoid()` in the controller). The worker updates its in-memory copy, but:
- If the app restarts, it loads the disk file which may have the local UUID (if save timing is unlucky)
- The controller has the nanoid-based ID in its database

**Impact**: Worker polls with wrong ID -> controller returns 404 "Worker not found" -> no builds ever assigned

**Solution**:
```swift
// Option A: Don't generate local ID on load - let registration be the sole source
public static func load() -> WorkerConfiguration {
    guard let data = try? Data(contentsOf: configFileURL),
          let config = try? JSONDecoder().decode(WorkerConfiguration.self, from: data) else {
        return .default
    }
    // REMOVE the local UUID generation - controller is authoritative
    return config
}

// Option B: In WorkerService, after registration succeeds, reload from disk
private func registerWorker() async {
    // ... registration code ...
    if httpResponse.statusCode == 200 {
        if let assignedId = json["id"] as? String {
            var updatedConfig = configuration
            updatedConfig.workerID = assignedId
            updatedConfig.save()
            // CRITICAL: Update actor's stored configuration
            self.configuration = updatedConfig
            // Or reload: self.configuration = WorkerConfiguration.load()
        }
    }
}
```

---

### 2. Non-Atomic Configuration Update

**Location**: `WorkerService.swift:135-136`

```swift
configuration.workerID = assignedId
configuration.save()
```

**Problem**: Two separate operations that can fail independently:
1. In-memory update succeeds
2. `save()` fails silently (returns without throwing)

If save fails, next app launch loads old disk data while current session uses new ID. Session works, but restart breaks.

**Impact**: Intermittent failures that only manifest after app restart

**Solution**:
```swift
public func save() throws {  // Make throwing
    let data = try JSONEncoder().encode(self)
    try data.write(to: Self.configFileURL)
}

// In registerWorker:
do {
    configuration.workerID = assignedId
    try configuration.save()
    print("Registered with ID: \(assignedId)")
} catch {
    // Revert in-memory change if save fails
    configuration.workerID = nil
    print("CRITICAL: Failed to persist worker ID: \(error)")
    // Consider: retry registration on next poll cycle
}
```

---

### 3. Registration Failure Silently Swallowed

**Location**: `WorkerService.swift:143-144, 146-148`

```swift
} else {
    print("Registration failed: \(httpResponse.statusCode)")
}
// ...
} catch {
    print("Failed to register worker: \(error)")
}
```

**Problem**: Registration failure just prints a log. The worker then proceeds to `pollLoop()` which will either:
- Use stale ID from disk -> 404 from controller
- Use nil ID -> "No worker ID found, skipping poll" indefinitely

**Impact**: Worker appears "online" in UI but never receives builds. Silent failure mode.

**Solution**:
```swift
private func registerWorker() async throws {  // Make throwing
    // ... existing code ...
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw WorkerError.registrationFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let assignedId = json["id"] as? String else {
        throw WorkerError.registrationFailed(reason: "Missing ID in response")
    }

    configuration.workerID = assignedId
    try configuration.save()
}

// In start():
public func start() async {
    guard !isActive else { return }

    do {
        try await registerWorker()
    } catch {
        print("FATAL: Registration failed: \(error)")
        // Don't start polling - no valid ID
        return
    }

    isActive = true
    pollingTask = Task { await pollLoop() }
}
```

---

## Architecture Concerns

### 4. Controller Always Generates New ID (Design Flaw)

**Location**: `packages/controller/src/api/workers/index.ts:51`

```typescript
const workerId = nanoid();  // Always generates new ID
```

**Problem**: Controller has no idempotent registration. Every call to `/register` creates a new worker entry. If worker already has a valid ID, it should send it and controller should:
1. Verify ID exists in database
2. Update last_seen_at
3. Return existing ID (or error if ID invalid)

Current flow:
- Worker restarts with saved ID "abc123"
- Calls /register (doesn't send existing ID)
- Controller creates new worker "xyz789"
- Worker saves "xyz789", polls with "xyz789"
- Old worker record "abc123" is orphaned in database

**Impact**: Worker database grows unbounded with orphan records; stats don't persist across restarts

**Solution** (controller-side):
```typescript
fastify.post<{ Body: RegisterBody }>('/register', async (request, reply) => {
    const { name, capabilities, workerId: existingId } = request.body;

    // If worker provides existing ID, verify and re-register
    if (existingId) {
        const existing = db.getWorker(existingId);
        if (existing) {
            db.updateWorkerStatus(existingId, 'idle', Date.now());
            return reply.send({ id: existingId, status: 're-registered' });
        }
        // ID not found - fall through to create new
    }

    const workerId = nanoid();
    // ... create new worker ...
});
```

And worker-side:
```swift
let payload: [String: Any] = [
    "name": configuration.deviceName ?? Host.current().localizedName ?? "Unknown",
    "workerId": configuration.workerID,  // Send existing ID if available
    "capabilities": [ ... ]
]
```

---

### 5. Configuration Loaded Multiple Times (Inconsistency Risk)

**Location**: `main.swift:159`, `main.swift:293`, `main.swift:604`, `main.swift:645`

```swift
// Line 159 - Worker initialization
let config = WorkerConfiguration.load()

// Line 293 - fetchActiveBuilds
let config = WorkerConfiguration.load()

// Line 604 - showSettings
configuration: WorkerConfiguration.load()

// Line 645 - showStatistics
configuration: WorkerConfiguration.load()
```

**Problem**: Configuration is loaded from disk at multiple points. After registration updates the disk file, these subsequent loads will get the new ID. But if the worker service was initialized with the OLD configuration (before registration completed), there's a window of inconsistency.

**Impact**: Minor - mostly affects UI displaying wrong worker ID briefly. The main flow (WorkerService) is the critical path.

**Solution**: Single source of truth pattern:
```swift
@MainActor
class AppDelegate {
    // Single configuration instance
    private var configuration: WorkerConfiguration

    func applicationDidFinishLaunching(_:) {
        configuration = WorkerConfiguration.load()
        // Pass reference, not copy
        workerService = WorkerService(configuration: configuration)
    }

    // Notify on config changes
    func configurationDidUpdate(_ newConfig: WorkerConfiguration) {
        self.configuration = newConfig
        // Update UI, services, etc.
    }
}
```

---

## DRY Opportunities

### 6. Repeated HTTP Request Setup

**Location**: Multiple methods in `WorkerService.swift`

The pattern of building URLRequest with headers repeats in:
- `registerWorker()` lines 98-102
- `unregisterWorker()` lines 157-160
- `pollForJob()` lines 183-187
- `downloadBuildPackage()` lines 311-317
- `uploadBuildResult()` lines 338-344
- `reportJobFailure()` lines 398-404

**Solution**:
```swift
private func makeRequest(url: URL, method: String = "GET") -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")
    if let workerID = configuration.workerID {
        request.setValue(workerID, forHTTPHeaderField: "X-Worker-Id")
    }
    return request
}
```

---

## Maintenance Improvements

### 7. Logging Not Structured

**Location**: Throughout `WorkerService.swift`

All logging uses `print()` with inconsistent formats. For production debugging:

```swift
// Current:
print("Registration failed: \(httpResponse.statusCode)")

// Better:
import os
private let logger = Logger(subsystem: "com.freeagent.worker", category: "service")

logger.error("Registration failed", metadata: ["statusCode": "\(httpResponse.statusCode)"])
```

---

### 8. No Retry Logic for Registration

**Location**: `WorkerService.swift:96-148`

Registration failure is final - no retry. Network blips during startup = worker never works.

**Solution**:
```swift
private func registerWorker() async throws {
    var lastError: Error?
    for attempt in 1...3 {
        do {
            try await attemptRegistration()
            return
        } catch {
            lastError = error
            try? await Task.sleep(for: .seconds(Double(attempt) * 2))  // Backoff
        }
    }
    throw lastError ?? WorkerError.registrationFailed(reason: "Unknown")
}
```

---

## Nitpicks

### 9. Hardcoded Template Image

**Location**: `WorkerService.swift:254`

```swift
let templateImage = job.baseImageId ?? "ghcr.io/sethwebster/expo-free-agent-base:0.1.23"
```

Should come from configuration, not hardcoded fallback.

---

### 10. Force Unwrap After Optional Check

**Location**: `WorkerService.swift:258-259`

```swift
let buildResult = try await vmManager!.executeBuild(
    sourceCodePath: buildPackagePath!,
```

These are safe given prior `try await` assignments, but `guard let` would be clearer.

---

## Strengths

1. **Actor isolation** - Correct use of Swift actors for thread safety
2. **Graceful shutdown** - `stop()` properly cancels tasks and waits for builds
3. **VM verification handler** - Good separation of concerns with verification callback
4. **Error propagation in build** - Failures properly reported to controller
5. **Multipart upload handling** - Correct boundary-based form data construction

---

## Recommended Fix Priority

| Priority | Issue | Effort |
|----------|-------|--------|
| P0 | Value type mutation race (#1) | Medium |
| P0 | Registration failure silent (#3) | Low |
| P1 | Non-atomic config update (#2) | Low |
| P1 | Controller always new ID (#4) | Medium |
| P2 | Multiple config loads (#5) | Medium |
| P3 | HTTP request DRY (#6) | Low |
| P3 | Structured logging (#7) | Medium |
| P3 | Registration retry (#8) | Low |

---

## Reproduction Steps for Bug

1. Delete `~/Library/Application Support/FreeAgent/config.json`
2. Start FreeAgent app
3. `WorkerConfiguration.load()` generates local UUID "abc123", saves to disk
4. `registerWorker()` calls controller, gets assigned "xyz789"
5. In-memory config updated to "xyz789", saved to disk
6. `pollForJob()` uses "xyz789" - **works**
7. Quit app, restart
8. `WorkerConfiguration.load()` loads disk (should be "xyz789")
9. If step 5's save failed silently, disk has "abc123"
10. Worker polls with "abc123" -> controller returns 404

To force the bug:
- Comment out `configuration.save()` in `registerWorker()`
- Observe that restart uses old/nil ID
