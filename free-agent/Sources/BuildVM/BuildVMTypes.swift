import Foundation

// Shared types for BuildVM
// Avoids circular dependency with WorkerCore

public enum VMError: Error, LocalizedError {
    case virtualizationNotSupported
    case vmNotInitialized
    case invalidHardwareModel
    case invalidMachineIdentifier
    case installationFailed
    case buildFailed
    case artifactNotFound
    case bootstrapTimeout
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case .virtualizationNotSupported:
            return "Virtualization is not supported on this system"
        case .vmNotInitialized:
            return "VM not initialized"
        case .invalidHardwareModel:
            return "Invalid hardware model"
        case .invalidMachineIdentifier:
            return "Invalid machine identifier"
        case .installationFailed:
            return "Installation failed"
        case .buildFailed:
            return "Build failed"
        case .artifactNotFound:
            return "Artifact not found"
        case .bootstrapTimeout:
            return "VM bootstrap timed out - check /tmp/free-agent-bootstrap.log in VM"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        }
    }
}

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
