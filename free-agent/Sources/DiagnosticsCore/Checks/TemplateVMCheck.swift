import Foundation

// Thread-safe output collector for process streaming
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var allOutput: [String] = []
    private var outBuffer = Data()
    private var errBuffer = Data()
    private var isFinalized = false
    private var isTerminating = false

    func markTerminating() {
        lock.lock()
        defer { lock.unlock() }
        isTerminating = true
    }

    func processStdout(_ chunk: Data, onLine: (String) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        guard !isFinalized, !isTerminating else { return }
        outBuffer.append(chunk)

        let newline = UInt8(0x0A)
        let carriageReturn = UInt8(0x0D)
        while let idx = outBuffer.firstIndex(where: { byte in byte == newline || byte == carriageReturn }) {
            let lineData = outBuffer.subdata(in: outBuffer.startIndex..<idx)
            outBuffer.removeSubrange(outBuffer.startIndex...idx)

            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                onLine(line)
                allOutput.append(line)
            }
        }
    }

    func processStderr(_ chunk: Data, onLine: (String) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        guard !isFinalized, !isTerminating else { return }
        errBuffer.append(chunk)

        let newline = UInt8(0x0A)
        let carriageReturn = UInt8(0x0D)
        while let idx = errBuffer.firstIndex(where: { byte in byte == newline || byte == carriageReturn }) {
            let lineData = errBuffer.subdata(in: errBuffer.startIndex..<idx)
            errBuffer.removeSubrange(errBuffer.startIndex...idx)

            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                onLine(line)
                allOutput.append(line)
            }
        }
    }

    func finalize() -> String {
        lock.lock()
        defer { lock.unlock() }

        isFinalized = true

        // Just collect remaining buffer data without parsing (no progress updates after termination)
        if !outBuffer.isEmpty, let line = String(data: outBuffer, encoding: .utf8), !line.isEmpty {
            allOutput.append(line)
        }
        if !errBuffer.isEmpty, let line = String(data: errBuffer, encoding: .utf8), !line.isEmpty {
            allOutput.append(line)
        }

        return allOutput.joined(separator: "\n")
    }
}

/// Check if template VM exists (auto-fixable via tart pull)
public actor TemplateVMCheck: DiagnosticCheck {
    public let name = "template_vm_exists"
    public let autoFixable = true
    private let tartPath: String
    private let templateImage: String
    private var progressHandler: (@Sendable (DownloadProgress) -> Void)?

    public init(tartPath: String = "/opt/homebrew/bin/tart", templateImage: String) {
        self.tartPath = tartPath
        self.templateImage = templateImage
    }

    public func setProgressHandler(_ handler: @Sendable @escaping (DownloadProgress) -> Void) {
        self.progressHandler = handler
    }

    public func run() async -> CheckResult {
        let startTime = Date()

        do {
            let (exitCode, output) = try await executeCommand(tartPath, ["list"])
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)

            if exitCode == 0 {
                // Check if template exists in list (tart list returns formatted table)
                // Look for template image name within any line
                let lines = output.components(separatedBy: .newlines)
                let found = lines.contains { line in
                    line.contains(templateImage)
                }

                if found {
                    return CheckResult(
                        name: name,
                        status: .pass,
                        message: "Template VM exists",
                        durationMs: duration,
                        details: ["template": templateImage]
                    )
                } else {
                    return CheckResult(
                        name: name,
                        status: .fail,
                        message: "Template VM not found",
                        durationMs: duration,
                        details: ["template": templateImage, "available": output]
                    )
                }
            } else {
                return CheckResult(
                    name: name,
                    status: .fail,
                    message: "Failed to list VMs",
                    durationMs: duration,
                    details: ["output": output]
                )
            }
        } catch {
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            return CheckResult(
                name: name,
                status: .fail,
                message: "Error listing VMs: \(error.localizedDescription)",
                durationMs: duration
            )
        }
    }

    public func autoFix() async throws -> Bool {
        // First check if template already exists (avoid unnecessary pull)
        let checkResult = await run()
        if checkResult.status == .pass {
            print("✓ Template VM already exists, skipping pull")
            progressHandler?(DownloadProgress(
                status: .complete,
                message: "Template VM already exists",
                percentComplete: 100.0
            ))
            return true
        }

        print("Attempting to pull template VM: \(templateImage)...")

        // Notify starting
        progressHandler?(DownloadProgress(status: .downloading, message: "Starting download..."))

        do {
            let (exitCode, output) = try await executeCommandWithProgress(
                tartPath,
                ["pull", templateImage]
            )

            if exitCode == 0 {
                print("✓ Template VM pulled successfully")
                progressHandler?(DownloadProgress(
                    status: .complete,
                    message: "Download complete",
                    percentComplete: 100.0
                ))
                return true
            } else {
                print("✗ Failed to pull template VM: \(output)")
                progressHandler?(DownloadProgress(
                    status: .failed,
                    message: "Download failed: \(output)"
                ))
                return false
            }
        } catch {
            print("✗ Error pulling template VM: \(error.localizedDescription)")
            progressHandler?(DownloadProgress(
                status: .failed,
                message: "Error: \(error.localizedDescription)"
            ))
            return false
        }
    }

    private func executeCommand(_ command: String, _ arguments: [String]) async throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        return (process.terminationStatus, output.isEmpty ? error : output)
    }

    private func executeCommandWithProgress(_ command: String, _ arguments: [String]) async throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let collector = OutputCollector()
        let handler = progressHandler

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading

        outHandle.readabilityHandler = { [collector, handler] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }

            collector.processStdout(chunk) { line in
                Self.parseProgressLineSync(line, handler: handler)
            }
        }

        errHandle.readabilityHandler = { [collector, handler] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }

            collector.processStderr(chunk) { line in
                Self.parseProgressLineSync(line, handler: handler)
            }
        }

        try process.run()

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { [collector, handler] proc in
                // First, mark terminating to prevent new callbacks from processing
                collector.markTerminating()

                // Give any in-flight callbacks 100ms to complete
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) {
                    // Now safe to clear handlers - callbacks won't process anymore
                    outHandle.readabilityHandler = nil
                    errHandle.readabilityHandler = nil

                    // Brief additional delay to ensure handler cleanup
                    Thread.sleep(forTimeInterval: 0.05)

                    // Collect remaining output (no progress parsing - that's done)
                    let output = collector.finalize()
                    continuation.resume(returning: (proc.terminationStatus, output))
                }
            }
        }
    }

    nonisolated private static func parseProgressLineSync(_ line: String, handler: (@Sendable (DownloadProgress) -> Void)?) {
        guard let handler = handler else { return }

        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        // Check if line contains a percentage
        if let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*%"#),
           let match = regex.firstMatch(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)),
           match.numberOfRanges > 1,
           let percentRange = Range(match.range(at: 1), in: trimmedLine),
           let percent = Double(trimmedLine[percentRange]) {
            handler(DownloadProgress(
                status: .downloading,
                message: "Downloading base image...",
                percentComplete: percent
            ))
            return
        }

        // Check for pulling/downloading/extracting messages
        if trimmedLine.contains("pulling") || trimmedLine.contains("downloading") || trimmedLine.contains("Downloading") {
            handler(DownloadProgress(status: .downloading, message: trimmedLine))
        } else if trimmedLine.contains("extracting") || trimmedLine.contains("Extracting") {
            handler(DownloadProgress(status: .extracting, message: trimmedLine))
        }
    }
}
