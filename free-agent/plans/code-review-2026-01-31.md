# Code Review: HUD Notification Memory Safety

**Date**: 2026-01-31
**Reviewer**: Code Review Agent
**Files**: HUDNotification.swift, main.swift, TemplateVMCheck.swift, VMSyncService.swift
**Issue**: Crash with `objc_release` / `Bad pointer dereference` when hovering/clicking HUD during download

---

## 🔴 Critical Issues

### 1. Race Condition: viewModel Nullified While Window Animation In-Flight

**Location**: `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/FreeAgent/HUDNotification.swift:195-213`

**Problem**: The `dismiss()` method sets `viewModel = nil` immediately, but the window's fade-out animation runs asynchronously for 0.2s. The `HUDNotificationView` still holds an `@ObservedObject var viewModel` that references the now-nil object. If the user interacts with the HUD during this animation window, SwiftUI attempts to access the deallocated viewModel.

```swift
func dismiss() {
    dismissTimer?.invalidate()
    dismissTimer = nil

    guard let window = currentHUD else { return }

    NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.2
        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
        window.animator().alphaValue = 0
    }, completionHandler: {
        Task { @MainActor in
            window.close()
        }
    })

    currentHUD = nil
    viewModel = nil  // ❌ CRITICAL: Set to nil while view still exists in window
}
```

**Impact**: Use-after-free. The SwiftUI view hierarchy still references `viewModel` via `@ObservedObject`. When the user hovers/clicks, SwiftUI accesses the deallocated object causing `objc_release` crash.

**Solution**: Defer `viewModel = nil` until AFTER the window closes:

```swift
func dismiss() {
    dismissTimer?.invalidate()
    dismissTimer = nil

    guard let window = currentHUD else { return }
    currentHUD = nil  // Prevent re-entry

    NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.2
        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
        window.animator().alphaValue = 0
    }, completionHandler: { [weak self] in
        Task { @MainActor in
            window.close()
            self?.viewModel = nil  // ✅ Safe: window closed, view hierarchy destroyed
        }
    })
}
```

---

### 2. Concurrent Updates to @Published Properties During Rapid Progress

**Location**: `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/FreeAgent/HUDNotification.swift:187-193`

**Problem**: `updateDownloadProgress` directly mutates `@Published` properties on `HUDViewModel`. Although `HUDNotificationManager` is `@MainActor`, the progress handler in `main.swift` dispatches to main queue asynchronously. Multiple dispatched blocks can queue up and execute in rapid succession, causing SwiftUI to process multiple state changes while the view is mid-render.

```swift
func updateDownloadProgress(percent: Double) {
    guard let vm = viewModel else { return }

    // ❌ These mutations trigger SwiftUI re-renders
    vm.type = .downloading(percent: percent)
    vm.message = String(format: "Downloading base image (%.0f%%)", percent)
}
```

