import Foundation

/// Represents the progress of a VM template download
public struct DownloadProgress: Sendable {
    public let status: Status
    public let message: String
    public let percentComplete: Double?
    public let bytesDownloaded: Int64?
    public let totalBytes: Int64?

    public enum Status: Sendable {
        case idle
        case downloading
        case extracting
        case complete
        case failed
    }

    public init(
        status: Status,
        message: String,
        percentComplete: Double? = nil,
        bytesDownloaded: Int64? = nil,
        totalBytes: Int64? = nil
    ) {
        self.status = status
        self.message = message
        self.percentComplete = percentComplete
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
    }

    public static var idle: DownloadProgress {
        DownloadProgress(status: .idle, message: "Ready")
    }
}
