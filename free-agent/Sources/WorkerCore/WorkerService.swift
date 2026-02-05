import Foundation
import BuildVM

@available(macOS 14.0, *)
public actor WorkerService {
    private var configuration: WorkerConfiguration
    private var isActive = false
    private var pollingTask: Task<Void, Never>?
    private var activeBuilds: [String: Task<Void, Never>] = [:]
    private var vmVerificationHandler: (@Sendable () async -> Bool)?
    private var isReregistering = false

    // Exponential backoff state (resets on success)
    private var currentBackoffDelay: UInt64 = 1_000_000_000 // 1 second in nanoseconds
    private let minBackoffDelay: UInt64 = 1_000_000_000 // 1 second
    private let maxBackoffDelay: UInt64 = 60_000_000_000 // 60 seconds

    public var isRunning: Bool { isActive }

    public init(configuration: WorkerConfiguration) {
        self.configuration = configuration
    }

    /// Set a handler to verify VM template freshness before accepting builds
    public func setVMVerificationHandler(_ handler: @escaping @Sendable () async -> Bool) {
        self.vmVerificationHandler = handler
    }

    public func start() async {
        guard !isActive else { return }

        print("Worker service starting...")

        // Register with controller - retry with exponential backoff on failure
        var attempt = 0
        let maxAttempts = 10

        while attempt < maxAttempts {
            do {
                try await registerWorker()
                print("✓ Worker registered successfully")
                resetBackoff() // Reset backoff on success
                break
            } catch {
                attempt += 1
                if attempt >= maxAttempts {
                    print("FATAL: Registration failed after \(maxAttempts) attempts: \(error)")
                    print("Worker service cannot start without valid registration")
                    return
                }

                // Log the failure and wait before retry
                print("⚠️  Registration attempt \(attempt) failed: \(error)")
                print("   Retrying in \(currentBackoffDelay / 1_000_000_000)s...")

                try? await Task.sleep(nanoseconds: currentBackoffDelay)

                increaseBackoff()
            }
        }

        isActive = true

        // Start polling loop
        pollingTask = Task {
            await pollLoop()
        }

        print("Worker service started")
    }

    private func resetBackoff() {
        currentBackoffDelay = minBackoffDelay
    }

    private func increaseBackoff() {
        currentBackoffDelay = min(currentBackoffDelay * 2, maxBackoffDelay)
    }

    public func stop() async {
        guard isActive else { return }

        print("Worker service stopping...")
        isActive = false

        // Cancel polling
        pollingTask?.cancel()
        pollingTask = nil

        // Wait for active builds to complete
        for (jobID, task) in activeBuilds {
            print("Waiting for build \(jobID) to complete...")
            task.cancel()
            await task.value
        }
        activeBuilds.removeAll()

        // Unregister from controller
        await unregisterWorker()

        print("Worker service stopped")
    }

    private func pollLoop() async {
        while !Task.isCancelled && isActive {
            do {
                // Skip polling during re-registration to avoid state corruption
                if isReregistering {
                    print("Re-registration in progress, skipping poll")
                    try await Task.sleep(for: .seconds(configuration.pollIntervalSeconds))
                    continue
                }

                // Check if we can accept more builds
                if activeBuilds.count < configuration.maxConcurrentBuilds {
                    // Verify VM template is fresh (< 5 min old) before accepting builds
                    if let verificationHandler = vmVerificationHandler {
                        let isVMFresh = await verificationHandler()
                        if !isVMFresh {
                            print("VM template verification stale or failed, skipping poll")
                            try await Task.sleep(for: .seconds(configuration.pollIntervalSeconds))
                            continue
                        }
                    }

                    if let job = try await pollForJob() {
                        resetBackoff() // Reset backoff on successful poll
                        await executeJob(job)
                    } else {
                        resetBackoff() // Also reset on successful no-job response
                    }
                } else {
                    resetBackoff() // Reset when at capacity (not an error)
                }

                // Wait for next poll interval
                try await Task.sleep(for: .seconds(configuration.pollIntervalSeconds))
            } catch {
                if !Task.isCancelled {
                    print("⚠️  Poll error: \(error)")
                    print("   Retrying in \(currentBackoffDelay / 1_000_000_000)s...")

                    // Exponential backoff on error
                    try? await Task.sleep(nanoseconds: currentBackoffDelay)
                    increaseBackoff()
                }
            }
        }
    }

    private func registerWorker() async throws {
        // Snapshot active build count before registration
        let activeBuildCount = activeBuilds.count
        print("Registration attempt with \(activeBuildCount) active builds")

        let url = URL(string: "\(configuration.controllerURL)/api/workers/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")

        // Controller expects: { name, capabilities }
        // Send existing worker ID if available for idempotent registration
        var payload: [String: Any] = [
            "name": configuration.deviceName ?? Host.current().localizedName ?? "Unknown",
            "capabilities": [
                "platforms": ["ios"],
                "maxConcurrentBuilds": configuration.maxConcurrentBuilds,
                "maxMemoryGB": configuration.maxMemoryGB,
                "maxCPUPercent": configuration.maxCPUPercent,
                "xcode_version": "15.0"
            ],
            "active_build_count": activeBuildCount
        ]

        // Include existing worker ID if we have one (for re-registration)
        if let existingId = configuration.workerID {
            payload["id"] = existingId
        }

        print("Registering worker (current ID: \(configuration.workerID ?? "nil"))")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkerError.buildFailed(reason: "Invalid response from controller")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw WorkerError.buildFailed(reason: "Registration failed with status \(httpResponse.statusCode): \(body)")
        }

        // Controller returns { id, access_token, status } - save both
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assignedId = json["id"] as? String,
              let accessToken = json["access_token"] as? String else {
            throw WorkerError.buildFailed(reason: "Missing worker ID or access token in registration response")
        }

        print("Parsed ID from response: '\(assignedId)' (length: \(assignedId.count))")
        print("Received access token (length: \(accessToken.count))")

        // CRITICAL: Update configuration atomically
        configuration.workerID = assignedId
        configuration.accessToken = accessToken
        do {
            try configuration.save()
            print("✓ Registered with controller (ID: \(assignedId))")
            print("Configuration workerID is now: '\(configuration.workerID ?? "nil")'")
        } catch {
            // Revert in-memory changes if save fails
            configuration.workerID = nil
            configuration.accessToken = nil
            throw WorkerError.buildFailed(reason: "Failed to persist worker credentials: \(error.localizedDescription)")
        }
    }

    private func unregisterWorker() async {
        guard let accessToken = configuration.accessToken else {
            print("No access token, skipping unregister")
            return
        }

        do {
            // Send LEAVE notice to controller - reassigns active builds to pending
            let url = URL(string: "\(configuration.controllerURL)/api/workers/unregister")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")
            request.setValue(accessToken, forHTTPHeaderField: "X-Worker-Token")

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let reassignedCount = json["builds_reassigned"] as? Int {
                        print("✓ Unregistered from controller (\(reassignedCount) builds reassigned)")
                    } else {
                        print("✓ Unregistered from controller")
                    }
                } else {
                    print("Failed to unregister (status \(httpResponse.statusCode))")
                }
            }
        } catch {
            print("Failed to unregister worker: \(error)")
        }
    }

    private func pollForJob() async throws -> BuildJob? {
        guard let accessToken = configuration.accessToken else {
            print("No access token found, skipping poll")
            return nil
        }

        print("Polling with access token (length: \(accessToken.count))")

        // Controller expects X-Worker-Token header
        let url = URL(string: "\(configuration.controllerURL)/api/workers/poll")!
        print("Polling: \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(accessToken, forHTTPHeaderField: "X-Worker-Token")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else { return nil }

        if httpResponse.statusCode == 200 {
            // Controller returns { job: BuildJob | null, access_token: string }
            let pollResponse = try JSONDecoder().decode(PollResponse.self, from: data)

            // Update access token from response (token rotation)
            if let newToken = pollResponse.access_token {
                configuration.accessToken = newToken
                try? configuration.save()
                print("✓ Access token updated (length: \(newToken.count))")
            }

            if let job = pollResponse.job {
                print("Received job: \(job.id)")
                return job
            }
            return nil
        } else if httpResponse.statusCode == 204 {
            // No jobs available
            return nil
        } else if httpResponse.statusCode == 401 {
            // Unauthorized - token expired or invalid, re-register
            print("Unauthorized (401), triggering re-registration")
            if let body = String(data: data, encoding: .utf8) {
                print("Response body: \(body)")
            }
            try await handleReregistration(clearWorkerID: false)
            return nil
        } else if httpResponse.statusCode == 404 {
            // Worker not found - re-register with new ID
            print("Worker not found (404), triggering re-registration")
            if let body = String(data: data, encoding: .utf8) {
                print("Response body: \(body)")
            }
            try await handleReregistration(clearWorkerID: true)
            return nil
        } else {
            print("Poll failed: \(httpResponse.statusCode)")
            if let body = String(data: data, encoding: .utf8) {
                print("Response body: \(body)")
            }
            return nil
        }
    }

    private func handleReregistration(clearWorkerID: Bool) async throws {
        // Prevent concurrent re-registration attempts
        guard !isReregistering else {
            print("Re-registration already in progress, skipping")
            return
        }

        isReregistering = true
        defer { isReregistering = false }

        print("Starting atomic re-registration (clearWorkerID: \(clearWorkerID))")

        // Preserve worker ID for 401 (token expired but worker still valid)
        // Clear worker ID for 404 (worker deleted/unknown, need new registration)
        if clearWorkerID {
            configuration.workerID = nil
        }

        // Always clear stale token
        configuration.accessToken = nil
        try? configuration.save()

        // Re-register with controller (will preserve state if workerID provided)
        // Retry with exponential backoff
        var attempt = 0
        let maxAttempts = 5

        while attempt < maxAttempts {
            do {
                try await registerWorker()
                print("✓ Re-registration complete")
                resetBackoff()
                return
            } catch {
                attempt += 1
                if attempt >= maxAttempts {
                    print("⚠️  Re-registration failed after \(maxAttempts) attempts: \(error)")
                    throw error
                }

                print("⚠️  Re-registration attempt \(attempt) failed: \(error)")
                print("   Retrying in \(currentBackoffDelay / 1_000_000_000)s...")

                try? await Task.sleep(nanoseconds: currentBackoffDelay)
                increaseBackoff()
            }
        }
    }

    private func executeJob(_ job: BuildJob) async {
        let task = Task {
            do {
                print("Starting build job: \(job.id)")
                try await performBuild(job)
                print("✓ Build job completed: \(job.id)")
            } catch {
                print("✗ Build job failed: \(job.id) - \(error)")
                await reportJobFailure(job.id, error: error)
            }
        }

        activeBuilds[job.id] = task

        await task.value
        activeBuilds.removeValue(forKey: job.id)
    }

    private func performBuild(_ job: BuildJob) async throws {
        var buildPackagePath: URL?
        var runProcess: Process?
        var vmName: String?
        var tartPath: String?

        do {
            // Step 3: Create build config directory
            buildPackagePath = try await downloadBuildPackage(job)
            print("✓ Created build config directory")

            // Write versioned bootstrap script
            guard let bootstrapURL = Bundle.module.url(
                forResource: "free-agent-bootstrap",
                withExtension: "sh"
            ) else {
                throw WorkerError.resourceNotFound("free-agent-bootstrap.sh")
            }

            let bootstrapDestination = buildPackagePath!.appendingPathComponent("bootstrap.sh")
            try FileManager.default.copyItem(at: bootstrapURL, to: bootstrapDestination)

            // Make executable
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: bootstrapDestination.path
            )

            print("✓ Wrote bootstrap script to \(bootstrapDestination.path)")

            // Write diagnostics script
            guard let diagnosticsURL = Bundle.module.url(
                forResource: "diagnostics",
                withExtension: "sh"
            ) else {
                throw WorkerError.resourceNotFound("diagnostics.sh")
            }

            let diagnosticsDestination = buildPackagePath!.appendingPathComponent("diagnostics.sh")
            try FileManager.default.copyItem(at: diagnosticsURL, to: diagnosticsDestination)

            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: diagnosticsDestination.path
            )

            print("✓ Wrote diagnostics script to \(diagnosticsDestination.path)")

            // Step 4: Create and launch VM
            print("Step 4: Creating and launching VM...")

            // Use baseImageId from controller, then config override, then default
            let templateImage = job.baseImageId
                ?? configuration.templateImage
                ?? "ghcr.io/sethwebster/expo-free-agent-base:0.1.31"
            tartPath = "/opt/homebrew/bin/tart"

            // Clone VM
            let jobID = UUID().uuidString.prefix(8)
            vmName = "fa-\(jobID)"
            print("Cloning template \(templateImage) to \(vmName!)...")

            let cloneProcess = Process()
            cloneProcess.executableURL = URL(fileURLWithPath: tartPath!)
            cloneProcess.arguments = ["clone", templateImage, vmName!]
            try cloneProcess.run()
            cloneProcess.waitUntilExit()

            guard cloneProcess.terminationStatus == 0 else {
                throw WorkerError.buildFailed(reason: "Failed to clone VM template")
            }
            print("✓ VM cloned: \(vmName!)")

            // Launch VM headless with build config mounted
            print("Launching VM headless with build config mounted...")
            runProcess = Process()
            runProcess!.executableURL = URL(fileURLWithPath: tartPath!)
            runProcess!.arguments = [
                "run",
                "--no-graphics",
                vmName!,
                "--dir", "build-config:\(buildPackagePath!.path)"
            ]

            print("Executing: \(tartPath!) run --no-graphics \(vmName!) --dir build-config:\(buildPackagePath!.path)")
            try runProcess!.run()
            print("✓ VM launched headless (PID: \(runProcess!.processIdentifier))")
            print("✓ Build config will mount at /Volumes/My Shared Files/build-config")

            // Wait for VM bootstrap to complete (polls controller API)
            let vmToken = try await waitForVMReady(buildID: job.id, timeout: 300)
            print("✓ VM bootstrap complete (token: \(vmToken.prefix(8))...)")

            // Step 5: Monitor build progress
            print("Step 5: Monitoring build progress...")

            guard let workerID = configuration.workerID, !workerID.isEmpty else {
                throw WorkerError.buildFailed(reason: "Worker ID not configured")
            }

            let buildStatus = try await monitorBuildProgress(
                buildID: job.id,
                workerID: workerID,
                vmToken: vmToken,
                buildDir: buildPackagePath!,
                vmProcess: runProcess!,
                timeout: TimeInterval(configuration.buildTimeoutMinutes * 60)
            )

            // Report result to controller
            if buildStatus.success {
                print("✓ Build succeeded, reporting to controller...")
                try await uploadBuildResult(job.id, result: BuildResult(
                    success: true,
                    logs: "Build completed successfully",
                    artifactPath: nil  // Artifact already uploaded by VM
                ))
            } else {
                print("✗ Build failed, reporting to controller...")
                let baseError = buildStatus.error ?? "Build failed"
                let detailedError: String

                if let logTail = buildStatus.logTail, !logTail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailedError = "\(baseError)\n\nVM build log tail:\n\(logTail)"
                } else {
                    detailedError = baseError
                }

                await reportJobFailure(job.id, error: WorkerError.buildFailed(
                    reason: detailedError
                ))
            }

            // Cleanup
            await stopVMProcess(runProcess!)
            if configuration.cleanupAfterBuild {
                try await deleteVMClone(vmName!, tartPath: tartPath!)
            }

        } catch {
            print("✗ Build error: \(error)")

            // Cleanup on error
            do {
                // Stop VM process if it was started
                if let process = runProcess {
                    await stopVMProcess(process)
                }

                // Delete VM clone if it was created
                if configuration.cleanupAfterBuild, let name = vmName, let path = tartPath {
                    try? await deleteVMClone(name, tartPath: path)
                }

                // Delete build directory
                if let path = buildPackagePath {
                    try FileManager.default.removeItem(at: path)
                }
            } catch {
                print("Cleanup error: \(error)")
            }

            throw error
        }

        // Cleanup build directory on success
        // (VM cleanup already done in Step 5)
        do {
            if let path = buildPackagePath {
                try FileManager.default.removeItem(at: path)
            }
        } catch {
            print("Cleanup error: \(error)")
        }
    }

    private func downloadBuildPackage(_ job: BuildJob) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let buildDir = tempDir.appendingPathComponent("fa-build-\(job.id)")

        // Create build directory
        if FileManager.default.fileExists(atPath: buildDir.path) {
            try FileManager.default.removeItem(at: buildDir)
        }
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)

        // Create build-config.json
        let buildConfig: [String: Any] = [
            "build_token": job.otp,
            "build_id": job.id,
            "controller_url": configuration.controllerURL,
            "platform": job.platform
        ]

        let configPath = buildDir.appendingPathComponent("build-config.json")
        let configData = try JSONSerialization.data(withJSONObject: buildConfig, options: .prettyPrinted)
        try configData.write(to: configPath)

        print("✓ Created build config at \(configPath.path)")

        // Log build config contents
        if let configString = String(data: configData, encoding: .utf8) {
            print("Build config contents:\n\(configString)")
        }

        return buildDir
    }


    private func uploadBuildResult(_ jobID: String, result: BuildResult) async throws {
        let url = URL(string: "\(configuration.controllerURL)/api/workers/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add build_id (controller expects snake_case)
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"build_id\"\r\n\r\n")
        body.append("\(jobID)\r\n")

        // Add worker_id
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"worker_id\"\r\n\r\n")
        body.append("\(configuration.workerID ?? "")\r\n")

        // Add success status (controller expects string "true" or "false")
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"success\"\r\n\r\n")
        body.append("\(result.success ? "true" : "false")\r\n")

        // Add error_message if failed
        if !result.success {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"error_message\"\r\n\r\n")
            body.append("Build failed. See logs for details.\r\n")
        }

        // Add result file if exists (controller expects field name "result")
        if let artifactPath = result.artifactPath,
           let artifactData = try? Data(contentsOf: artifactPath) {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"result\"; filename=\"\(artifactPath.lastPathComponent)\"\r\n")
            body.append("Content-Type: application/octet-stream\r\n\r\n")
            body.append(artifactData)
            body.append("\r\n")
        }

        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        let (_, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 200 {
                print("✓ Uploaded build result for job \(jobID)")
            } else {
                throw WorkerError.uploadFailed(statusCode: httpResponse.statusCode)
            }
        }
    }

    private func reportJobFailure(_ jobID: String, error: Error) async {
        // Report failure via the upload endpoint with success=false
        do {
            let url = URL(string: "\(configuration.controllerURL)/api/workers/upload")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")

            let boundary = UUID().uuidString
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var body = Data()

            // Add build_id
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"build_id\"\r\n\r\n")
            body.append("\(jobID)\r\n")

            // Add worker_id
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"worker_id\"\r\n\r\n")
            body.append("\(configuration.workerID ?? "")\r\n")

            // Add success=false
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"success\"\r\n\r\n")
            body.append("false\r\n")

            // Add error_message
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"error_message\"\r\n\r\n")
            body.append("\(error.localizedDescription)\r\n")

            body.append("--\(boundary)--\r\n")

            request.httpBody = body

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("Reported job failure for \(jobID)")
            }
        } catch {
            print("Failed to report job failure: \(error)")
        }
    }

    private func reportJobAbandoned(_ jobID: String, reason: String) async {
        // Report abandonment - controller will requeue the build
        do {
            let url = URL(string: "\(configuration.controllerURL)/api/workers/abandon")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(configuration.accessToken, forHTTPHeaderField: "X-Worker-Token")

            let payload: [String: Any] = [
                "build_id": jobID,
                "worker_id": configuration.workerID ?? "",
                "reason": reason
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("✓ Reported job abandoned for \(jobID)")
            } else {
                print("⚠️  Failed to report abandonment (status \((response as? HTTPURLResponse)?.statusCode ?? -1))")
            }
        } catch {
            print("Failed to report job abandonment: \(error)")
        }
    }

    private func waitForVMReady(buildID: String, timeout: TimeInterval = 300) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        let statusURL = URL(string: "\(configuration.controllerURL)/api/builds/\(buildID)/vm-status")!

        print("Waiting for VM ready signal via controller API...")

        while Date() < deadline {
            do {
                var request = URLRequest(url: statusURL)
                request.httpMethod = "GET"
                request.timeoutInterval = 10

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    try await Task.sleep(for: .seconds(2))
                    continue
                }

                if httpResponse.statusCode == 200 {
                    let vmStatus = try JSONDecoder().decode(VMStatusResponse.self, from: data)

                    if vmStatus.vm_ready {
                        guard let token = vmStatus.vm_token, !token.isEmpty else {
                            throw WorkerError.vmBootstrapFailed("VM token missing from controller")
                        }
                        print("✓ VM ready (token: \(token.prefix(8))...)")
                        return token
                    }
                } else if httpResponse.statusCode == 404 {
                    throw WorkerError.vmBootstrapFailed("Build not found")
                }
            } catch let error as WorkerError {
                throw error
            } catch {
                // Network error, continue polling
                print("⚠️  VM status check failed: \(error), retrying...")
            }

            try await Task.sleep(for: .seconds(2))
        }

        throw WorkerError.timeout("VM did not signal ready within \(timeout)s")
    }

    private func monitorBuildProgress(
        buildID: String,
        workerID: String,
        vmToken: String,
        buildDir: URL,
        vmProcess: Process,
        timeout: TimeInterval
    ) async throws -> BuildCompletionStatus {
        let completeFile = buildDir.appendingPathComponent("build-complete")
        let errorFile = buildDir.appendingPathComponent("build-error")
        let progressFile = buildDir.appendingPathComponent("progress.json")
        let deadline = Date().addingTimeInterval(timeout)
        let heartbeatInterval: TimeInterval = 20
        var lastHeartbeat = Date.distantPast

        print("Monitoring build progress...")

        while Date() < deadline {
            let now = Date()
            // Check if VM process is still running
            if !vmProcess.isRunning {
                throw WorkerError.buildFailed(reason: "VM process terminated unexpectedly")
            }

            if now.timeIntervalSince(lastHeartbeat) >= heartbeatInterval {
                let progress = try Self.decodeBuildProgress(at: progressFile)
                try await sendBuildHeartbeat(
                    buildID: buildID,
                    workerID: workerID,
                    vmToken: vmToken,
                    progressPercent: progress?.progressPercent
                )
                lastHeartbeat = now
            }

            // Check for completion
            if FileManager.default.fileExists(atPath: completeFile.path) {
                let data = try Data(contentsOf: completeFile)
                let _ = try JSONDecoder().decode(BuildCompletionSignal.self, from: data)
                print("✓ Build completed successfully")
                return BuildCompletionStatus(success: true, error: nil, logTail: nil)
            }

            // Check for error
            if FileManager.default.fileExists(atPath: errorFile.path) {
                let data = try Data(contentsOf: errorFile)
                let signal = try JSONDecoder().decode(BuildCompletionSignal.self, from: data)
                print("✗ Build failed: \(signal.error ?? "Unknown error")")
                return BuildCompletionStatus(success: false, error: signal.error, logTail: signal.log_tail)
            }

            // Poll every 5 seconds
            try await Task.sleep(for: .seconds(5))
        }

        throw WorkerError.timeout("Build did not complete within \(timeout)s")
    }

    private func sendBuildHeartbeat(
        buildID: String,
        workerID: String,
        vmToken: String,
        progressPercent: Int?
    ) async throws {
        var urlComponents = URLComponents(string: "\(configuration.controllerURL)/api/builds/\(buildID)/heartbeat")
        urlComponents?.queryItems = [URLQueryItem(name: "worker_id", value: workerID)]

        guard let url = urlComponents?.url else {
            throw WorkerError.invalidConfiguration("Invalid heartbeat URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(vmToken, forHTTPHeaderField: "X-VM-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let progressPercent = progressPercent {
            let payload: [String: Any] = ["progress": progressPercent]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } else {
            request.httpBody = try JSONSerialization.data(withJSONObject: [:])
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw WorkerError.buildFailed(reason: "Heartbeat failed with status \(httpResponse.statusCode)")
        }
    }

    private func stopVMProcess(_ process: Process) async {
        guard process.isRunning else {
            print("VM process already stopped")
            return
        }

        print("Stopping VM process...")
        process.terminate()

        // Wait up to 30 seconds for graceful shutdown
        for _ in 0..<30 {
            if !process.isRunning {
                print("✓ VM process stopped gracefully")
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }

        // Force kill if still running
        if process.isRunning {
            print("⚠️  Force killing VM process")
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func deleteVMClone(_ vmName: String, tartPath: String) async throws {
        print("Deleting VM clone: \(vmName)")

        let deleteProcess = Process()
        deleteProcess.executableURL = URL(fileURLWithPath: tartPath)
        deleteProcess.arguments = ["delete", vmName]

        try deleteProcess.run()
        deleteProcess.waitUntilExit()

        guard deleteProcess.terminationStatus == 0 else {
            throw WorkerError.buildFailed(reason: "VM deletion failed (exit code: \(deleteProcess.terminationStatus))")
        }

        print("✓ VM clone deleted")
    }
}

struct BuildProgress: Codable {
    let status: String?
    let phase: String?
    let progressPercent: Int?
    let message: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case status
        case phase
        case progressPercent = "progress_percent"
        case message
        case updatedAt = "updated_at"
    }
}

struct VMReadyResponse: Codable {
    let status: String
    let vm_token: String?
    let error: String?
}

struct VMStatusResponse: Codable {
    let vm_ready: Bool
    let vm_token: String?
    let vm_ready_at: String?
}

extension WorkerService {
    static func decodeBuildProgress(at path: URL) throws -> BuildProgress? {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
        }

        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(BuildProgress.self, from: data)
    }
}

struct BuildCompletionSignal: Codable {
    let status: String
    let completed_at: String
    let error: String?
    let log_tail: String?
    let artifact_uploaded: Bool
}

struct BuildCompletionStatus {
    let success: Bool
    let error: String?
    let logTail: String?
}

// MARK: - Models

/// Job response from controller's /api/workers/poll endpoint
public struct PollResponse: Codable, Sendable {
    public let job: BuildJob?
    public let access_token: String?
}

/// Build job details returned by controller
public struct BuildJob: Codable, Sendable {
    public let id: String
    public let platform: String
    public let source_url: String
    public let certs_url: String?
    public let baseImageId: String?
    public let otp: String  // One-time password for VM authentication

    enum CodingKeys: String, CodingKey {
        case id
        case platform
        case source_url
        case otp
        case certs_url
        case baseImageId
    }
}

enum WorkerError: Error {
    case uploadFailed(statusCode: Int)
    case downloadFailed
    case buildFailed(reason: String)
    case resourceNotFound(String)
    case vmBootstrapFailed(String)
    case timeout(String)
    case invalidConfiguration(String)
}

// MARK: - Data Extension

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
