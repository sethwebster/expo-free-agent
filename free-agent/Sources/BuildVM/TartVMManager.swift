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
    private var resourceMonitor: VMResourceMonitor?
    private var vmProcess: Process?  // Keep VM process alive in background

    // Timeouts from runbook
    private let ipTimeout: TimeInterval = 120
    private let sshTimeout: TimeInterval = 180

    public init(configuration: VMConfiguration, templateImage: String = "ghcr.io/sethwebster/expo-free-agent-base:0.1.26", vmUser: String = "admin", tartPath: String = "/opt/homebrew/bin/tart") {
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
        print("TartVMManager.executeBuild() started")
        print("  sourceCodePath: \(sourceCodePath.path)")
        print("  buildTimeout: \(buildTimeout)s")
        print("  buildId: \(buildId ?? "nil")")
        print("  workerId: \(workerId ?? "nil")")
        print("  controllerURL: \(controllerURL ?? "nil")")

        var logs = ""
        var created = false
        var monitorPID: Int32?

        // Validate inputs to prevent command injection
        print("Validating inputs...")
        if let buildId = buildId {
            guard buildId.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else {
                print("✗ Invalid buildId: \(buildId)")
                throw VMError.invalidInput("buildId contains invalid characters")
            }
        }
        if let workerId = workerId {
            guard workerId.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else {
                throw VMError.invalidInput("workerId contains invalid characters")
            }
        }
        if let apiKey = apiKey {
            guard apiKey.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else {
                throw VMError.invalidInput("apiKey contains invalid characters")
            }
        }
        if let controllerURL = controllerURL {
            guard controllerURL.range(of: "^https?://[a-zA-Z0-9._:-]+(/[a-zA-Z0-9._/-]*)?$", options: .regularExpression) != nil else {
                throw VMError.invalidInput("controllerURL is not a valid HTTP/HTTPS URL")
            }
        }

        do {
            // 1) Clone template into ephemeral job VM
            print("Step 1: Cloning VM template...")
            let jobID = UUID().uuidString.prefix(8)
            vmName = "fa-\(jobID)"

            logs += "=== Tart VM Build ===\n"
            logs += "Template: \(templateImage)\n"
            logs += "VM: \(vmName!)\n\n"

            logs += "Cloning template...\n"
            print("Executing: \(tartPath) clone \(templateImage) \(vmName!)")
            try await executeCommand(tartPath, ["clone", templateImage, vmName!])
            created = true
            logs += "✓ VM cloned\n\n"
            print("✓ VM cloned successfully")

            // 2) Create config file for VM with build credentials
            print("Step 2: Creating VM config...")
            let configDir = FileManager.default.temporaryDirectory.appendingPathComponent("build-\(jobID)")
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

            let configFile = configDir.appendingPathComponent("config")
            var configContent = ""
            if let buildId = buildId {
                configContent += "BUILD_ID=\(buildId)\n"
            }
            if let workerId = workerId {
                configContent += "WORKER_ID=\(workerId)\n"
            }
            if let controllerURL = controllerURL {
                configContent += "CONTROLLER_URL=\(controllerURL)\n"
            }
            if let apiKey = apiKey {
                configContent += "OTP=\(apiKey)\n"
            }

            try configContent.write(to: configFile, atomically: true, encoding: .utf8)
            logs += "✓ Config written to \(configFile.path)\n\n"
            print("✓ Config file created at \(configFile.path)")

            // 3) Run headless in background (without screen, so tart ip works)
            print("Step 3: Starting VM headless with config mount...")
            logs += "Starting VM headless with config...\n"

            // Run tart directly in background (not in screen) so `tart ip` can track it
            vmProcess = Process()
            vmProcess!.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            vmProcess!.arguments = [tartPath, "run", vmName!, "--no-graphics", "--dir", "\(configDir.path):ro,tag=build-config"]

            // Redirect I/O to prevent blocking and avoid terminal interaction
            vmProcess!.standardInput = FileHandle.nullDevice
            vmProcess!.standardOutput = FileHandle.nullDevice
            vmProcess!.standardError = FileHandle.nullDevice

            print("Executing: \(tartPath) run \(vmName!) --no-graphics --dir \(configDir.path):ro,tag=build-config")
            try vmProcess!.run()
            logs += "✓ VM started (PID: \(vmProcess!.processIdentifier))\n\n"
            print("✓ VM started in background (PID: \(vmProcess!.processIdentifier))")

            // Give VM process a moment to initialize
            try await Task.sleep(for: .seconds(2))

            // Verify process is still running
            if vmProcess!.isRunning {
                print("✓ VM process verified running")
            } else {
                print("✗ VM process already terminated!")
                throw VMError.commandFailed("VM process terminated immediately after start")
            }

            // 2.5) Start resource monitor if we have credentials
            print("Step 2.5: Starting resource monitor...")
            if let buildId = buildId, let workerId = workerId, let controllerURL = controllerURL, let apiKey = apiKey {
                logs += "Starting resource monitor...\n"
                resourceMonitor = VMResourceMonitor(
                    vmName: vmName!,
                    buildId: buildId,
                    workerId: workerId,
                    controllerURL: controllerURL,
                    apiKey: apiKey,
                    tartPath: tartPath
                )
                await resourceMonitor?.start()
                logs += "✓ Resource monitor started\n\n"
                print("✓ Resource monitor started")
            }

            // 3) Wait for VM to boot and get SSH access (skip bootstrap for now)
            print("Step 3: Waiting for VM to boot...")
            logs += "Waiting for VM to boot...\n"

            // 4) Wait for IP
            logs += "Waiting for IP address...\n"
            vmIP = try await waitForIP(vmName!, timeout: ipTimeout)
            logs += "✓ IP: \(vmIP!)\n\n"

            // 5) Wait for SSH ready
            logs += "Waiting for SSH...\n"
            try await waitForSSH(ip: vmIP!, timeout: sshTimeout)
            logs += "✓ SSH ready\n\n"

            // 5.5) Run bootstrap with env vars via SSH (fetches certs, randomizes password)
            if let buildId = buildId, let workerId = workerId, let controllerURL = controllerURL, let apiKey = apiKey {
                logs += "Running VM bootstrap with credentials...\n"
                let bootstrapCmd = """
                BUILD_ID=\(buildId) WORKER_ID=\(workerId) CONTROLLER_URL=\(controllerURL) API_KEY=\(apiKey) \
                /usr/local/bin/free-agent-vm-bootstrap 2>&1 || true
                """
                let bootstrapOutput = try await sshCommand(ip: vmIP!, command: bootstrapCmd, timeout: 180)
                logs += bootstrapOutput + "\n"

                // Check if bootstrap succeeded
                let checkReady = try await sshCommand(ip: vmIP!, command: "test -f /tmp/free-agent-ready && echo 'ready' || echo 'not ready'")
                if checkReady.trimmingCharacters(in: .whitespacesAndNewlines) == "ready" {
                    logs += "✓ Bootstrap complete - certs fetched\n\n"
                } else {
                    logs += "⚠️  Bootstrap may have failed, continuing anyway\n\n"
                }
            }

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

                // Write credentials to temp file (avoid ps visibility)
                let credFile = "/tmp/monitor-creds-\(UUID().uuidString)"
                let createCredsCmd = """
                cat > '\(credFile)' << 'EOFCREDS'
                CONTROLLER_URL=\(controllerURL)
                BUILD_ID=\(buildId)
                WORKER_ID=\(workerId)
                API_KEY=\(apiKey)
                EOFCREDS
                chmod 600 '\(credFile)'
                """
                _ = try await sshCommand(ip: vmIP!, command: createCredsCmd)

                // Start monitor with creds file (not visible in ps)
                let monitorCommand = "/usr/local/bin/vm-monitor.sh '\(credFile)' 30 > /dev/null 2>&1 & echo $!"
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

            // 11) Pass credentials to build script for log streaming
            if let buildId = buildId, let workerId = workerId, let controllerURL = controllerURL, let apiKey = apiKey {
                logs += "Setting up log streaming credentials...\n"
                let credFile = "/tmp/build-creds-\(UUID().uuidString)"
                let createCredsCmd = """
                cat > '\(credFile)' << 'EOFCREDS'
                export CONTROLLER_URL=\(controllerURL)
                export BUILD_ID=\(buildId)
                export WORKER_ID=\(workerId)
                export API_KEY=\(apiKey)
                EOFCREDS
                chmod 600 '\(credFile)'
                """
                _ = try await sshCommand(ip: vmIP!, command: createCredsCmd)
                logs += "✓ Credentials configured\n\n"

                // 12) Run build with credentials sourced
                logs += "=== Starting build ===\n"
                let buildLogs = try await sshCommand(
                    ip: vmIP!,
                    command: "source '\(credFile)' && /usr/local/bin/free-agent-run-job --in ~/free-agent/in --out ~/free-agent/out; rm -f '\(credFile)'",
                    timeout: buildTimeout
                )
                logs += buildLogs + "\n"
                logs += "=== Build complete ===\n\n"
            } else {
                // Fallback: run without log streaming
                logs += "=== Starting build (no log streaming) ===\n"
                let buildLogs = try await sshCommand(
                    ip: vmIP!,
                    command: "/usr/local/bin/free-agent-run-job --in ~/free-agent/in --out ~/free-agent/out",
                    timeout: buildTimeout
                )
                logs += buildLogs + "\n"
                logs += "=== Build complete ===\n\n"
            }

            // 13) Stop build monitor
            if let pid = monitorPID {
                logs += "Stopping build monitor...\n"
                _ = try? await sshCommand(ip: vmIP!, command: "kill \(pid) 2>/dev/null || true")
                logs += "✓ Monitor stopped\n\n"
            }

            // 14) Download artifacts
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
        // Stop resource monitor
        if let monitor = resourceMonitor {
            logs += "\nStopping resource monitor...\n"
            await monitor.stop()
            resourceMonitor = nil
            logs += "✓ Resource monitor stopped\n"
        }

        // Terminate VM process if still running
        if let process = vmProcess, process.isRunning {
            logs += "Terminating VM process...\n"
            process.terminate()
            vmProcess = nil
            logs += "✓ VM process terminated\n"
        }

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
        var attemptCount = 0

        while Date() < deadline {
            attemptCount += 1
            let (code, output) = try await executeCommandWithResult(tartPath, ["ip", vmName])
            let ip = output.trimmingCharacters(in: .whitespacesAndNewlines)

            print("waitForIP attempt \(attemptCount): code=\(code), output='\(output)', ip='\(ip)'")

            if code == 0 && !ip.isEmpty {
                print("✓ Got IP: \(ip)")
                return ip
            }

            if attemptCount % 10 == 0 {
                print("Still waiting for IP after \(attemptCount) attempts...")
            }

            try await Task.sleep(for: .seconds(1))
        }

        throw VMError.timeout("Timed out waiting for VM IP after \(attemptCount) attempts")
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

        // Capture output for debugging
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            let combined = (output + error).trimmingCharacters(in: .whitespacesAndNewlines)

            print("✗ Command failed: \(command) \(arguments.joined(separator: " "))")
            print("✗ Exit code: \(process.terminationStatus)")
            if !combined.isEmpty {
                print("✗ Output: \(combined)")
            }

            throw VMError.commandFailed("\(command) failed with exit code \(process.terminationStatus): \(combined)")
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
