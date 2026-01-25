import Foundation

/// Orchestrates diagnostic checks and reports to controller
public actor DiagnosticsService {
    private let workerId: String
    private let controllerURL: String
    private let apiKey: String
    private let checks: [DiagnosticCheck]

    public init(
        workerId: String,
        controllerURL: String,
        apiKey: String,
        tartPath: String = "/opt/homebrew/bin/tart",
        templateImage: String
    ) {
        self.workerId = workerId
        self.controllerURL = controllerURL
        self.apiKey = apiKey

        // Initialize all checks
        self.checks = [
            TartCheck(tartPath: tartPath),
            TemplateVMCheck(tartPath: tartPath, templateImage: templateImage),
            DiskSpaceCheck(minFreeSpaceGB: 50, tartPath: tartPath),
            XcodeCheck(),
            ControllerConnectivityCheck(controllerURL: controllerURL, apiKey: apiKey),
            VMSpawnCheck(tartPath: tartPath, templateImage: templateImage)
        ]
    }

    /// Run all diagnostic checks with auto-fix
    public func runDiagnostics(autoFix: Bool = true) async -> DiagnosticReport {
        let startTime = Date()
        var results: [CheckResult] = []
        var anyAutoFixed = false

        print("\n=== Free Agent Diagnostics ===\n")

        for check in checks {
            print("Running check: \(check.name)...")

            var result = await check.run()
            results.append(result)

            // Print result
            printCheckResult(result)

            // Auto-fix if enabled, fixable, and failed
            if autoFix && check.autoFixable && result.status == .fail {
                print("Attempting auto-fix...")
                do {
                    let fixed = try await check.autoFix()
                    if fixed {
                        anyAutoFixed = true
                        print("✓ Auto-fix succeeded, re-running check...")

                        // Re-run the check
                        result = await check.run()
                        // Mark as auto-fixed
                        result = CheckResult(
                            name: result.name,
                            status: result.status,
                            message: result.message,
                            durationMs: result.durationMs,
                            autoFixed: true,
                            details: result.details
                        )
                        results[results.count - 1] = result
                        printCheckResult(result)
                    } else {
                        print("✗ Auto-fix failed")
                    }
                } catch {
                    print("✗ Auto-fix error: \(error.localizedDescription)")
                }
            }

            print("")
        }

        // Calculate overall status
        let overallStatus = determineOverallStatus(results)
        let duration = Int(Date().timeIntervalSince(startTime) * 1000)

        print("Overall Status: \(overallStatus.rawValue)")
        print("Duration: \(duration)ms")
        print("Auto-fixed: \(anyAutoFixed ? "Yes" : "No")\n")

        return DiagnosticReport(
            workerId: workerId,
            status: overallStatus,
            runAt: Int(Date().timeIntervalSince1970 * 1000),
            durationMs: duration,
            autoFixed: anyAutoFixed,
            checks: results
        )
    }

    /// Send diagnostic report to controller
    public func reportToController(_ report: DiagnosticReport) async throws {
        guard let url = URL(string: "\(controllerURL)/api/diagnostics/report") else {
            throw DiagnosticsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(report)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiagnosticsError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DiagnosticsError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
    }

    // MARK: - Helpers

    private func determineOverallStatus(_ results: [CheckResult]) -> DiagnosticStatus {
        let hasFail = results.contains { $0.status == .fail }
        let hasWarn = results.contains { $0.status == .warn }

        if hasFail {
            return .critical
        } else if hasWarn {
            return .warning
        } else {
            return .healthy
        }
    }

    private func printCheckResult(_ result: CheckResult) {
        let icon: String
        switch result.status {
        case .pass:
            icon = "✓"
        case .warn:
            icon = "⚠"
        case .fail:
            icon = "✗"
        }

        let autoFixedLabel = result.autoFixed ? " (auto-fixed)" : ""
        print("\(icon) \(result.name): \(result.message) (\(result.durationMs)ms)\(autoFixedLabel)")
    }
}

// MARK: - Errors

enum DiagnosticsError: Error {
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int, message: String)
}
