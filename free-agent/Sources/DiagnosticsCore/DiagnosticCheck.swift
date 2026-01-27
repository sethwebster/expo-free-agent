import Foundation

/// Status of a diagnostic check
public enum CheckStatus: String, Codable, Sendable {
    case pass
    case warn
    case fail
}

/// Result of running a diagnostic check
public struct CheckResult: Codable, Sendable {
    public let name: String
    public let status: CheckStatus
    public let message: String
    public let durationMs: Int
    public let autoFixed: Bool
    public let details: [String: String]?

    public init(
        name: String,
        status: CheckStatus,
        message: String,
        durationMs: Int,
        autoFixed: Bool = false,
        details: [String: String]? = nil
    ) {
        self.name = name
        self.status = status
        self.message = message
        self.durationMs = durationMs
        self.autoFixed = autoFixed
        self.details = details
    }

    enum CodingKeys: String, CodingKey {
        case name
        case status
        case message
        case durationMs = "duration_ms"
        case autoFixed = "auto_fixed"
        case details
    }
}

/// Protocol for diagnostic checks
public protocol DiagnosticCheck: Sendable {
    /// Name of the check (e.g., "tart_installed")
    var name: String { get }

    /// Whether this check can attempt auto-fix
    var autoFixable: Bool { get }

    /// Run the diagnostic check
    func run() async -> CheckResult

    /// Attempt to auto-fix the issue (only called if autoFixable is true and check failed)
    func autoFix() async throws -> Bool
}

/// Overall diagnostic report status
public enum DiagnosticStatus: String, Codable, Sendable {
    case healthy
    case warning
    case critical
}

/// Complete diagnostic report
public struct DiagnosticReport: Codable, Sendable {
    public let workerId: String
    public let status: DiagnosticStatus
    public let runAt: Int
    public let durationMs: Int
    public let autoFixed: Bool
    public let checks: [CheckResult]

    public init(
        workerId: String,
        status: DiagnosticStatus,
        runAt: Int,
        durationMs: Int,
        autoFixed: Bool,
        checks: [CheckResult]
    ) {
        self.workerId = workerId
        self.status = status
        self.runAt = runAt
        self.durationMs = durationMs
        self.autoFixed = autoFixed
        self.checks = checks
    }

    enum CodingKeys: String, CodingKey {
        case workerId = "worker_id"
        case status
        case runAt = "run_at"
        case durationMs = "duration_ms"
        case autoFixed = "auto_fixed"
        case checks
    }
}
