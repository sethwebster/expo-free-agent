import Foundation
import BuildVM

@available(macOS 14.0, *)
public actor WorkerService {
    private var configuration: WorkerConfiguration
    private var isActive = false
    private var pollingTask: Task<Void, Never>?
    private var activeBuilds: [String: Task<Void, Never>] = [:]
    private var vmVerificationHandler: (@Sendable () async -> Bool)?

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

        // Register with controller - halt startup if registration fails
        do {
            try await registerWorker()
        } catch {
            print("FATAL: Registration failed: \(error)")
            print("Worker service cannot start without valid registration")
            return
        }

        isActive = true

        // Start polling loop
        pollingTask = Task {
            await pollLoop()
        }

        print("Worker service started")
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
                        await executeJob(job)
                    }
                }

                // Wait for next poll interval
                try await Task.sleep(for: .seconds(configuration.pollIntervalSeconds))
            } catch {
                if !Task.isCancelled {
                    print("Poll error: \(error)")
                    // Exponential backoff on error
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }

    private func registerWorker() async throws {
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
            ]
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

        // Controller returns { id, status } - save the assigned worker ID
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assignedId = json["id"] as? String else {
            throw WorkerError.buildFailed(reason: "Missing worker ID in registration response")
        }

        print("Parsed ID from response: '\(assignedId)' (length: \(assignedId.count))")

        // CRITICAL: Update configuration atomically
        configuration.workerID = assignedId
        do {
            try configuration.save()
            print("✓ Registered with controller (ID: \(assignedId))")
            print("Configuration workerID is now: '\(configuration.workerID ?? "nil")'")
        } catch {
            // Revert in-memory change if save fails
            configuration.workerID = nil
            throw WorkerError.buildFailed(reason: "Failed to persist worker ID: \(error.localizedDescription)")
        }
    }

    private func unregisterWorker() async {
        guard let workerID = configuration.workerID else { return }

        do {
            // Note: Controller doesn't have an unregister endpoint currently
            // This is a no-op but keeping structure for future implementation
            let url = URL(string: "\(configuration.controllerURL)/api/workers/\(workerID)/unregister")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print("✓ Unregistered from controller")
                }
            }
        } catch {
            print("Failed to unregister worker: \(error)")
        }
    }

    private func pollForJob() async throws -> BuildJob? {
        guard let workerID = configuration.workerID else {
            print("No worker ID found, skipping poll")
            return nil
        }

        print("About to poll with workerID: '\(workerID)' (length: \(workerID.count))")

        // Controller expects query param: /api/workers/poll?worker_id={id}
        let url = URL(string: "\(configuration.controllerURL)/api/workers/poll?worker_id=\(workerID)")!
        print("Polling: \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else { return nil }

        if httpResponse.statusCode == 200 {
            // Controller returns { job: BuildJob | null }
            let pollResponse = try JSONDecoder().decode(PollResponse.self, from: data)
            if let job = pollResponse.job {
                print("Received job: \(job.id)")
                return job
            }
            return nil
        } else if httpResponse.statusCode == 204 {
            // No jobs available
            return nil
        } else {
            print("Poll failed: \(httpResponse.statusCode)")
            if let body = String(data: data, encoding: .utf8) {
                print("Response body: \(body)")
            }
            return nil
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
            print("✓ Downloaded build package")

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
            let templateImage = job.baseImageId ?? "ghcr.io/sethwebster/expo-free-agent-base:0.1.23"
            vmManager = TartVMManager(configuration: vmConfig, templateImage: templateImage)
            print("✓ Tart VM Manager created with template: \(templateImage)")

            let buildResult = try await vmManager!.executeBuild(
                sourceCodePath: buildPackagePath!,
                signingCertsPath: nil, // VM fetches via API now
                buildTimeout: TimeInterval(configuration.buildTimeoutMinutes * 60),
                buildId: job.id,
                workerId: configuration.workerID,
                controllerURL: configuration.controllerURL,
                apiKey: configuration.apiKey
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
        let packagePath = tempDir.appendingPathComponent("build-\(job.id).zip")

        // Use source_url from job (relative URL like /api/builds/{id}/source)
        let url = URL(string: "\(configuration.controllerURL)\(job.source_url)")!
        print("Downloading build package from: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")
        // Controller requires X-Worker-Id header for source/certs downloads
        if let workerID = configuration.workerID {
            request.setValue(workerID, forHTTPHeaderField: "X-Worker-Id")
            print("Using worker ID: \(workerID)")
        }

        let (localURL, response) = try await URLSession.shared.download(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("✗ Download failed: Invalid response type")
            throw WorkerError.downloadFailed
        }

        print("Download response status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            print("✗ Download failed with status \(httpResponse.statusCode)")
            // Try to read error body
            if let data = try? Data(contentsOf: localURL),
               let errorBody = String(data: data, encoding: .utf8) {
                print("Error response: \(errorBody)")
            }
            throw WorkerError.downloadFailed
        }

        // Remove existing file if present
        if FileManager.default.fileExists(atPath: packagePath.path) {
            try FileManager.default.removeItem(at: packagePath)
        }

        try FileManager.default.moveItem(at: localURL, to: packagePath)
        print("✓ Downloaded build package to \(packagePath.path)")

        return packagePath
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
}

// MARK: - Models

/// Job response from controller's /api/workers/poll endpoint
public struct PollResponse: Codable, Sendable {
    public let job: BuildJob?
}

/// Build job details returned by controller
public struct BuildJob: Codable, Sendable {
    public let id: String
    public let platform: String
    public let source_url: String
    public let certs_url: String?
    public let baseImageId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case platform
        case source_url
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
