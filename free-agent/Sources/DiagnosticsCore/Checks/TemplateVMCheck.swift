import Foundation

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

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading

        try process.run()

        // Read output asynchronously, handling both \n and \r as line terminators
        let outputTask = Task {
            var buffer = ""
            var allLines: [String] = []
            do {
                for try await byte in outputHandle.bytes {
                    let char = Character(UnicodeScalar(byte))
                    if char == "\n" || char == "\r" {
                        if !buffer.isEmpty {
                            parseProgressLine(buffer)
                            allLines.append(buffer)
                            buffer = ""
                        }
                    } else {
                        buffer.append(char)
                    }
                }
                // Handle any remaining buffer
                if !buffer.isEmpty {
                    parseProgressLine(buffer)
                    allLines.append(buffer)
                }
            } catch {
                print("Error reading stdout: \(error)")
            }
            return allLines.joined(separator: "\n")
        }

        let errorTask = Task {
            var buffer = ""
            var allLines: [String] = []
            do {
                for try await byte in errorHandle.bytes {
                    let char = Character(UnicodeScalar(byte))
                    if char == "\n" || char == "\r" {
                        if !buffer.isEmpty {
                            parseProgressLine(buffer)
                            allLines.append(buffer)
                            buffer = ""
                        }
                    } else {
                        buffer.append(char)
                    }
                }
                // Handle any remaining buffer
                if !buffer.isEmpty {
                    parseProgressLine(buffer)
                    allLines.append(buffer)
                }
            } catch {
                print("Error reading stderr: \(error)")
            }
            return allLines.joined(separator: "\n")
        }

        // Wait for process to complete
        process.waitUntilExit()

        // Wait for all output to be read
        let stdout = await outputTask.value
        let stderr = await errorTask.value

        let allOutput = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        return (process.terminationStatus, allOutput)
    }

    private func parseProgressLine(_ line: String) {
        // tart pull outputs progress like:
        // "pulling manifest..."
        // "pulling disk (69.0 GB compressed)..."
        // "[1A[J37%" or "37%" (with optional ANSI escape codes)
        // "pulling NVRAM..."

        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        // Check if line contains a percentage (handles ANSI codes like [1A[J23%)
        // Match any number followed by % anywhere in the line
        if let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*%"#),
           let match = regex.firstMatch(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)),
           match.numberOfRanges > 1 {
            let percentRange = Range(match.range(at: 1), in: trimmedLine)
            if let percentRange = percentRange,
               let percent = Double(trimmedLine[percentRange]) {
                progressHandler?(DownloadProgress(
                    status: .downloading,
                    message: "Downloading base image...",
                    percentComplete: percent
                ))
                return
            }
        }

        // Check for pulling/downloading messages
        if trimmedLine.contains("pulling") || trimmedLine.contains("downloading") || trimmedLine.contains("Downloading") {
            progressHandler?(DownloadProgress(
                status: .downloading,
                message: trimmedLine
            ))
        } else if trimmedLine.contains("extracting") || trimmedLine.contains("Extracting") {
            progressHandler?(DownloadProgress(
                status: .extracting,
                message: trimmedLine
            ))
        }
    }
}
