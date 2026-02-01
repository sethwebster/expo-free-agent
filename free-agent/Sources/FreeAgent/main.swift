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
            templateImage: "ghcr.io/sethwebster/expo-free-agent-base:0.1.27"
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

// MARK: - Minimal App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var vmSyncService: VMSyncService?
    private var menu: NSMenu?
    private var lastProgressUpdateTime: Date?
    private var lastProgressPercent: Double?
    private let appState = AppState.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 Starting Free Agent")

        // Initialize VM sync service to ensure template exists
        vmSyncService = VMSyncService()
        vmSyncService?.setProgressHandler { [weak self] progress in
            guard let self = self else { return }

            // Update centralized app state (for preferences pane, etc.)
            DispatchQueue.main.async { [weak self] in
                self?.appState.updateProgress(progress)
            }

            switch progress.status {
            case .idle:
                break

            case .downloading:
                let percent = progress.percentComplete ?? 0.0

                // Throttle UI updates to once per 0.5s or when percent changes by >= 1%
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }

                    let now = Date()
                    var shouldUpdate = false

                    if let lastUpdate = self.lastProgressUpdateTime, let lastPct = self.lastProgressPercent {
                        let timeSince = now.timeIntervalSince(lastUpdate)
                        let percentDiff = abs(percent - lastPct)
                        shouldUpdate = timeSince >= 0.5 || percentDiff >= 1.0
                    } else {
                        shouldUpdate = true
                    }

                    if shouldUpdate {
                        self.lastProgressUpdateTime = now
                        self.lastProgressPercent = percent
                        print(String(format: "Downloading: %.0f%%", percent))
                    }
                }

            case .extracting:
                let percent = progress.percentComplete ?? 0.0
                DispatchQueue.main.async {
                    print(String(format: "Extracting: %.0f%%", percent))
                }

            case .complete:
                DispatchQueue.main.async {
                    print("✓ VM template ready")
                }

            case .failed:
                DispatchQueue.main.async {
                    print("✗ VM template download failed: \(progress.message)")
                }
            }
        }

        Task {
            await vmSyncService?.ensureTemplateExists()
            print("✓ VM template check complete")
        }

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let statusItem = statusItem else {
            print("✗ Failed to create status item")
            return
        }

        // Set up button with custom icon
        if let button = statusItem.button {
            button.image = createIcon()
            print("✓ Set status item icon")
        }

        // Create menu
        let menu = NSMenu()
        menu.delegate = self
        self.menu = menu

        // Preferences menu item
        let settingsItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit menu item
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        // Attach menu to status item
        statusItem.menu = menu

        print("✓ Minimal app initialized")
    }

    @objc private func launchTestVM() {
        print("🚀 Launch Test VM clicked")

        let randomID = UUID().uuidString.prefix(8)
        let vmName = "fa-test-\(randomID)"
        let vmSetupPath = "/Users/sethwebster/Development/expo/expo-free-agent/vm-setup"

        print("VM Name: \(vmName)")
        print("Mount path: free-agent:\(vmSetupPath)")

        // Run in background thread
        DispatchQueue.global(qos: .userInitiated).async {
            // Clone the base image
            let cloneProcess = Process()
            cloneProcess.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/tart")
            cloneProcess.arguments = ["clone", "expo-free-agent-base", vmName]

            do {
                print("Cloning VM...")
                try cloneProcess.run()
                cloneProcess.waitUntilExit()

                if cloneProcess.terminationStatus == 0 {
                    print("✓ VM cloned successfully")

                    // Run the VM with directory mount
                    let runProcess = Process()
                    runProcess.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/tart")
                    runProcess.arguments = ["run", vmName, "--dir=free-agent:\(vmSetupPath)"]

                    print("Starting VM with mount...")
                    try runProcess.run()
                    print("✓ VM launched: \(vmName)")
                    print("✓ Directory mounted: free-agent:\(vmSetupPath)")
                } else {
                    print("✗ Failed to clone VM (exit code: \(cloneProcess.terminationStatus))")
                }
            } catch {
                print("✗ Error launching VM: \(error.localizedDescription)")
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Check if Option key is pressed
        let optionKeyPressed = NSEvent.modifierFlags.contains(.option)

        // Find if Launch Test VM item already exists
        let existingItem = menu.items.first { $0.action == #selector(launchTestVM) }

        if optionKeyPressed && existingItem == nil {
            // Add Launch Test VM item at the top
            let launchVMItem = NSMenuItem(
                title: "Launch Test VM",
                action: #selector(launchTestVM),
                keyEquivalent: ""
            )
            launchVMItem.target = self
            menu.insertItem(launchVMItem, at: 0)
            menu.insertItem(NSMenuItem.separator(), at: 1)
        } else if !optionKeyPressed && existingItem != nil {
            // Remove Launch Test VM item and its separator
            if let index = menu.items.firstIndex(where: { $0.action == #selector(launchTestVM) }) {
                menu.removeItem(at: index)
                // Remove separator if it's right after
                if index < menu.items.count && menu.items[index].isSeparatorItem {
                    menu.removeItem(at: index)
                }
            }
        }
    }

    @MainActor @objc private func showSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow?.close()
        settingsWindow = nil

        let preferencesView = PreferencesView(
            configuration: WorkerConfiguration.load(),
            onSave: { config in
                do {
                    try config.save()
                    print("✓ Configuration saved")
                } catch {
                    print("✗ Failed to save configuration: \(error)")
                }
            }
        )

        let hostingController = NSHostingController(rootView: preferencesView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Preferences"
        window.styleMask = [
            NSWindow.StyleMask.titled,
            NSWindow.StyleMask.closable,
            NSWindow.StyleMask.miniaturizable,
            NSWindow.StyleMask.resizable,
            NSWindow.StyleMask.fullSizeContentView
        ]
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.setContentSize(NSSize(width: 580, height: 720))
        window.center()
        window.level = NSWindow.Level.floating
        window.makeKeyAndOrderFront(self)

        settingsWindow = window
    }

    private func createIcon() -> NSImage {
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
}

// MARK: - App Startup

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
