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
            templateImage: "ghcr.io/sethwebster/expo-free-agent-base:0.1.26"
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

enum ConnectionState: Equatable {
    case connecting
    case online
    case building
    case downloading(percent: Double)
    case offline

    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.connecting, .connecting), (.online, .online), (.building, .building), (.offline, .offline):
            return true
        case (.downloading(let lhsPercent), .downloading(let rhsPercent)):
            return abs(lhsPercent - rhsPercent) < 0.01  // Close enough for visual update
        default:
            return false
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, ObservableObject {
    private var statusItem: NSStatusItem?
    private var workerService: WorkerService?
    private var vmSyncService: VMSyncService?
    private var settingsWindow: NSWindow?
    private var statisticsWindow: NSWindow?
    private var statusUpdateTimer: Timer?
    private var animationTimer: Timer?
    private var isCheckingStatus = false
    private var currentBuilds: [ActiveBuild] = []
    private var connectionState: ConnectionState = .connecting
    private var animationFrame = 0
    private var downloadProgress: Double = 0.0
    @Published var currentVMDownloadProgress: DownloadProgress? = nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy for menu bar app with windows
        NSApp.setActivationPolicy(.accessory)

        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        print("✓ Created status item: \(statusItem != nil)")

        if let button = statusItem?.button {
            // Start with connecting state
            connectionState = .connecting
            let icon = createIconForState(.connecting)
            button.image = icon
            button.image?.isTemplate = true
            button.toolTip = toolTipForState(.connecting)
            print("✓ Set status item icon")
        } else {
            print("✗ Failed to get status item button!")
        }

        setupMenu()
        print("✓ Menu setup complete")

        // Start animation for connecting dots
        startAnimation()

        // Initialize VM sync service
        vmSyncService = VMSyncService()
        vmSyncService?.setProgressHandler { [weak self] progress in
            guard let self = self else { return }

            // Store current download progress for Preferences window
            self.currentVMDownloadProgress = progress

            // Update connection state based on download progress
            switch progress.status {
            case .downloading, .extracting:
                let percent = progress.percentComplete ?? 0.0
                self.connectionState = .downloading(percent: percent)
                self.updateIconForCurrentState()
            case .complete, .failed:
                // VM template ready or failed, proceed to worker initialization
                Task {
                    await self.initializeWorker()
                }
            case .idle:
                break
            }
        }

        // Start VM template sync in background
        Task {
            await vmSyncService?.ensureTemplateExists()
        }
    }

    private func initializeWorker() async {
        // Initialize worker service
        let config = WorkerConfiguration.load()
        workerService = WorkerService(configuration: config)

        // Set VM verification handler to ensure fresh verification before accepting builds
        await workerService?.setVMVerificationHandler { [weak self] () async -> Bool in
            guard let self = self else { return false }
            return await self.vmSyncService?.ensureFreshVerification() ?? false
        }

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

        // Preferences
        let settingsItem = NSMenuItem(title: "Preferences...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

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
        button.toolTip = toolTipForState(connectionState)
        // Template mode is now handled per-icon in creation methods
    }

    private func toolTipForState(_ state: ConnectionState) -> String {
        switch state {
        case .connecting:
            return "Free Agent - Connecting..."
        case .online:
            return "Free Agent - Online"
        case .building:
            if currentBuilds.isEmpty {
                return "Free Agent - Building"
            } else {
                let buildInfo = currentBuilds.map { "\($0.platform.uppercased())" }.joined(separator: ", ")
                return "Free Agent - Building \(buildInfo)"
            }
        case .downloading(let percent):
            return String(format: "Free Agent - Downloading base image (%.0f%%)", percent)
        case .offline:
            return "Free Agent - Offline"
        }
    }

    private func createIconForState(_ state: ConnectionState) -> NSImage {
        switch state {
        case .connecting:
            return createConnectingIcon()
        case .online:
            return createOnlineIcon()
        case .building:
            return createBuildingIcon()
        case .downloading(let percent):
            return createDownloadingIcon(percent: percent)
        case .offline:
            return createTrayIcon()
        }
    }

    private func createTrayIcon() -> NSImage {
        let traySize = NSSize(width: 18, height: 18)

        // Load SVG logo from Resources
        if let svgURL = Bundle.resources.url(forResource: "free-agent-logo", withExtension: "svg"),
           let svgImage = NSImage(contentsOf: svgURL) {
            let trayImage = NSImage(size: traySize, flipped: false) { rect in
                svgImage.draw(in: rect)
                return true
            }
            trayImage.isTemplate = true
            return trayImage
        }

        // Fallback: Simple block pattern if SVG not found
        let image = NSImage(size: traySize, flipped: false) { rect in
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

            return true
        }
        image.isTemplate = true
        return image
    }

    private func createConnectingIcon() -> NSImage {
        let size = NSSize(width: 18, height: 20)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw base logo
            let baseIcon = self.createTrayIcon()
            baseIcon.draw(in: NSRect(x: 0, y: 4, width: 18, height: 18))

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
        // Just use the same icon as offline - simple template icon with no badge
        return createTrayIcon()
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
        image.isTemplate = false  // Preserve green dot color
        return image
    }

    private func createDownloadingIcon(percent: Double) -> NSImage {
        let size = NSSize(width: 26, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw base logo
            let baseIcon = self.createTrayIcon()
            baseIcon.draw(in: NSRect(x: 4, y: 2, width: 18, height: 18))

            // Draw orange pie chart in bottom-right
            let pieSize: CGFloat = 12
            let pieRect = NSRect(x: size.width - pieSize - 2,
                                 y: 2,
                                 width: pieSize,
                                 height: pieSize)

            // Background circle (light gray)
            NSColor(calibratedWhite: 0.8, alpha: 1.0).setFill()
            NSBezierPath(ovalIn: pieRect).fill()

            // Progress arc (orange)
            NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.0, alpha: 1.0).setFill()
            let path = NSBezierPath()
            let center = NSPoint(x: pieRect.midX, y: pieRect.midY)
            let radius = pieSize / 2.0
            let startAngle: CGFloat = 90.0  // Start at top
            let endAngle = startAngle - (CGFloat(percent) / 100.0 * 360.0)  // Clockwise

            path.move(to: center)
            path.line(to: NSPoint(x: center.x, y: center.y + radius))
            path.appendArc(withCenter: center,
                          radius: radius,
                          startAngle: startAngle,
                          endAngle: endAngle,
                          clockwise: true)
            path.close()
            path.fill()

            // Border circle
            NSColor.black.setStroke()
            let borderPath = NSBezierPath(ovalIn: pieRect)
            borderPath.lineWidth = 0.5
            borderPath.stroke()

            return true
        }
        image.isTemplate = false  // Preserve orange color
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
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow?.close()
        settingsWindow = nil

        let progressBinding = Binding<DownloadProgress?>(
            get: { [weak self] in self?.currentVMDownloadProgress },
            set: { [weak self] newValue in self?.currentVMDownloadProgress = newValue }
        )

        let preferencesView = PreferencesView(
            configuration: WorkerConfiguration.load(),
            downloadProgress: progressBinding,
            onSave: { [weak self] config in
                Task { @MainActor in
                    await self?.workerService?.stop()
                    do {
                        try config.save()
                        let newService = WorkerService(configuration: config)
                        await newService.setVMVerificationHandler { [weak self] () async -> Bool in
                            guard let self = self else { return false }
                            return await self.vmSyncService?.ensureFreshVerification() ?? false
                        }
                        self?.workerService = newService
                    } catch {
                        print("Failed to save configuration: \(error)")
                        // TODO: Show error alert to user
                    }
                }
            }
        )

        let hostingController = NSHostingController(rootView: preferencesView)
        
        // Ensure the underlying NSView is transparent
        hostingController.view.layer?.backgroundColor = .clear
        
        let window = NSWindow(contentViewController: hostingController)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setContentSize(NSSize(width: 800, height: 600))
        window.center()

        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func showStatistics() {
        NSApp.activate(ignoringOtherApps: true)

        if statisticsWindow == nil {
            let statsView = StatisticsView(configuration: WorkerConfiguration.load())
            let hostingController = NSHostingController(rootView: statsView)
            
            // Ensure the underlying NSView is transparent
            hostingController.view.layer?.backgroundColor = .clear
            
            let window = NSWindow(contentViewController: hostingController)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.setContentSize(NSSize(width: 580, height: 720))
            window.center()
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            self.statisticsWindow = window
        }

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
