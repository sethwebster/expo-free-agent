import Foundation

/// Check VM spawn/SSH/cleanup cycle (most comprehensive test)
public actor VMSpawnCheck: DiagnosticCheck {
    public let name = "vm_spawn_test"
    public let autoFixable = false
    private let tartPath: String
    private let templateImage: String
    private let vmUser: String
    private let sshOptions: [String]
    private let ipTimeout: TimeInterval = 120
    private let sshTimeout: TimeInterval = 180

    public init(
        tartPath: String = "/opt/homebrew/bin/tart",
        templateImage: String,
        vmUser: String = "admin"
    ) {
        self.tartPath = tartPath
        self.templateImage = templateImage
        self.vmUser = vmUser
        self.sshOptions = [
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=5",
            "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=3"
        ]
    }

    public func run() async -> CheckResult {
        let startTime = Date()
        let testID = UUID().uuidString.prefix(8)
        let vmName = "fa-test-\(testID)"
        var vmCreated = false

        do {
            // 1. Clone template
            try await executeCommand(tartPath, ["clone", templateImage, vmName])
            vmCreated = true

            // 2. Start VM headless
            try await executeCommand("screen", ["-d", "-m", tartPath, "run", vmName, "--no-graphics"])

            // 3. Wait for IP
            let vmIP = try await waitForIP(vmName, timeout: ipTimeout)

            // 4. Wait for SSH
            try await waitForSSH(ip: vmIP, timeout: sshTimeout)

            // 5. Test SSH command
            let result = try await sshCommand(ip: vmIP, command: "echo 'Diagnostic test'")
            guard result.contains("Diagnostic test") else {
                throw VMError.sshFailed("SSH command output mismatch")
            }

            // 6. Cleanup
            await cleanupVM(vmName)

            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            return CheckResult(
                name: name,
                status: .pass,
                message: "VM spawn/SSH test passed",
                durationMs: duration,
                details: [
                    "vm": vmName,
                    "template": templateImage,
                    "ip": vmIP
                ]
            )
        } catch VMError.timeout(let message) {
            if vmCreated {
                await cleanupVM(vmName)
            }
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            return CheckResult(
                name: name,
                status: .fail,
                message: "Timeout: \(message)",
                durationMs: duration,
                details: ["vm": vmName, "error": message]
            )
        } catch {
            if vmCreated {
                await cleanupVM(vmName)
            }
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            return CheckResult(
                name: name,
                status: .fail,
                message: "VM spawn test failed: \(error.localizedDescription)",
                durationMs: duration,
                details: ["vm": vmName, "error": error.localizedDescription]
            )
        }
    }

    public func autoFix() async throws -> Bool {
        // Not auto-fixable - VM spawn issues require manual investigation
        return false
    }

    // MARK: - Helpers

    private func waitForIP(_ vmName: String, timeout: TimeInterval) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let (code, output) = try await executeCommandWithResult(tartPath, ["ip", vmName])
            let ip = output.trimmingCharacters(in: .whitespacesAndNewlines)

            if code == 0 && !ip.isEmpty {
                return ip
            }

            try await Task.sleep(for: .seconds(1))
        }

        throw VMError.timeout("Timed out waiting for VM IP")
    }

    private func waitForSSH(ip: String, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            do {
                let result = try await sshCommand(ip: ip, command: "echo SSH_READY", timeout: 5)
                if result.contains("SSH_READY") {
                    return
                }
            } catch {
                // SSH not ready yet, keep waiting
            }

            try await Task.sleep(for: .seconds(2))
        }

        throw VMError.timeout("Timed out waiting for SSH")
    }

    private func sshCommand(ip: String, command: String, timeout: TimeInterval = 30) async throws -> String {
        var args = sshOptions
        args.append("\(vmUser)@\(ip)")
        args.append(command)

        let (code, output) = try await executeCommandWithResult("ssh", args, timeout: timeout)

        guard code == 0 else {
            throw VMError.sshFailed(output)
        }

        return output
    }

    private func cleanupVM(_ vmName: String) async {
        // Stop VM
        _ = try? await executeCommand(tartPath, ["stop", vmName])
        try? await Task.sleep(for: .seconds(2))

        // Delete VM
        _ = try? await executeCommand(tartPath, ["delete", vmName])
    }

    private func executeCommand(_ command: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw VMError.commandFailed(command: command, exitCode: process.terminationStatus)
        }
    }

    private func executeCommandWithResult(_ command: String, _ arguments: [String], timeout: TimeInterval = 30) async throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // Wait with timeout
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }

        if process.isRunning {
            process.terminate()
            throw VMError.timeout("Command timed out: \(command)")
        }

        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        return (process.terminationStatus, output.isEmpty ? error : output)
    }
}

// MARK: - Errors

enum VMError: Error {
    case timeout(String)
    case sshFailed(String)
    case scpFailed(String)
    case commandFailed(command: String, exitCode: Int32)
}
