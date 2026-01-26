import Foundation

/// Manages Tart-based VMs for isolated Expo builds
/// Implements clone → run → build → destroy pattern
public class TartVMManager {
    private let configuration: VMConfiguration
    private let templateImage: String
    private let vmUser: String
    private let sshOptions: [String]
    private let tartPath: String

    private var vmName: String?
    private var vmIP: String?

    // Timeouts from runbook
    private let ipTimeout: TimeInterval = 120
    private let sshTimeout: TimeInterval = 180

    public init(configuration: VMConfiguration, templateImage: String = "expo-free-agent-tahoe-26.2-xcode-expo-54", vmUser: String = "admin", tartPath: String = "/opt/homebrew/bin/tart") {
        self.configuration = configuration
        self.templateImage = templateImage
        self.vmUser = vmUser
        self.tartPath = tartPath

        // SSH options from runbook to handle ephemeral VMs
        self.sshOptions = [
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=5",
            "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=3"
        ]
    }

    /// Execute build in ephemeral Tart VM
    /// CRITICAL: Always calls cleanup, even on failure
    /// signingCertsPath is now optional - VM fetches certs directly when nil
    public func executeBuild(
        sourceCodePath: URL,
        signingCertsPath: URL?,
        buildTimeout: TimeInterval,
        buildId: String?,
        workerId: String?,
        controllerURL: String?,
        apiKey: String?
    ) async throws -> BuildResult {
        var logs = ""
        var created = false
        var monitorPID: Int32?

        do {
            // 1) Clone template into ephemeral job VM
            let jobID = UUID().uuidString.prefix(8)
            vmName = "fa-\(jobID)"

            logs += "=== Tart VM Build ===\n"
            logs += "Template: \(templateImage)\n"
            logs += "VM: \(vmName!)\n\n"

            logs += "Cloning template...\n"
            try await executeCommand(tartPath, ["clone", templateImage, vmName!])
            created = true
            logs += "✓ VM cloned\n\n"

            // 2) Run headless, detached (using screen) with env vars for bootstrap
            logs += "Starting VM headless with secure bootstrap...\n"
            var runArgs = ["-d", "-m", tartPath, "run", vmName!, "--no-graphics"]

            // Add env vars for VM bootstrap (cert fetch)
            if let buildId = buildId {
                runArgs.append("--env")
                runArgs.append("BUILD_ID=\(buildId)")
            }
            if let workerId = workerId {
                runArgs.append("--env")
                runArgs.append("WORKER_ID=\(workerId)")
            }
            if let controllerURL = controllerURL {
                runArgs.append("--env")
                runArgs.append("CONTROLLER_URL=\(controllerURL)")
            }
            if let apiKey = apiKey {
                runArgs.append("--env")
                runArgs.append("API_KEY=\(apiKey)")
            }

            try await executeCommand("screen", runArgs)
            logs += "✓ VM started with secure bootstrap env vars\n\n"

            // 3) Wait for bootstrap completion (password randomization + cert fetch)
            logs += "Waiting for VM bootstrap (password randomization + cert fetch)...\n"
            try await waitForBootstrapComplete(vmName!, timeout: 180)
            logs += "✓ Bootstrap complete - certs installed, SSH blocked\n\n"

            // 4) Wait for IP
            logs += "Waiting for IP address...\n"
            vmIP = try await waitForIP(vmName!, timeout: ipTimeout)
            logs += "✓ IP: \(vmIP!)\n\n"

            // 5) Wait for SSH ready
            logs += "Waiting for SSH...\n"
            try await waitForSSH(ip: vmIP!, timeout: sshTimeout)
            logs += "✓ SSH ready\n\n"

            // 6) Verify Xcode ready (hard fail if missing)
            logs += "Verifying Xcode...\n"
            let xcodeVersion = try await sshCommand(ip: vmIP!, command: "xcodebuild -version")
            logs += xcodeVersion + "\n"

            let sdks = try await sshCommand(ip: vmIP!, command: "xcodebuild -showsdks")
            logs += sdks + "\n"
            logs += "✓ Xcode ready\n\n"

            // Belt+suspenders: force first-run steps (should be no-ops if baked correctly)
            _ = try? await sshCommand(ip: vmIP!, command: "sudo xcodebuild -license accept || true")
            _ = try? await sshCommand(ip: vmIP!, command: "sudo xcodebuild -runFirstLaunch || true")

            // 7) Verify Expo toolchain
            logs += "Verifying Expo toolchain...\n"
            let nodeVersion = try await sshCommand(ip: vmIP!, command: "node -v")
            logs += "Node: \(nodeVersion)\n"

            let npmVersion = try await sshCommand(ip: vmIP!, command: "npm -v")
            logs += "npm: \(npmVersion)\n"

            let expoVersion = try await sshCommand(ip: vmIP!, command: "npx --yes expo --version")
            logs += "Expo: \(expoVersion)\n"
            logs += "✓ Toolchain ready\n\n"

            // 8) Start build monitor (sends heartbeats to controller)
            if let buildId = buildId, let workerId = workerId, let controllerURL = controllerURL, let apiKey = apiKey {
                logs += "Starting build monitor...\n"
                let monitorCommand = "/usr/local/bin/vm-monitor.sh '\(controllerURL)' '\(buildId)' '\(workerId)' '\(apiKey)' 30 > /dev/null 2>&1 & echo $!"
                let pidOutput = try await sshCommand(ip: vmIP!, command: monitorCommand)
                if let pid = Int32(pidOutput.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    monitorPID = pid
                    logs += "✓ Monitor started (PID: \(pid))\n\n"
                } else {
                    logs += "⚠️  Could not start monitor\n\n"
                }
            }

            // 9) Prepare directories
            logs += "Preparing build directories...\n"
            _ = try await sshCommand(ip: vmIP!, command: "mkdir -p ~/free-agent/in ~/free-agent/out ~/free-agent/work")
            logs += "✓ Directories created\n\n"

            // 10) Upload source (certs already installed by bootstrap)
            logs += "Uploading source code...\n"
            try await scpUpload(localPath: sourceCodePath.path, remotePath: "~/free-agent/in/source.tar.gz", ip: vmIP!)
            logs += "✓ Source uploaded\n\n"

            // Note: Signing bundle upload removed - VM fetches certs directly via bootstrap
            if signingCertsPath != nil {
                logs += "⚠️  signingCertsPath provided but ignored - VM fetches certs securely via bootstrap\n\n"
            }

            // 11) Run build
            logs += "=== Starting build ===\n"
            let buildLogs = try await sshCommand(
                ip: vmIP!,
                command: "/usr/local/bin/free-agent-run-job --in ~/free-agent/in --out ~/free-agent/out",
                timeout: buildTimeout
            )
            logs += buildLogs + "\n"
            logs += "=== Build complete ===\n\n"

            // 12) Stop build monitor
            if let pid = monitorPID {
                logs += "Stopping build monitor...\n"
                _ = try? await sshCommand(ip: vmIP!, command: "kill \(pid) 2>/dev/null || true")
                logs += "✓ Monitor stopped\n\n"
            }

            // 13) Download artifacts
            logs += "Downloading artifacts...\n"

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("fa-\(jobID)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let artifactPath = tempDir.appendingPathComponent("artifact.ipa")
            let buildLogPath = tempDir.appendingPathComponent("xcodebuild.log")

            try await scpDownload(remotePath: "~/free-agent/out/artifact.ipa", localPath: artifactPath.path, ip: vmIP!)
            logs += "✓ Downloaded artifact.ipa\n"

            // Build log download is optional (may not exist on failure)
            do {
                try await scpDownload(remotePath: "~/free-agent/out/xcodebuild.log", localPath: buildLogPath.path, ip: vmIP!)
                logs += "✓ Downloaded xcodebuild.log\n"

                // Append VM build logs to our logs
                if let vmLogs = try? String(contentsOf: buildLogPath, encoding: .utf8) {
                    logs += "\n=== Xcodebuild logs ===\n"
                    logs += vmLogs
                    logs += "\n=== End Xcodebuild logs ===\n"
                }
            } catch {
                logs += "⚠ xcodebuild.log not available\n"
            }

            logs += "\n✓ Build succeeded\n"

            // Cleanup on success
            await cleanupVM(&logs, created: created)

            return BuildResult(success: true, logs: logs, artifactPath: artifactPath)

        } catch {
            logs += "\n✗ Build failed: \(error)\n"

            // Cleanup on error
            await cleanupVM(&logs, created: created)

            return BuildResult(success: false, logs: logs, artifactPath: nil)
        }
    }

    /// Cleanup VM (always called, even on error)
    private func cleanupVM(_ logs: inout String, created: Bool) async {
        guard created, let vm = vmName else { return }

        logs += "\nCleaning up VM...\n"

        // Best effort: ask guest to shutdown (optional)
        if let ip = vmIP {
            _ = try? await sshCommand(ip: ip, command: "sudo shutdown -h now", timeout: 5)
            logs += "✓ Shutdown requested\n"
        }

        // Hard guarantee: stop and delete VM
        do {
            // Stop VM first (tart delete requires VM to be stopped)
            _ = try? await executeCommand(tartPath, ["stop", vm])
            try await Task.sleep(for: .seconds(2))

            // Delete VM (no -f flag exists)
            try await executeCommand(tartPath, ["delete", vm])
            logs += "✓ VM deleted\n"
        } catch {
            logs += "⚠ Failed to delete VM: \(error)\n"
        }
    }

    /// Cleanup resources
    public func cleanup() async throws {
        // Cleanup is handled in finally block of executeBuild
        // This method exists for interface compatibility with VMManager
    }

    // MARK: - Helpers

    /// Wait for VM bootstrap to complete (password randomization + cert fetch)
    /// Polls for /tmp/free-agent-ready file via tart exec
    private func waitForBootstrapComplete(_ vmName: String, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            // Check if bootstrap signal file exists via tart exec
            let checkCmd = "test -f /tmp/free-agent-ready"
            let (code, _) = try await executeCommandWithResult(tartPath, ["exec", vmName, "--", checkCmd], timeout: 5)

            if code == 0 {
                return // Bootstrap complete
            }

            // Not ready yet, wait before next check
            try await Task.sleep(for: .seconds(2))
        }

        throw VMError.bootstrapTimeout
    }

