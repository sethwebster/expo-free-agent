import Foundation

/// Check for stuck VMs (fa-* prefix) and auto-cleanup
/// Runs at startup and every 2 minutes to prevent VM limit issues
public actor StuckVMCheck: DiagnosticCheck {
    public let name = "stuck_vm_cleanup"
    public let autoFixable = true
    private let tartPath: String

    public init(tartPath: String = "/opt/homebrew/bin/tart") {
        self.tartPath = tartPath
    }

    public func run() async -> CheckResult {
        let startTime = Date()

        do {
            let stuckVMs = try await findStuckVMs()

            if stuckVMs.isEmpty {
                return CheckResult(
                    name: name,
                    status: .pass,
                    message: "No stuck VMs found",
                    durationMs: Int(Date().timeIntervalSince(startTime) * 1000),
                    details: [:]
                )
            }

            return CheckResult(
                name: name,
                status: .warn,
                message: "Found \(stuckVMs.count) stuck VM(s): \(stuckVMs.joined(separator: ", "))",
                durationMs: Int(Date().timeIntervalSince(startTime) * 1000),
                details: ["stuck_vms": stuckVMs.joined(separator: ",")]
            )
        } catch {
            return CheckResult(
                name: name,
                status: .fail,
                message: "Failed to check for stuck VMs: \(error.localizedDescription)",
                durationMs: Int(Date().timeIntervalSince(startTime) * 1000),
                details: ["error": error.localizedDescription]
            )
        }
    }

    public func autoFix() async throws -> Bool {
        let stuckVMs = try await findStuckVMs()

        guard !stuckVMs.isEmpty else {
            return true
        }

        print("🧹 Auto-fixing: Cleaning up \(stuckVMs.count) stuck VM(s)")

        var allSucceeded = true

        for vm in stuckVMs {
            do {
                try await forceCleanupVM(vm)
                print("  ✓ Cleaned up VM: \(vm)")
            } catch {
                print("  ✗ Failed to cleanup VM \(vm): \(error)")
                allSucceeded = false
            }
        }

        return allSucceeded
    }

    // MARK: - Private

    private func findStuckVMs() async throws -> [String] {
        let (code, output) = try await executeCommandWithResult(tartPath, ["list"])

        guard code == 0 else {
            throw VMCleanupError.commandFailed("tart list failed with code \(code)")
        }

        // Parse tart list output for VMs with fa-* prefix (excluding fa-test-* from diagnostics)
        let lines = output.split(separator: "\n")
        var stuckVMs: [String] = []

        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }

            let vmName = String(parts[1])

            // Match fa-* but exclude fa-test-* (diagnostic VMs clean themselves)
            if vmName.hasPrefix("fa-") && !vmName.hasPrefix("fa-test-") {
                stuckVMs.append(vmName)
            }
        }

        return stuckVMs
    }

    private func forceCleanupVM(_ vmName: String) async throws {
        // Step 1: Try to stop VM (ignore errors if already stopped)
        _ = try? await executeCommand(tartPath, ["stop", vmName])

        // Step 2: Wait a moment for clean shutdown
        try await Task.sleep(for: .seconds(2))

        // Step 3: Force delete (no -f flag in tart, but delete should work on stopped VM)
        try await executeCommand(tartPath, ["delete", vmName])
    }

    private func executeCommand(_ command: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw VMCleanupError.commandFailed("\(command) \(arguments.joined(separator: " ")) failed with code \(process.terminationStatus)")
        }
    }

    private func executeCommandWithResult(_ command: String, _ arguments: [String]) async throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments

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

enum VMCleanupError: Error {
    case commandFailed(String)
}
