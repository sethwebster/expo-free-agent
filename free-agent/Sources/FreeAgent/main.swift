import AppKit
import SwiftUI
import WorkerCore

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var workerService: WorkerService?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "Free Agent")
            button.image?.isTemplate = true
        }

        setupMenu()

        // Initialize worker service
        let config = WorkerConfiguration.load()
        workerService = WorkerService(configuration: config)

        // Auto-start worker if configured
        if config.autoStart {
            Task {
                await workerService?.start()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task {
            await workerService?.stop()
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        // Status
        menu.addItem(NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: ""))
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
                    config.save()
                    self?.workerService = WorkerService(configuration: config)
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
        // TODO: Implement statistics window
        let alert = NSAlert()
        alert.messageText = "Statistics"
        alert.informativeText = "Statistics feature coming soon"
        alert.runModal()
    }

    private func updateMenuStatus(running: Bool) {
        guard let menu = statusItem?.menu else { return }

        if let statusMenuItem = menu.item(at: 0) {
            statusMenuItem.title = running ? "Status: Running" : "Status: Idle"
        }

        if let toggleMenuItem = menu.item(at: 2) {
            toggleMenuItem.title = running ? "Stop Worker" : "Start Worker"
        }

        // Update icon color/appearance
        if let button = statusItem?.button {
            button.appearsDisabled = !running
        }
    }
}
