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
    private var consecutiveFailures = 0
    private let maxConsecutiveFailures = 5

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
        let output = try await runProcess("/bin/ps", args: ["-ax", "-o", "pid,command"])

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
        let output = try await runProcess("/bin/ps", args: ["-p", "\(pid)", "-o", "%cpu,rss"])

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

    /// Send CPU snapshot to controller with circuit breaker
    private func sendCpuSnapshot(cpuPercent: Double, memoryMB: Double) async {
        // Circuit breaker: stop trying after consecutive failures
        guard consecutiveFailures < maxConsecutiveFailures else {
            return
        }

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

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    consecutiveFailures = 0 // Reset on success
                } else {
                    consecutiveFailures += 1
                    print("Failed to send CPU snapshot: HTTP \(httpResponse.statusCode) (failures: \(consecutiveFailures)/\(maxConsecutiveFailures))")
                }
            }
        } catch {
            consecutiveFailures += 1
            print("Error sending CPU snapshot: \(error) (failures: \(consecutiveFailures)/\(maxConsecutiveFailures))")
            if consecutiveFailures >= maxConsecutiveFailures {
                print("Circuit breaker triggered - stopping telemetry after \(maxConsecutiveFailures) consecutive failures")
            }
        }
    }

    /// Run a process asynchronously without blocking the actor thread
    private func runProcess(_ executable: String, args: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { _ in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""

                continuation.resume(returning: output + error)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
