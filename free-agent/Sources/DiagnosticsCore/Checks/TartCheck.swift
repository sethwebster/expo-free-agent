import Foundation

/// Check if Tart is installed and get version
public actor TartCheck: DiagnosticCheck {
    public let name = "tart_installed"
    public let autoFixable = false
    private let tartPath: String

    public init(tartPath: String = "/opt/homebrew/bin/tart") {
        self.tartPath = tartPath
    }

    public func run() async -> CheckResult {
        let startTime = Date()

        // Check if tart executable exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: tartPath) else {
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            return CheckResult(
                name: name,
                status: .fail,
                message: "Tart not found at \(tartPath)",
                durationMs: duration,
                details: ["path": tartPath]
            )
        }

        // Get tart version
        do {
            let (exitCode, output) = try await executeCommand(tartPath, ["--version"])
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)

            if exitCode == 0 {
                let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return CheckResult(
                    name: name,
                    status: .pass,
                    message: "Tart \(version) installed",
                    durationMs: duration,
                    details: ["version": version, "path": tartPath]
                )
            } else {
                return CheckResult(
                    name: name,
                    status: .fail,
                    message: "Tart command failed",
                    durationMs: duration,
                    details: ["output": output]
                )
            }
        } catch {
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            return CheckResult(
                name: name,
                status: .fail,
                message: "Error checking Tart: \(error.localizedDescription)",
                durationMs: duration
            )
        }
    }

    public func autoFix() async throws -> Bool {
        // Not auto-fixable - user must install Tart manually
        return false
    }

    private func executeCommand(_ command: String, _ arguments: [String]) async throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        return (process.terminationStatus, output.isEmpty ? error : output)
    }
}
