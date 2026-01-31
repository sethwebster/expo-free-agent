import AppKit
import SwiftUI

// MARK: - HUD Notification Window

class HUDWindow: NSWindow {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.contentView = contentView
        self.level = .statusBar + 1  // Above menu bar
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - HUD Types

enum HUDType {
    case info
    case success
    case error
    case downloading(percent: Double)

    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .downloading: return "arrow.down.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .info: return .blue
        case .success: return .green
        case .error: return .red
        case .downloading: return .orange
        }
    }
}

// MARK: - HUD View

struct HUDNotificationView: View {
    let type: HUDType
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: type.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(type.color)

            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                // Progress bar for downloading
                if case .downloading(let percent) = type {
                    ProgressView(value: percent, total: 100.0)
                        .progressViewStyle(.linear)
                        .tint(type.color)
                        .frame(height: 4)
                }
            }

            Spacer()

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(16)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .padding(8)
    }
}

// MARK: - HUD Manager

@MainActor
class HUDNotificationManager {
    private var currentHUD: NSWindow?
    private var dismissTimer: Timer?

    func show(type: HUDType, message: String, duration: TimeInterval = 4.0) {
        // Dismiss existing HUD
        dismiss()

        // Create HUD view
        let hudView = HUDNotificationView(type: type, message: message) { [weak self] in
            self?.dismiss()
        }

        let hostingView = NSHostingView(rootView: hudView)
        hostingView.layer?.backgroundColor = .clear

        // Create window
        let window = HUDWindow(contentView: hostingView)

        // Position near top-right of screen (below menu bar)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let hudWidth: CGFloat = 320
            let hudHeight: CGFloat = type.hasProgress ? 96 : 80

            let x = screenFrame.maxX - hudWidth - 20
            let y = screenFrame.maxY - hudHeight - 10

            window.setFrame(NSRect(x: x, y: y, width: hudWidth, height: hudHeight), display: true)
        }

        // Animate in
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }

        currentHUD = window

        // Auto-dismiss after duration (unless it's a download in progress)
        if case .downloading = type {
            // Don't auto-dismiss downloads - they'll be updated or manually dismissed
        } else {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.dismiss()
                }
            }
        }
    }

    func updateDownloadProgress(percent: Double) {
        guard let window = currentHUD else { return }

        // Update existing HUD if it's a download type
        let hudView = HUDNotificationView(
            type: .downloading(percent: percent),
            message: String(format: "Downloading base image (%.0f%%)", percent)
        ) { [weak self] in
            self?.dismiss()
        }

        let hostingView = NSHostingView(rootView: hudView)
        hostingView.layer?.backgroundColor = .clear
        window.contentView = hostingView
    }

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
    }
}

// MARK: - Helper Extensions

extension HUDType {
    var hasProgress: Bool {
        if case .downloading = self {
            return true
        }
        return false
    }
}
