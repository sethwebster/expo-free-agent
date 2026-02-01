import SwiftUI
import DiagnosticsCore

/// Centralized app state manager
@MainActor
class AppState: ObservableObject {
    /// Current download progress (nil when not downloading)
    @Published var downloadProgress: DownloadProgress?

    /// Singleton instance
    static let shared = AppState()

    private init() {}

    /// Update download progress
    func updateProgress(_ progress: DownloadProgress) {
        downloadProgress = progress

        // Clear progress when complete or failed
        if progress.status == .complete || progress.status == .failed {
            // Keep it visible for a moment, then clear
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                if self.downloadProgress?.status == progress.status {
                    self.downloadProgress = nil
                }
            }
        }
    }

    /// Clear download progress
    func clearProgress() {
        downloadProgress = nil
    }
}
