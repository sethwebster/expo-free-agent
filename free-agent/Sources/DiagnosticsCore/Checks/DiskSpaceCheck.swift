import Foundation

/// Check disk space (auto-fixable by deleting orphaned VMs)
public actor DiskSpaceCheck: DiagnosticCheck {
    public let name = "disk_space"
    public let autoFixable = true
    private let minFreeSpaceGB: Int64
    private let tartPath: String

    public init(minFreeSpaceGB: Int64 = 50, tartPath: String = "/opt/homebrew/bin/tart") {
        self.minFreeSpaceGB = minFreeSpaceGB
        self.tartPath = tartPath
    }

    public func run() async -> CheckResult {
        let startTime = Date()

        do {
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: homeDirectory.path)

            guard let freeSize = attributes[.systemFreeSize] as? Int64 else {
                let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                return CheckResult(
                    name: name,
                    status: .fail,
                    message: "Unable to determine free disk space",
                    durationMs: duration
                )
            }

            let freeGB = Double(freeSize) / 1_073_741_824.0 // Bytes to GB
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)

            if freeGB >= Double(minFreeSpaceGB) {
                return CheckResult(
                    name: name,
                    status: .pass,
                    message: String(format: "%.1f GB free (threshold: %.1f GB)", freeGB, Double(minFreeSpaceGB)),
                    durationMs: duration,
                    details: ["free_gb": String(format: "%.1f", freeGB), "threshold_gb": "\(minFreeSpaceGB)"]
                )
            } else {
                return CheckResult(
                    name: name,
                    status: .fail,
                    message: String(format: "Only %.1f GB free (threshold: %.1f GB)", freeGB, Double(minFreeSpaceGB)),
                    durationMs: duration,
                    details: ["free_gb": String(format: "%.1f", freeGB), "threshold_gb": "\(minFreeSpaceGB)"]
                )
            }
        } catch {
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            return CheckResult(
                name: name,
                status: .fail,
                message: "Error checking disk space: \(error.localizedDescription)",
                durationMs: duration
            )
        }
    }

    public func autoFix() async throws -> Bool {
        print("Attempting to free disk space by deleting orphaned VMs...")

        do {
            // List all VMs
            let (exitCode, output) = try await executeCommand(tartPath, ["list"])

            if exitCode != 0 {
                print("✗ Failed to list VMs")
                return false
            }

            // Find orphaned VMs (starting with "fa-")
            let vms = output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("fa-") }

            if vms.isEmpty {
                print("No orphaned VMs found to delete")
                return false
            }

            print("Found \(vms.count) orphaned VM(s): \(vms.joined(separator: ", "))")

            var deletedCount = 0
            for vm in vms {
                // Try to stop the VM first (ignore errors if already stopped)
                _ = try? await executeCommand(tartPath, ["stop", vm])

                // Delete the VM
                let (deleteExitCode, _) = try await executeCommand(tartPath, ["delete", vm])
                if deleteExitCode == 0 {
                    print("✓ Deleted VM: \(vm)")
                    deletedCount += 1
                } else {
                    print("✗ Failed to delete VM: \(vm)")
                }
            }

            return deletedCount > 0
        } catch {
            print("✗ Error during cleanup: \(error.localizedDescription)")
            return false
        }
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
