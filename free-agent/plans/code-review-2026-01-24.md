# Code Review: Expo Free Agent - Menu Bar App & API Client

**Date:** 2026-01-24
**Reviewer:** Code Review
**Focus:** Concurrency issues, frozen/duplicate processes, resource leaks, macOS GUI best practices, API security

---

## Executive Summary

The frozen/duplicate process issue stems from **multiple compounding concurrency problems** in `main.swift`. The 2-second polling timer spawns synchronous blocking `Process` calls on background threads while UI updates must happen on main thread, creating a race condition nightmare. Additionally, the `pgrep` subprocess with spin-wait timeout is fundamentally flawed.

---

## [RED] Critical Issues

### 1. Main Thread Blocking in Process Detection
**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/FreeAgent/main.swift`, lines 78-109

**Problem:** `isWorkerProcessRunning()` spawns a `Process`, then spin-waits with `usleep(1000)` in a tight loop. This is called from a `Task` that was dispatched from a `Timer` callback. The spin-wait blocks the executor thread and can cause UI freezes.

```swift
// Current problematic code:
while process.isRunning && Date() < deadline {
    usleep(1000) // 1ms spin-wait - BLOCKS THREAD
}
```

**Impact:**
- Blocks Swift Concurrency executor threads
- Can cause main thread starvation when called from `@MainActor` context
- `readDataToEndOfFile()` on line 101 can block indefinitely if process hangs

**Solution:** Use async subprocess execution with proper timeout:
```swift
private func isWorkerProcessRunning() async -> Bool {
    await withCheckedContinuation { continuation in
        let queue = DispatchQueue(label: "process.check")
        queue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            process.arguments = ["-f", "FreeAgent worker"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
                return
            }

            // Set up timeout
            let workItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            queue.asyncAfter(deadline: .now() + 0.5, execute: workItem)

            process.waitUntilExit()
            workItem.cancel()

            let data = pipe.fileHandleForReading.availableData
            let output = String(data: data, encoding: .utf8) ?? ""
            continuation.resume(returning: !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
```

### 2. Race Condition in Timer + Task + Actor
**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/FreeAgent/main.swift`, lines 51-55

**Problem:** The timer fires every 2 seconds and creates a new `Task` each time. If the previous `updateStatus()` hasn't completed (due to slow `pgrep` or network call), multiple concurrent status checks run simultaneously. With the blocking subprocess calls, this can spawn dozens of orphaned `pgrep` processes.

```swift
statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
    Task { @MainActor in
        await self?.updateStatus()  // Creates new task each tick
    }
}
```

**Impact:**
- Multiple concurrent `pgrep` processes accumulate
- Race condition between `isWorkerProcessRunning()` and `workerService?.isRunning`
- Memory pressure from accumulated Tasks

**Solution:** Use a serial check with debouncing:
```swift
private var statusCheckTask: Task<Void, Never>?
private var isCheckingStatus = false

statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
    Task { @MainActor in
        guard let self = self, !self.isCheckingStatus else { return }
        self.isCheckingStatus = true
        defer { self.isCheckingStatus = false }
        await self.updateStatus()
    }
}
```

### 3. Process Zombies from Terminated Subprocesses
**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/FreeAgent/main.swift`, lines 96-98

**Problem:** When `process.terminate()` is called on timeout, the code returns immediately without calling `waitUntilExit()`. This leaves zombie processes.

```swift
if process.isRunning {
    process.terminate()
    return false  // ZOMBIE: never waited for termination
}
```

**Impact:** Zombie processes accumulate over time, consuming PIDs and causing `pgrep` to find stale entries.

**Solution:** Always wait after terminate:
```swift
if process.isRunning {
    process.terminate()
    process.waitUntilExit()  // Reap the zombie
    return false
}
```

### 4. `readDataToEndOfFile()` Blocking After Timeout
**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/FreeAgent/main.swift`, line 101

**Problem:** After the spin-wait timeout check, if the process somehow exited between the check and line 101, `readDataToEndOfFile()` will still block. This is a TOCTOU (time-of-check-time-of-use) race.

**Solution:** Use `availableData` instead:
```swift
let data = pipe.fileHandleForReading.availableData  // Non-blocking
```

### 5. TartVMManager Uses Blocking `waitUntilExit()` in Async Context
**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/BuildVM/TartVMManager.swift`, lines 291-297

**Problem:** `executeCommand()` calls `process.waitUntilExit()` synchronously, blocking the Swift Concurrency cooperative thread pool. This is acceptable for long-running builds but can cause thread exhaustion.

```swift
private func executeCommand(_ command: String, _ arguments: [String]) async throws {
    let process = Process()
    // ...
    try process.run()
    process.waitUntilExit()  // BLOCKS executor thread
}
```

**Impact:** With `maxConcurrentBuilds > 1`, multiple blocked threads can exhaust the cooperative pool, causing app-wide hangs.

**Solution:** Wrap in `DispatchQueue` to avoid blocking executor:
```swift
private func executeCommand(_ command: String, _ arguments: [String]) async throws {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
            // ... process setup and run ...
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                continuation.resume()
            } else {
                continuation.resume(throwing: VMError.commandFailed(...))
            }
        }
    }
}
```

---

## [YELLOW] Architecture Concerns

### 6. Actor Re-entrancy in WorkerService
**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/WorkerCore/WorkerService.swift`, lines 62-66

