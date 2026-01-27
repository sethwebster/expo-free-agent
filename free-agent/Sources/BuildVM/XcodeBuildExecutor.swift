import Foundation
import Virtualization
import Network

@available(macOS 14.0, *)
public class XcodeBuildExecutor {
    private let vm: VZVirtualMachine
    private let sshHost: String
    private let sshPort: Int
    private let sshUser: String
    private let sshKeyPath: URL

    public init(
        vm: VZVirtualMachine,
        sshHost: String = "192.168.64.2", // Default NAT IP
        sshPort: Int = 22,
        sshUser: String = "builder",
        sshKeyPath: URL? = nil
    ) {
        self.vm = vm
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUser = sshUser
        self.sshKeyPath = sshKeyPath ?? Self.defaultSSHKeyPath()
    }

    public func executeBuild(timeout: TimeInterval) async throws -> BuildExecutionResult {
        var logs = ""

        // Wait for SSH to be available
        logs += "Waiting for VM to be ready...\n"
        try await waitForSSH(timeout: 120)
        logs += "✓ VM is ready\n\n"

        logs += "Starting Expo build process...\n"

        do {
            // Navigate to project directory
            logs += try await executeCommand("cd /Users/builder/project", timeout: 30)

            // Step 1: Install dependencies
            logs += "Installing npm dependencies...\n"
            logs += try await executeCommand("npm install", timeout: 600)

            // Step 2: Install CocoaPods dependencies (iOS)
            logs += "Installing CocoaPods dependencies...\n"
            logs += try await executeCommand("cd ios && pod install && cd ..", timeout: 600)

            // Step 3: Run EAS build
            logs += "Running EAS build...\n"
            logs += try await executeCommand(
                "npx eas-cli build --platform ios --local --non-interactive",
                timeout: timeout
            )

            logs += "✓ Build completed successfully\n"
            return BuildExecutionResult(success: true, logs: logs)

        } catch {
            logs += "✗ Build failed: \(error)\n"
            return BuildExecutionResult(success: false, logs: logs)
        }
    }

    public func executeCommand(_ command: String, timeout: TimeInterval) async throws -> String {
        return try await executeViaSSH(command, timeout: timeout)
    }

    // MARK: - SSH Communication

    private func executeViaSSH(_ command: String, timeout: TimeInterval) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

        process.arguments = [
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "ConnectTimeout=10",
            "-p", "\(sshPort)",
            "-i", sshKeyPath.path,
            "\(sshUser)@\(sshHost)",
            command
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // Simple timeout using Task
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeout))
            if process.isRunning {
                process.terminate()
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        let exitCode = process.terminationStatus

        let outputData = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
        let errorData = try errorPipe.fileHandleForReading.readToEnd() ?? Data()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        if exitCode != 0 {
            throw ExecutorError.commandFailed(exitCode: Int(exitCode), output: output, error: error)
        }

        return output + error
    }

    private func waitForSSH(timeout: TimeInterval) async throws {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            do {
                _ = try await executeViaSSH("echo 'ready'", timeout: 5)
                return // SSH is available
            } catch {
                // Wait and retry
                try await Task.sleep(for: .seconds(2))
            }
        }

        throw ExecutorError.sshTimeout
    }

    private static func defaultSSHKeyPath() -> URL {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent(".ssh/free_agent_ed25519")
    }

    // MARK: - File Transfer

    public func copyFileToVM(localPath: URL, remotePath: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")

        process.arguments = [
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-P", "\(sshPort)",
            "-i", sshKeyPath.path,
            localPath.path,
            "\(sshUser)@\(sshHost):\(remotePath)"
        ]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw ExecutorError.fileTransferFailed(path: localPath.path)
        }
    }

    public func copyFileFromVM(remotePath: String, localPath: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")

        process.arguments = [
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-P", "\(sshPort)",
            "-i", sshKeyPath.path,
            "\(sshUser)@\(sshHost):\(remotePath)",
            localPath.path
        ]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw ExecutorError.fileTransferFailed(path: remotePath)
        }
    }

    public func copyDirectoryToVM(localPath: URL, remotePath: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")

        process.arguments = [
            "-r",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-P", "\(sshPort)",
            "-i", sshKeyPath.path,
            localPath.path,
            "\(sshUser)@\(sshHost):\(remotePath)"
        ]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw ExecutorError.fileTransferFailed(path: localPath.path)
        }
    }
}

public struct BuildExecutionResult: Sendable {
    public let success: Bool
    public let logs: String
}

enum ExecutorError: Error {
    case commandFailed(exitCode: Int, output: String, error: String)
    case timeout
    case sshTimeout
    case fileTransferFailed(path: String)
}
