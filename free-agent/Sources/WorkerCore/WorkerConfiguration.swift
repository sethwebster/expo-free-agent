import Foundation

public struct WorkerConfiguration: Codable, Sendable {
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

    // Worker preferences
    public var autoStart: Bool
    public var onlyWhenIdle: Bool
    public var buildTimeoutMinutes: Int

    // Worker identity (generated on first run)
    public var workerID: String?
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
        autoStart: false,
        onlyWhenIdle: true,
        buildTimeoutMinutes: 120,
        workerID: nil,
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
              var config = try? JSONDecoder().decode(WorkerConfiguration.self, from: data) else {
            return .default
        }

        // Generate worker ID if missing
        if config.workerID == nil {
            config.workerID = UUID().uuidString
            config.deviceName = Host.current().localizedName
            config.save()
        }

        return config
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.configFileURL)
    }
}