**Problem:** `pollLoop()` calls `executeJob()` which awaits on actor-isolated state. During the `await`, another poll could theoretically trigger. The `activeBuilds.count` check happens before the async work completes.

```swift
if activeBuilds.count < configuration.maxConcurrentBuilds {
    if let job = try await pollForJob() {  // Suspends here
        await executeJob(job)  // Another poll could check count before this completes
    }
}
```

**Mitigation:** The single-threaded actor guarantees no true concurrency, but the logic should increment a counter atomically:
```swift
private var pendingJobStarts = 0

if (activeBuilds.count + pendingJobStarts) < configuration.maxConcurrentBuilds {
    pendingJobStarts += 1
    defer { pendingJobStarts -= 1 }
    if let job = try await pollForJob() {
        await executeJob(job)
    }
}
```

### 7. Settings Window Re-creation on Every Open
**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/FreeAgent/main.swift`, lines 159-178

**Problem:** Creates a new `WorkerService` instance on every settings save. The old service is not stopped, potentially leaving orphaned polling tasks.

```swift
onSave: { [weak self] config in
    config.save()
    self?.workerService = WorkerService(configuration: config)  // Old service still running?
}
```

**Solution:** Stop old service before replacing:
```swift
onSave: { [weak self] config in
    Task { @MainActor in
        await self?.workerService?.stop()
        config.save()
        self?.workerService = WorkerService(configuration: config)
    }
}
```

### 8. Timer Not Scheduled on RunLoop
**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/FreeAgent/main.swift`, line 51

**Problem:** `Timer.scheduledTimer` adds to current RunLoop, which in AppKit is `RunLoop.main`. However, if called from a dispatch queue, it may not fire.

**Mitigation:** Explicit RunLoop scheduling (though current code likely works):
```swift
RunLoop.main.add(statusUpdateTimer!, forMode: .common)
```

---

## [GREEN] DRY Opportunities

### 9. Duplicate Multipart Form Building
**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/WorkerCore/WorkerService.swift`, lines 342-398 and 400-444

**Problem:** `uploadBuildResult()` and `reportJobFailure()` both construct identical multipart form bodies with duplicate code.

**Solution:** Extract shared multipart builder:
```swift
private func buildMultipartBody(
    boundary: String,
    jobID: String,
    success: Bool,
    errorMessage: String? = nil,
    artifactData: Data? = nil,
    artifactFilename: String? = nil
) -> Data {
    var body = Data()
    // ... shared implementation ...
    return body
}
```

### 10. Repeated SSH Option Array
**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/BuildVM/TartVMManager.swift`, lines 26-32

**Problem:** SSH options hardcoded as array literal, then duplicated in every SSH/SCP call.

**Solution:** Already factored into `sshOptions` property. Good.

---

## [BLUE] Maintenance Improvements

### 11. Error Type Loses Information
**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/BuildVM/TartVMManager.swift`, lines 337-353

**Problem:** All error factories return `.buildFailed` enum case, losing the actual error message.

```swift
static func timeout(_ message: String) -> VMError {
    .buildFailed // message discarded!
}
```

**Solution:** Add associated values to VMError:
```swift
enum VMError: Error {
    case buildFailed
    case timeout(String)
    case sshFailed(String)
    case scpFailed(String)
    case commandFailed(String)
}
```

### 12. Hardcoded Template Image Name
**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/BuildVM/TartVMManager.swift`, line 19

**Problem:** `expo-free-agent-tahoe-26.2-xcode-expo-54` hardcoded. Should be configurable.

