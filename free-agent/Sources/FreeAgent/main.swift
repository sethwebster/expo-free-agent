import AppKit
import SwiftUI
import WorkerCore
import DiagnosticsCore

// MARK: - Doctor Mode

// Check for doctor command before starting GUI
if CommandLine.arguments.contains("doctor") {
    Task {
        let config = WorkerConfiguration.load()

        // Ensure worker ID exists
        guard let workerId = config.workerID else {
            print("Error: Worker ID not found. Please start the worker once to register.")
            exit(1)
        }

        // Create diagnostics service
        let diagnosticsService = DiagnosticsService(
            workerId: workerId,
            controllerURL: config.controllerURL,
            apiKey: config.apiKey,
            templateImage: "expo-free-agent-tahoe-26.2-xcode-expo-54"
        )

        // Run diagnostics with auto-fix
        let report = await diagnosticsService.runDiagnostics(autoFix: true)

        // Report to controller
        do {
            try await diagnosticsService.reportToController(report)
            print("✓ Report sent to controller\n")
        } catch {
            print("✗ Failed to send report to controller: \(error.localizedDescription)\n")
        }

        // Exit with appropriate code
        exit(report.status == .healthy ? 0 : 1)
    }

    // Wait for async task to complete
    RunLoop.main.run()
}

// MARK: - Data Models for Active Builds

struct ActiveBuild: Codable {
    let id: String
    let status: String
    let platform: String
    let worker_id: String?
    let started_at: Int64?
}

struct ActiveBuildsResponse: Codable {
    let builds: [ActiveBuild]
}

// MARK: - App Delegate

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