**Impact**: If a previous dismiss is in-flight (animation running, viewModel about to be nil'd), this function can write to a dangling reference.

**Solution**: Add a dismissed flag and guard against updates after dismissal:

```swift
@MainActor
class HUDViewModel: ObservableObject {
    @Published var type: HUDType
    @Published var message: String
    let onDismiss: () -> Void
    var isDismissed = false  // ✅ Add dismissed flag

    // ...
}

func updateDownloadProgress(percent: Double) {
    guard let vm = viewModel, !vm.isDismissed else { return }
    vm.type = .downloading(percent: percent)
    vm.message = String(format: "Downloading base image (%.0f%%)", percent)
}

func dismiss() {
    viewModel?.isDismissed = true  // ✅ Mark before animation
    // ... rest of dismiss logic
}
```

---

### 3. Closure Capture Creates Strong Reference Cycle Risk in onDismiss

**Location**: `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/FreeAgent/HUDNotification.swift:137-139`

**Problem**: The `onDismiss` closure is stored as a strong reference in `HUDViewModel`. If `dismiss()` is called during HUD animation and the viewModel is accessed through the button action, Swift may attempt to execute the closure on a deallocating object.

```swift
let vm = HUDViewModel(type: type, message: message) { [weak self] in
    self?.dismiss()  // ❌ `self` may be nil, but viewModel holds closure strongly
}
viewModel = vm
```

The viewModel stores `onDismiss` strongly, and the button in `HUDNotificationView` calls `viewModel.onDismiss` directly:

```swift
Button(action: viewModel.onDismiss) {  // ❌ Direct reference to stored closure
    Image(systemName: "xmark.circle.fill")
}
```

**Impact**: When `viewModel = nil` is set in `dismiss()` but the view is still visible, clicking the dismiss button accesses the deallocated closure.

**Solution**: Use a weak reference pattern or make the button action safe:

```swift
// Option A: Make onDismiss optional and guard
Button(action: { [weak viewModel] in
    viewModel?.onDismiss()
}) {
    Image(systemName: "xmark.circle.fill")
}

// Option B: Don't store closure, use delegation pattern
```

---

### 4. Progress Handler Called After Process Termination

**Location**: `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/DiagnosticsCore/Checks/TemplateVMCheck.swift:252-271`

**Problem**: The termination handler has a 100ms delay before clearing `readabilityHandler`, but the handlers themselves may still fire during this window. The `markTerminating()` call is meant to prevent processing, but there's a race:

```swift
process.terminationHandler = { [collector, handler] proc in
    collector.markTerminating()  // Sets flag

    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) {
        // ❌ 100ms window where readabilityHandler can still fire
        outHandle.readabilityHandler = nil
        errHandle.readabilityHandler = nil

        Thread.sleep(forTimeInterval: 0.05)  // ❌ Another 50ms gap

        let output = collector.finalize()
        continuation.resume(returning: (proc.terminationStatus, output))
    }
}
```

The `OutputCollector.processStdout` checks `isTerminating` under lock, but `parseProgressLineSync` is called INSIDE that lock, meaning the handler callback happens synchronously while the lock is held. This is fine. However, the progress handler dispatches to main queue:

```swift
// In VMSyncService.ensureTemplateExists:
await check.setProgressHandler { [weak self] progress in
    Task { @MainActor in
        self?.onProgressUpdate?(progress)  // ❌ Async dispatch
    }
}
```

**Impact**: Progress updates can be dispatched to main queue after the process terminates and the continuation resumes, potentially updating a HUD that's being dismissed.

**Solution**: The handler should be invalidated before any callbacks can dispatch:

```swift
process.terminationHandler = { [collector] proc in
    // ✅ Clear handlers FIRST, synchronously
    outHandle.readabilityHandler = nil
    errHandle.readabilityHandler = nil

    collector.markTerminating()

    // Give any already-dispatched main queue blocks time to complete
    DispatchQueue.main.async {
        // Now finalize
        let output = collector.finalize()
        continuation.resume(returning: (proc.terminationStatus, output))
    }
}
```

---

## 🟡 Architecture Concerns

### 1. Mixing MainActor and Background Thread Callbacks

**Location**: `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/FreeAgent/main.swift:63-126`

**Problem**: The progress handler is set with `[weak self]` but `self` is the `@MainActor` AppDelegate. The handler is called from background threads (the readabilityHandler runs on dispatch I/O queue). Inside, there's `DispatchQueue.main.async` which is correct, but the outer closure captures `percent` from a background thread:

```swift
vmSyncService?.setProgressHandler { [weak self] progress in
    guard let self = self else { return }

    switch progress.status {
    case .downloading:
        let percent = progress.percentComplete ?? 0.0

        DispatchQueue.main.async { [weak self] in  // ❌ Capturing `percent` from bg thread
            guard let self = self else { return }
            // Uses `percent` here
        }
    }
}
```

**Impact**: This works but is fragile. If `progress` were a reference type that could mutate, you'd have a data race. Currently `DownloadProgress` appears to be a value type so this is safe, but the pattern is concerning.

**Solution**: Capture progress value explicitly:

```swift
case .downloading:
    let percent = progress.percentComplete ?? 0.0
    let message = progress.message

    DispatchQueue.main.async { [weak self, percent, message] in
        // Now explicitly captured
    }
```

---

### 2. Timer Not RunLoop-Safe

**Location**: `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/FreeAgent/HUDNotification.swift:179-184`

**Problem**: `Timer.scheduledTimer` schedules on the current RunLoop. Since `HUDNotificationManager` is `@MainActor`, this should be `.main`, but the timer callback uses `Task { @MainActor in ... }` which is unnecessary overhead:

```swift
dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
    Task { @MainActor in  // ❌ Unnecessary - timer already fires on main
        self?.dismiss()
    }
}
```

**Impact**: Minor inefficiency, but also creates a potential issue where the Task can outlive the timer and manager.

**Solution**: Direct call since we're already MainActor:

```swift
dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
    self?.dismiss()  // Already on main run loop
}
```

---

## 🟢 DRY Opportunities

### 1. Progress Handler Pattern Duplicated

**Location**:
- `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/FreeAgent/main.swift:70-110`
- `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/FreeAgent/VMSyncService.swift:46-50`

**Problem**: Progress handling with `DispatchQueue.main.async` and weak self capture is repeated. Could be consolidated into VMSyncService itself handling the main queue dispatch.

---

## 🔵 Maintenance Improvements

### 1. Missing Guard for Nil ViewMode in Button Action

**Location**: `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/FreeAgent/HUDNotification.swift:102`

**Problem**: The button action directly references `viewModel.onDismiss`. If SwiftUI evaluates this while viewModel is in an inconsistent state, crash ensues.

**Solution**: Wrap in safe accessor or use local capture.

---

### 2. Thread.sleep in Async Code

**Location**: `/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/DiagnosticsCore/Checks/TemplateVMCheck.swift:264`

**Problem**: `Thread.sleep(forTimeInterval: 0.05)` blocks a GCD thread. Should use async delay.

**Solution**: Use `try? await Task.sleep(nanoseconds:)` or dispatch scheduling.

---

## ⚪ Nitpicks

1. **HUDWindow.canBecomeKey returns false**: Intentional, but document why (prevents stealing focus).

2. **Magic numbers**: `0.3`, `0.2` animation durations, `0.5` throttle interval should be constants.

3. **dismissTimer invalidation**: Already done correctly, but could use `Timer?` optional chaining pattern.

---

## ✅ Strengths

1. **OutputCollector thread safety**: Proper use of `NSLock` with `defer { lock.unlock() }` pattern. The `isTerminating` flag prevents late callbacks from corrupting state.

2. **Throttling logic**: Good approach to limit UI updates to 0.5s intervals - prevents UI thrashing during rapid progress.

3. **@MainActor annotations**: Correctly applied to AppDelegate, HUDNotificationManager, and HUDViewModel. The type system helps catch threading issues.

4. **Weak self captures**: Consistent use of `[weak self]` in closures to prevent retain cycles.

5. **Value type for DownloadProgress**: Makes cross-thread passing safe without explicit synchronization.

---

## Summary: Root Cause Analysis

The crash is almost certainly caused by **Critical Issue #1**: The `dismiss()` method sets `viewModel = nil` immediately while the window's 0.2s fade animation is still running. During this window:

1. User hovers over HUD (causes view re-render)
2. SwiftUI accesses `viewModel` via `@ObservedObject`
3. `viewModel` is nil or deallocated
4. `objc_release` on invalid pointer

**Secondary contributor**: Rapid progress updates (every 0.5s) can queue multiple `DispatchQueue.main.async` blocks. If one block triggers a dismiss (e.g., 100% complete), subsequent blocks may try to update a nil viewModel.

## Recommended Fix Priority

1. **Immediate**: Fix Critical Issue #1 - defer `viewModel = nil` to after window.close()
2. **Immediate**: Fix Critical Issue #2 - add `isDismissed` guard
3. **High**: Fix Critical Issue #3 - protect button action closure
4. **Medium**: Fix Critical Issue #4 - clean up handler before termination callback

---

## Proposed Code Fixes

### Fix 1: Safe Dismiss with Deferred Cleanup

```swift
func dismiss() {
    dismissTimer?.invalidate()
    dismissTimer = nil

    guard let window = currentHUD else { return }

    // Mark viewModel as dismissed immediately to block updates
    viewModel?.isDismissed = true
    currentHUD = nil  // Prevent re-entry

    // Capture viewModel reference for cleanup after animation
    let vmToCleanup = viewModel

    NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.2
        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
        window.animator().alphaValue = 0
    }, completionHandler: { [weak self] in
        Task { @MainActor in
            window.close()
            // Now safe to nil out - view hierarchy is destroyed
            if self?.viewModel === vmToCleanup {
                self?.viewModel = nil
            }
        }
    })
}
```

### Fix 2: Add isDismissed to ViewModel

```swift
@MainActor
class HUDViewModel: ObservableObject {
    @Published var type: HUDType
    @Published var message: String
    let onDismiss: () -> Void
    private(set) var isDismissed = false

    func markDismissed() {
        isDismissed = true
    }

    init(type: HUDType, message: String, onDismiss: @escaping () -> Void) {
        self.type = type
        self.message = message
        self.onDismiss = onDismiss
    }
}
```

### Fix 3: Safe updateDownloadProgress

```swift
func updateDownloadProgress(percent: Double) {
    guard let vm = viewModel, !vm.isDismissed else { return }
    vm.type = .downloading(percent: percent)
    vm.message = String(format: "Downloading base image (%.0f%%)", percent)
}
```