### 13. No Logging Framework
**Problem:** All logging uses `print()`. No log levels, no persistence, no structured output. Hard to debug production issues.

**Solution:** Use `os.Logger` or a logging package:
```swift
import os
private let logger = Logger(subsystem: "com.expo.free-agent", category: "worker")
logger.info("Worker service starting...")
logger.error("Poll error: \(error.localizedDescription)")
```

### 14. Missing Cancellation in applicationWillTerminate
**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/FreeAgent/main.swift`, lines 63-68

**Problem:** `Task { await workerService?.stop() }` creates a detached task. If app terminates before task completes, the worker may not stop cleanly.

**Solution:** Use synchronous shutdown or Task.detached with priority:
```swift
func applicationWillTerminate(_ notification: Notification) {
    statusUpdateTimer?.invalidate()
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        await workerService?.stop()
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 5)
}
```

---

## [WHITE] Nitpicks

### 15. Bundle.module May Fail
**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/FreeAgent/main.swift`, line 23

**Problem:** `Bundle.module` only works in Swift Package Manager builds. May fail in Xcode project builds.

### 16. Force Unwrap After nil Check
**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/BuildVM/TartVMManager.swift`, lines 52, 67, etc.

**Problem:** `vmName!` used repeatedly after setting it. Use `guard let` binding instead.

### 17. API Client Path Traversal Check Inconsistent
**Location:** `/Users/sethwebster/Development/expo/expo-free-agent/cli/src/api-client.ts`, lines 292-311

**Problem:** Checks for `..` after resolving path, which is redundant. The `resolve()` call already normalizes. The `startsWith(cwd)` check is the real protection.

---

## [CHECK] Strengths

1. **Actor-based WorkerService:** Proper use of Swift actors for thread-safe state management
2. **Zod Schema Validation:** API client validates responses with runtime type checking
3. **Timeout Handling:** Build execution has explicit timeouts
4. **Cleanup Patterns:** VM cleanup runs in both success and error paths
5. **API Key Security:** Keys passed via headers, not query params; Apple password only from env var

---

## Root Cause Analysis: Frozen/Duplicate Processes

The freeze occurs due to this sequence:

1. Timer fires every 2 seconds
2. Each tick creates a new `Task` calling `updateStatus()`
3. `updateStatus()` calls `isWorkerProcessRunning()` synchronously
4. `isWorkerProcessRunning()` spawns `pgrep` and spin-waits
5. If `pgrep` hangs (e.g., system under load), the spin-wait continues for 100ms
6. Meanwhile, timer fires again, creating another Task
7. Multiple concurrent `pgrep` processes now running
8. `readDataToEndOfFile()` blocks on slow pipes
9. Main thread starves, UI freezes
10. Terminated processes become zombies (no `waitUntilExit()` after `terminate()`)

**Immediate Fix:**

```swift
// Replace isWorkerProcessRunning() with async version
private func isWorkerProcessRunning() async -> Bool {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            process.arguments = ["-f", "FreeAgent worker"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
                return
            }

            // Timeout after 500ms
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                if process.isRunning {
                    process.terminate()
                    process.waitUntilExit()  // Reap zombie
                }
            }

            process.waitUntilExit()

            let data = pipe.fileHandleForReading.availableData
            let output = String(data: data, encoding: .utf8) ?? ""
            continuation.resume(returning: !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

// Add guard to prevent concurrent status checks
private var isCheckingStatus = false

private func updateStatus() async {
    guard !isCheckingStatus else { return }
    isCheckingStatus = true
    defer { isCheckingStatus = false }

    let processRunning = await isWorkerProcessRunning()
    let serviceRunning = await workerService?.isRunning ?? false
    updateMenuStatus(running: processRunning || serviceRunning)
}
```

---

## Priority Fixes

1. **P0:** Fix `isWorkerProcessRunning()` - make async, add zombie reaping
2. **P0:** Add mutex guard to prevent concurrent status checks
3. **P1:** Increase polling interval to 5+ seconds
4. **P1:** Stop old WorkerService before creating new one in settings
5. **P2:** Use `os.Logger` for proper logging
6. **P2:** Fix VMError to preserve error messages

---

## Unresolved Questions

- Why 2s poll? 5-10s more reasonable for status checks
- Is `pgrep -f "FreeAgent worker"` the right detection pattern? Could match unrelated processes
- Should status check use file-based PID tracking instead of pgrep?
- WorkerService.pollLoop recovery: exponential backoff caps at 5s - too aggressive?