enum ConnectionState {
    case connecting
    case online
    case building
    case offline
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var workerService: WorkerService?
    private var settingsWindow: NSWindow?
    private var statisticsWindow: NSWindow?
    private var statusUpdateTimer: Timer?
    private var animationTimer: Timer?
    private var isCheckingStatus = false
    private var currentBuilds: [ActiveBuild] = []
    private var connectionState: ConnectionState = .connecting
    private var animationFrame = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Start with connecting state
            connectionState = .connecting
            button.image = createIconForState(.connecting)
            button.image?.isTemplate = true
        }

        setupMenu()

        // Start animation for connecting dots
        startAnimation()

        // Initialize worker service
        let config = WorkerConfiguration.load()
        workerService = WorkerService(configuration: config)

        // Auto-start worker if configured
        if config.autoStart {
            Task {
                await workerService?.start()
                updateMenuStatus(running: true)
            }
        }

        // Start status monitoring timer (check every 5 seconds)
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateStatus()
            }
        }

        // Initial status update
        Task { @MainActor in
            await updateStatus()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusUpdateTimer?.invalidate()
        animationTimer?.invalidate()
        Task {
            await workerService?.stop()
        }
    }

    private func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.connectionState == .connecting {
                    self.animationFrame = (self.animationFrame + 1) % 4
                    if let button = self.statusItem?.button {
                        button.image = self.createIconForState(.connecting)
                    }
                }
            }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationFrame = 0
    }

    private func updateStatus() async {
        // Prevent concurrent status checks
        guard !isCheckingStatus else { return }
        isCheckingStatus = true
        defer { isCheckingStatus = false }

        // Check if any FreeAgent worker process is running (CLI or GUI-managed)
        let processRunning = await isWorkerProcessRunning()
        let serviceRunning = await workerService?.isRunning ?? false
        let running = processRunning || serviceRunning
        updateMenuStatus(running: running)

        // Fetch and update active builds list
        let builds = await fetchActiveBuilds()
        currentBuilds = builds  // Cache for menu delegate
        updateActiveBuildsMenu(builds: builds)

        // Update connection state and icon
        let newState: ConnectionState
        if !builds.isEmpty {
            newState = .building
        } else if running {
            newState = .online
        } else {
            newState = .offline
        }

        if newState != connectionState {
            connectionState = newState
            if newState == .connecting {
                startAnimation()
            } else {
                stopAnimation()
            }
            updateIconForCurrentState()
        } else if connectionState == .building {
            // Update building icon to refresh green dot
            updateIconForCurrentState()
        }
    }

    private func isWorkerProcessRunning() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
                process.arguments = ["-f", "FreeAgent worker"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()

                    // Wait for completion (blocks dispatch queue, not Swift Concurrency executor)
                    process.waitUntilExit()

                    // Use availableData instead of readDataToEndOfFile
                    let data = pipe.fileHandleForReading.availableData
                    guard let output = String(data: data, encoding: .utf8) else {
                        continuation.resume(returning: false)
                        return
                    }

                    // pgrep returns PIDs if processes found, empty if not
                    let found = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    continuation.resume(returning: found)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func fetchActiveBuilds() async -> [ActiveBuild] {
        let config = WorkerConfiguration.load()
        let apiKey = config.apiKey

        let urlString = "\(config.controllerURL)/api/builds/active"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 5.0

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(ActiveBuildsResponse.self, from: data)
            return response.builds
        } catch {
            return []
        }
    }

    private func formatElapsedTime(startedAt: Int64?) -> String {
        guard let started = startedAt else { return "—" }

        let startDate = Date(timeIntervalSince1970: TimeInterval(started) / 1000.0)
        let elapsed = Date().timeIntervalSince(startDate)

        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self  // Enable live menu updates

        // Status
        menu.addItem(NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        // Active Builds section (placeholder - will be populated by updateActiveBuildsMenu)
        // Menu items will be inserted here at index 2

        menu.addItem(NSMenuItem.separator())

        // Start/Stop
        let startStopItem = NSMenuItem(title: "Start Worker", action: #selector(toggleWorker), keyEquivalent: "s")
        startStopItem.target = self
        menu.addItem(startStopItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Statistics
        let statsItem = NSMenuItem(title: "Statistics", action: #selector(showStatistics), keyEquivalent: "i")
        statsItem.target = self
        menu.addItem(statsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Free Agent", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Update menu items when menu is about to be displayed
        Task { @MainActor in
            await updateStatus()
        }
    }

    // MARK: - Icon Creation

    private func updateIconForCurrentState() {
        guard let button = statusItem?.button else { return }
        button.image = createIconForState(connectionState)
        button.image?.isTemplate = (connectionState != .building)
    }

    private func createIconForState(_ state: ConnectionState) -> NSImage {
        switch state {
        case .connecting:
            return createConnectingIcon()
        case .online:
            return createOnlineIcon()
        case .building:
            return createBuildingIcon()
        case .offline:
            return createTrayIcon()
        }
    }

    private func createTrayIcon() -> NSImage {
        // Try to load and render SVG logo, fallback to simple pattern
        if let svgPath = Bundle.main.path(forResource: "free-agent-logo", ofType: "svg"),
           let svgData = try? Data(contentsOf: URL(fileURLWithPath: svgPath)),
           let image = NSImage(data: svgData) {
            // Render SVG at small size for tray
            let traySize = NSSize(width: 18, height: 18)
            let trayImage = NSImage(size: traySize, flipped: false) { rect in
                image.draw(in: rect)
                return true
            }
            return trayImage
        }

        // Fallback: Simple block pattern if SVG not found
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Create simple block pattern:
            //   ■
            // ■ ■ ■
            let blockSize: CGFloat = 4.5

            // Top block (centered)
            let topBlock = NSRect(x: 6.75, y: 9, width: blockSize, height: blockSize)
            NSBezierPath(rect: topBlock).fill()

            // Bottom row - 3 blocks
            let bottomY: CGFloat = 4
            let bottomLeft = NSRect(x: 2.25, y: bottomY, width: blockSize, height: blockSize)
            let bottomCenter = NSRect(x: 6.75, y: bottomY, width: blockSize, height: blockSize)
            let bottomRight = NSRect(x: 11.25, y: bottomY, width: blockSize, height: blockSize)

            NSBezierPath(rect: bottomLeft).fill()
            NSBezierPath(rect: bottomCenter).fill()
            NSBezierPath(rect: bottomRight).fill()

            return true
        }
        return image
    }

    private func createConnectingIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw base icon
            let blockSize: CGFloat = 4.5
            let topBlock = NSRect(x: 6.75, y: 9, width: blockSize, height: blockSize)
            NSBezierPath(rect: topBlock).fill()

            let bottomY: CGFloat = 4
            let bottomLeft = NSRect(x: 2.25, y: bottomY, width: blockSize, height: blockSize)
            let bottomCenter = NSRect(x: 6.75, y: bottomY, width: blockSize, height: blockSize)
            let bottomRight = NSRect(x: 11.25, y: bottomY, width: blockSize, height: blockSize)

            NSBezierPath(rect: bottomLeft).fill()
            NSBezierPath(rect: bottomCenter).fill()
            NSBezierPath(rect: bottomRight).fill()

            // Draw animated dots below
            let dotSize: CGFloat = 2.0
            let dotY: CGFloat = 0.5
            let spacing: CGFloat = 3.0

            for i in 0..<3 {
                let alpha: CGFloat = (i == self.animationFrame % 3) ? 1.0 : 0.3
                NSColor.black.withAlphaComponent(alpha).setFill()
                let dotX = 5.0 + CGFloat(i) * spacing
                let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
                NSBezierPath(ovalIn: dotRect).fill()
            }

            return true
        }
        return image
    }

    private func createOnlineIcon() -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw base icon
            let blockSize: CGFloat = 4.5
            let topBlock = NSRect(x: 6.75, y: 9, width: blockSize, height: blockSize)
            NSBezierPath(rect: topBlock).fill()

            let bottomY: CGFloat = 4
            let bottomLeft = NSRect(x: 2.25, y: bottomY, width: blockSize, height: blockSize)
            let bottomCenter = NSRect(x: 6.75, y: bottomY, width: blockSize, height: blockSize)
            let bottomRight = NSRect(x: 11.25, y: bottomY, width: blockSize, height: blockSize)

            NSBezierPath(rect: bottomLeft).fill()
            NSBezierPath(rect: bottomCenter).fill()
            NSBezierPath(rect: bottomRight).fill()

            // Draw green checkmark in top-right
            let checkSize: CGFloat = 6.0
            let checkX: CGFloat = 14.0
            let checkY: CGFloat = 11.0

            NSColor(calibratedRed: 0.0, green: 0.8, blue: 0.0, alpha: 1.0).setStroke()
            let checkPath = NSBezierPath()
            checkPath.lineWidth = 1.5
            checkPath.move(to: NSPoint(x: checkX, y: checkY))
            checkPath.line(to: NSPoint(x: checkX + 2.0, y: checkY - 2.0))
            checkPath.line(to: NSPoint(x: checkX + checkSize, y: checkY + 2.0))
            checkPath.stroke()

            return true
        }
        return image
    }

    private func createBuildingIcon() -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw block icon
            let baseIcon = self.createTrayIcon()
            baseIcon.draw(in: NSRect(x: 2, y: 2, width: 18, height: 18))

            // Draw bright green dot in bottom-right
            let dotSize: CGFloat = 8
            let dotRect = NSRect(x: size.width - dotSize,
                                 y: 0,
                                 width: dotSize,
                                 height: dotSize)

            NSColor(calibratedRed: 0.0, green: 1.0, blue: 0.0, alpha: 1.0).setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            return true
        }
        return image
    }

    @objc private func toggleWorker() {
        guard let service = workerService else { return }

        Task { @MainActor in
            let running = await service.isRunning
            if running {
                await service.stop()
                updateMenuStatus(running: false)
            } else {
                await service.start()
                updateMenuStatus(running: true)
            }
        }
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView(
                configuration: WorkerConfiguration.load(),
                onSave: { [weak self] config in
                    Task { @MainActor in
                        // Stop old service before replacing
                        await self?.workerService?.stop()
                        config.save()
                        self?.workerService = WorkerService(configuration: config)
                    }
                }
            )

            let hostingController = NSHostingController(rootView: settingsView)
            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "Free Agent Settings"
            settingsWindow?.styleMask = [.titled, .closable, .miniaturizable]
            settingsWindow?.setContentSize(NSSize(width: 500, height: 600))
            settingsWindow?.center()
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showStatistics() {
        // Activate app first to ensure window comes to front
        NSApp.activate(ignoringOtherApps: true)

        if statisticsWindow == nil {
            let statsView = StatisticsView(configuration: WorkerConfiguration.load())

            let hostingController = NSHostingController(rootView: statsView)
            statisticsWindow = NSWindow(contentViewController: hostingController)
            statisticsWindow?.title = "Free Agent Statistics"
            statisticsWindow?.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            statisticsWindow?.setContentSize(NSSize(width: 500, height: 600))
            statisticsWindow?.center()
            statisticsWindow?.level = .floating  // Keep window on top
            statisticsWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }

        statisticsWindow?.orderFrontRegardless()
        statisticsWindow?.makeKeyAndOrderFront(nil)
    }

    private func updateMenuStatus(running: Bool) {
        guard let menu = statusItem?.menu else { return }

        if let statusMenuItem = menu.item(at: 0) {
            statusMenuItem.title = running ? "Status: Running" : "Status: Idle"
        }

        // Find Start/Stop Worker item (search by title prefix)
        for item in menu.items {
            if item.title.contains("Worker") {
                item.title = running ? "Stop Worker" : "Start Worker"
                break
            }
        }

        // Update icon color/appearance
        if let button = statusItem?.button {
            button.appearsDisabled = !running
        }
    }

    private func updateActiveBuildsMenu(builds: [ActiveBuild]) {
        guard let menu = statusItem?.menu else { return }

        // Remove old build items (between index 2 and next separator)
        let idx = 2
        while idx < menu.items.count {
            let item = menu.items[idx]
            if item.isSeparatorItem { break }
            menu.removeItem(at: idx)
        }

        // Add new build items
        if builds.isEmpty {
            let item = NSMenuItem(title: "No active builds", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.insertItem(item, at: 2)
        } else {
            for (i, build) in builds.enumerated() {
                let status = build.status.capitalized
                let platform = build.platform.uppercased()
                let elapsed = formatElapsedTime(startedAt: build.started_at)

                // Format: "Building IOS • 5m 23s"
                let title = "\(status) \(platform) • \(elapsed)"

                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false  // No click action (security: no build ID exposure)
                menu.insertItem(item, at: 2 + i)
            }
        }
    }

}
