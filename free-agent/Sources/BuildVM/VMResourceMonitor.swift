import Foundation

/// Monitors CPU and memory usage of Tart VM process
/// Sends telemetry snapshots to controller every 5 seconds
public actor VMResourceMonitor {
    private let vmName: String
    private let buildId: String
    private let workerId: String
    private let controllerURL: String
    private let apiKey: String
    private let tartPath: String

    private var monitorTask: Task<Void, Never>?
    private var isRunning = false

    public init(
        vmName: String,
        buildId: String,
        workerId: String,
        controllerURL: String,
        apiKey: String,
        tartPath: String = "/opt/homebrew/bin/tart"
    ) {
        self.vmName = vmName
        self.buildId = buildId
        self.workerId = workerId
        self.controllerURL = controllerURL
        self.apiKey = apiKey
        self.tartPath = tartPath
    }

    /// Start monitoring Tart VM process
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        monitorTask = Task {
            while !Task.isCancelled {
                do {
                    // Get Tart VM process PID
                    guard let pid = try await getTartVMPid() else {
                        // VM not running yet, wait and retry
                        try await Task.sleep(for: .seconds(5))
                        continue
                    }

                    // Get CPU and memory usage for the process
                    let (cpuPercent, memoryMB) = try await getProcessResourceUsage(pid: pid)

                    // Send snapshot to controller
                    await sendCpuSnapshot(cpuPercent: cpuPercent, memoryMB: memoryMB)

                    // Wait 5 seconds before next snapshot
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    // Log error but continue monitoring
                    print("Resource monitor error: \(error)")
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }

    /// Stop monitoring
    public func stop() {
        isRunning = false
        monitorTask?.cancel()
        monitorTask = nil
    }

    // MARK: - Private Helpers

    /// Get PID of Tart VM process
    private func getTartVMPid() async throws -> Int32? {
        // Use ps to find tart process running our VM
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ax", "-o", "pid,command"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        // Look for line with "tart run <vmName>"
        for line in output.components(separatedBy: "\n") {
            if line.contains("tart") && line.contains("run") && line.contains(vmName) {
                // Extract PID (first column)
                let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                if let pidStr = parts.first, let pid = Int32(pidStr) {
                    return pid
                }
            }
        }

        return nil
    }

    /// Get CPU and memory usage for a process using ps
    private func getProcessResourceUsage(pid: Int32) async throws -> (cpuPercent: Double, memoryMB: Double) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        // %cpu: CPU percentage, rss: resident set size in KB
        process.arguments = ["-p", "\(pid)", "-o", "%cpu,rss"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return (0, 0)
        }

        // Parse output (skip header line)
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count >= 2 else { return (0, 0) }

        let dataLine = lines[1].trimmingCharacters(in: .whitespaces)
        let parts = dataLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        guard parts.count >= 2,
              let cpu = Double(parts[0]),
              let rssKB = Double(parts[1]) else {
            return (0, 0)
        }

        let memoryMB = rssKB / 1024.0

        return (cpu, memoryMB)
    }

    /// Send CPU snapshot to controller
    private func sendCpuSnapshot(cpuPercent: Double, memoryMB: Double) async {
        let url = URL(string: "\(controllerURL)/api/builds/\(buildId)/telemetry")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(workerId, forHTTPHeaderField: "X-Worker-Id")
        request.setValue(buildId, forHTTPHeaderField: "X-Build-Id")

        let body: [String: Any] = [
            "type": "cpu_snapshot",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "data": [
                "cpu_percent": cpuPercent,
                "memory_mb": memoryMB
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("Failed to send CPU snapshot: HTTP \(httpResponse.statusCode)")
            }
        } catch {
            print("Error sending CPU snapshot: \(error)")
        }
    }
}
