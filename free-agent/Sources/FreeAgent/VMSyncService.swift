import Foundation
import DiagnosticsCore

@MainActor
class VMSyncService {
    private let templateImage: String
    private var onProgressUpdate: ((DownloadProgress) -> Void)?
    private var isRunning = false
    private var lastVerifiedAt: Date?
    private let maxVerificationAge: TimeInterval = 5 * 60  // 5 minutes

    init(templateImage: String = "ghcr.io/sethwebster/expo-free-agent-base:0.1.31") {
        self.templateImage = templateImage
    }

    /// Returns true if VM template was verified within the last 5 minutes
    func isVerificationFresh() -> Bool {
        guard let lastVerified = lastVerifiedAt else {
            return false
        }
        return Date().timeIntervalSince(lastVerified) < maxVerificationAge
    }

    /// Ensures VM template is verified and fresh before accepting builds
    func ensureFreshVerification() async -> Bool {
        if isVerificationFresh() {
            return true
        }

        // Verification is stale, re-check
        await ensureTemplateExists()
        return lastVerifiedAt != nil
    }

    func setProgressHandler(_ handler: @escaping (DownloadProgress) -> Void) {
        self.onProgressUpdate = handler
    }

    func ensureTemplateExists() async {
        guard !isRunning else { return }
        isRunning = true

        let check = TemplateVMCheck(templateImage: templateImage)

        // Set up progress handler
        await check.setProgressHandler { [weak self] progress in
            Task { @MainActor in
                self?.onProgressUpdate?(progress)
            }
        }

        let result = await check.run()

        if result.status == .fail {
            // Template doesn't exist, download it
            do {
                let success = try await check.autoFix()
                if success {
                    lastVerifiedAt = Date()
                }
            } catch {
                Task { @MainActor in
                    onProgressUpdate?(DownloadProgress(
                        status: .failed,
                        message: "Failed to download template: \(error.localizedDescription)"
                    ))
                }
            }
        } else {
            // Template exists and verified
            lastVerifiedAt = Date()
            Task { @MainActor in
                onProgressUpdate?(DownloadProgress(
                    status: .complete,
                    message: "VM template ready"
                ))
            }
        }

        isRunning = false
    }
}