    /// Wait for tart ip <vm> to return a valid IP
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

    /// Wait for SSH to be ready
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

    /// Execute SSH command
    private func sshCommand(ip: String, command: String, timeout: TimeInterval = 600) async throws -> String {
        var args = sshOptions
        args.append("\(vmUser)@\(ip)")
        args.append(command)

        let (code, output) = try await executeCommandWithResult("ssh", args, timeout: timeout)

        guard code == 0 else {
            throw VMError.sshFailed(output)
        }

        return output
    }

    /// SCP upload
    private func scpUpload(localPath: String, remotePath: String, ip: String) async throws {
        var args = sshOptions
        args.append(localPath)
        args.append("\(vmUser)@\(ip):\(remotePath)")

        let (code, output) = try await executeCommandWithResult("scp", args)

        guard code == 0 else {
            throw VMError.scpFailed(output)
        }
    }

    /// SCP download
    private func scpDownload(remotePath: String, localPath: String, ip: String) async throws {
        var args = sshOptions
        args.append("\(vmUser)@\(ip):\(remotePath)")
        args.append(localPath)

        let (code, output) = try await executeCommandWithResult("scp", args)

        guard code == 0 else {
            throw VMError.scpFailed(output)
        }
    }

    /// Execute command (no output capture)
    private func executeCommand(_ command: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw VMError.commandFailed("\(command) failed with exit code \(process.terminationStatus)")
        }
    }

    /// Execute command with output capture and exit code
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
            throw VMError.timeout("Command timeout: \(command)")
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        let combined = output + error

        return (process.terminationStatus, combined)
    }
}

// MARK: - Errors

extension VMError {
    static func timeout(_ message: String) -> VMError {
        .buildFailed
    }

    static func sshFailed(_ output: String) -> VMError {
        .buildFailed
    }

    static func scpFailed(_ output: String) -> VMError {
        .buildFailed
    }

    static func commandFailed(_ message: String) -> VMError {
        .buildFailed
    }
}
