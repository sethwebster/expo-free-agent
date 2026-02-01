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

        // Debug: Print raw JSON response
        if let rawJson = String(data: data, encoding: .utf8) {
            print("Registration response JSON: \(rawJson)")
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
        var vmManager: TartVMManager?

        do {
            // Download build package
            buildPackagePath = try await downloadBuildPackage(job)
            print("✓ Created build config directory")

            // TEMPORARY: Stop here and abandon build
            print("⚠️  Abandoning build (temporary for testing)")
            await reportJobAbandoned(job.id, reason: "Testing build config creation")

            // Cleanup
            if let path = buildPackagePath {
                try? FileManager.default.removeItem(at: path)
            }
            return

            // NO CERT DOWNLOAD - VM fetches directly via bootstrap now
            print("Skipping cert download - VM will fetch certs securely via bootstrap")

            // Create VM and execute build
            let vmConfig = VMConfiguration(
                maxCPUPercent: configuration.maxCPUPercent,
                maxMemoryGB: configuration.maxMemoryGB,
                vmDiskSizeGB: configuration.vmDiskSizeGB,
                reuseVMs: configuration.reuseVMs,
                cleanupAfterBuild: configuration.cleanupAfterBuild,
                buildTimeoutMinutes: configuration.buildTimeoutMinutes
            )

            // Use baseImageId from controller (fallback to default if not provided)
            let templateImage = job.baseImageId ?? "ghcr.io/sethwebster/expo-free-agent-base:0.1.27"
            vmManager = TartVMManager(configuration: vmConfig, templateImage: templateImage)
            print("✓ Tart VM Manager created with template: \(templateImage)")

            let buildResult = try await vmManager!.executeBuild(
                sourceCodePath: buildPackagePath!,
                signingCertsPath: nil, // VM fetches via API now
                buildTimeout: TimeInterval(configuration.buildTimeoutMinutes * 60),
                buildId: job.id,
                workerId: configuration.workerID,
                controllerURL: configuration.controllerURL,
                apiKey: job.otp  // Pass OTP for VM authentication (not worker API key)
            )
            print("✓ Build execution completed")

            // Upload results
            try await uploadBuildResult(job.id, result: buildResult)
            print("✓ Results uploaded")

        } catch {
            print("✗ Build error: \(error)")

            // Cleanup on error
            do {
                if configuration.cleanupAfterBuild, let vm = vmManager {
                    try await vm.cleanup()
                }

                if let path = buildPackagePath {
                    try FileManager.default.removeItem(at: path)
                }
            } catch {
                print("Cleanup error: \(error)")
            }

            throw error
        }

        // Cleanup on success
        do {
            if configuration.cleanupAfterBuild, let vm = vmManager {
                try await vm.cleanup()
            }

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
}

// MARK: - Data Extension

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
