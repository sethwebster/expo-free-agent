import Foundation

public struct WorkerConfiguration: Codable, Sendable, Equatable {
    // Controller settings
    public var controllerURL: String
    public var apiKey: String
    public var pollIntervalSeconds: Int

    // Resource limits
    public var maxCPUPercent: Double
    public var maxMemoryGB: Double
    public var maxConcurrentBuilds: Int

    // VM settings
    public var vmDiskSizeGB: Double
    public var reuseVMs: Bool
    public var cleanupAfterBuild: Bool
    public var templateImage: String?  // Optional override for VM base image

    // Worker preferences
    public var autoStart: Bool
    public var onlyWhenIdle: Bool
    public var buildTimeoutMinutes: Int

    // Worker identity (generated on first run)
    public var workerID: String?
    public var accessToken: String?  // Short-lived token for worker authentication
    public var publicIdentifier: String?  // Unique identifier safe for public display (no PII)
    public var deviceName: String?

    public static let `default` = WorkerConfiguration(
        controllerURL: "https://expo-free-agent-controller.projects.sethwebster.com",
        apiKey: "",
        pollIntervalSeconds: 30,
        maxCPUPercent: 70,
        maxMemoryGB: 8,
        maxConcurrentBuilds: 1,
        vmDiskSizeGB: 50,
        reuseVMs: false,
        cleanupAfterBuild: true,
        templateImage: nil,
        autoStart: false,
        onlyWhenIdle: true,
        buildTimeoutMinutes: 120,
        workerID: nil,
        accessToken: nil,
        publicIdentifier: nil,
        deviceName: nil
    )

    private static var configFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let freeAgentDir = appSupport.appendingPathComponent("FreeAgent")
        try? FileManager.default.createDirectory(at: freeAgentDir, withIntermediateDirectories: true)
        return freeAgentDir.appendingPathComponent("config.json")
    }

    public static func load() -> WorkerConfiguration {
        guard let data = try? Data(contentsOf: configFileURL),
              let config = try? JSONDecoder().decode(WorkerConfiguration.self, from: data) else {
            return .default
        }

        // Controller is the sole authority for worker IDs - don't generate locally
        return config
    }

    public func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.configFileURL)
    }
}
