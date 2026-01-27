import Foundation

/// Check controller connectivity and API authentication
public actor ControllerConnectivityCheck: DiagnosticCheck {
    public let name = "controller_connectivity"
    public let autoFixable = false
    private let controllerURL: String
    private let apiKey: String

    public init(controllerURL: String, apiKey: String) {
        self.controllerURL = controllerURL
        self.apiKey = apiKey
    }

    public func run() async -> CheckResult {
        let startTime = Date()

        // Test /health endpoint
        guard let url = URL(string: "\(controllerURL)/health") else {
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            return CheckResult(
                name: name,
                status: .fail,
                message: "Invalid controller URL",
                durationMs: duration,
                details: ["url": controllerURL]
            )
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            request.timeoutInterval = 10

            let (_, response) = try await URLSession.shared.data(for: request)
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                return CheckResult(
                    name: name,
                    status: .fail,
                    message: "Invalid response from controller",
                    durationMs: duration
                )
            }

            if httpResponse.statusCode == 200 {
                return CheckResult(
                    name: name,
                    status: .pass,
                    message: "Controller reachable",
                    durationMs: duration,
                    details: [
                        "url": controllerURL,
                        "status": "\(httpResponse.statusCode)"
                    ]
                )
            } else if httpResponse.statusCode == 401 {
                return CheckResult(
                    name: name,
                    status: .fail,
                    message: "API key authentication failed",
                    durationMs: duration,
                    details: [
                        "url": controllerURL,
                        "status": "\(httpResponse.statusCode)"
                    ]
                )
            } else {
                return CheckResult(
                    name: name,
                    status: .fail,
                    message: "Controller returned error: \(httpResponse.statusCode)",
                    durationMs: duration,
                    details: [
                        "url": controllerURL,
                        "status": "\(httpResponse.statusCode)"
                    ]
                )
            }
        } catch {
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            return CheckResult(
                name: name,
                status: .fail,
                message: "Controller unreachable: \(error.localizedDescription)",
                durationMs: duration,
                details: ["url": controllerURL, "error": error.localizedDescription]
            )
        }
    }

    public func autoFix() async throws -> Bool {
        // Not auto-fixable - network/controller issues require manual intervention
        return false
    }
}
