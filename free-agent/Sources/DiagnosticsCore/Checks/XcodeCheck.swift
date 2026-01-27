import Foundation

/// Check if Xcode is installed and get version
public actor XcodeCheck: DiagnosticCheck {
    public let name = "xcode_version"
    public let autoFixable = false

    public init() {}

    public func run() async -> CheckResult {
        let startTime = Date()

        do {
            let (exitCode, output) = try await executeCommand("/usr/bin/xcodebuild", ["-version"])
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)

            if exitCode == 0 {
                // Parse version from output (e.g., "Xcode 16.1\nBuild version 16B40")
                let lines = output.components(separatedBy: .newlines)
                let versionLine = lines.first ?? "Unknown"

                return CheckResult(
                    name: name,
                    status: .pass,
                    message: versionLine,
                    durationMs: duration,
                    details: ["output": output.trimmingCharacters(in: .whitespacesAndNewlines)]
                )
            } else {
                return CheckResult(
                    name: name,
                    status: .fail,
                    message: "xcodebuild command failed",
                    durationMs: duration,
                    details: ["output": output]
                )
            }
        } catch {
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            return CheckResult(
                name: name,
                status: .fail,
                message: "Xcode not found or not installed",
                durationMs: duration,
                details: ["error": error.localizedDescription]
            )
        }
    }

    public func autoFix() async throws -> Bool {
        // Not auto-fixable - user must install Xcode manually
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
