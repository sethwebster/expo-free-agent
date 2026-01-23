import Foundation

// Shared types for BuildVM
// Avoids circular dependency with WorkerCore

public struct BuildResult: Sendable {
    public let success: Bool
    public let logs: String
    public let artifactPath: URL?

    public init(success: Bool, logs: String, artifactPath: URL?) {
        self.success = success
        self.logs = logs
        self.artifactPath = artifactPath
    }
}

public struct VMConfiguration: Sendable {
    public let maxCPUPercent: Double
    public let maxMemoryGB: Double
    public let vmDiskSizeGB: Double
    public let reuseVMs: Bool
    public let cleanupAfterBuild: Bool
    public let buildTimeoutMinutes: Int

    public init(
        maxCPUPercent: Double,
        maxMemoryGB: Double,
        vmDiskSizeGB: Double,
        reuseVMs: Bool,
        cleanupAfterBuild: Bool,
        buildTimeoutMinutes: Int
    ) {
        self.maxCPUPercent = maxCPUPercent
        self.maxMemoryGB = maxMemoryGB
        self.vmDiskSizeGB = vmDiskSizeGB
        self.reuseVMs = reuseVMs
        self.cleanupAfterBuild = cleanupAfterBuild
        self.buildTimeoutMinutes = buildTimeoutMinutes
    }
}
