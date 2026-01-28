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
                // Check if template exists in list
                let images = output.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                if images.contains(templateImage) {
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
                        details: ["template": templateImage, "available": images.joined(separator: ", ")]
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

        // Read output asynchronously with proper task management
        let outputTask = Task {
            var lines: [String] = []
            do {
                for try await line in outputHandle.bytes.lines {
                    lines.append(line)
                    parseProgressLine(line)
                }
            } catch {
                print("Error reading stdout: \(error)")
            }
            return lines.joined(separator: "\n")
        }

        let errorTask = Task {
            var lines: [String] = []
            do {
                for try await line in errorHandle.bytes.lines {
                    lines.append(line)
                    parseProgressLine(line)
                }
            } catch {
                print("Error reading stderr: \(error)")
            }
            return lines.joined(separator: "\n")
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
        // "downloading layer sha256:abc123... 45.2 MB / 120.5 MB (37.5%)"
        // or "extracting layer sha256:abc123..."

        if line.contains("downloading") || line.contains("Downloading") {
            // Try to extract percentage if available
            if let percentMatch = line.range(of: #"\((\d+(?:\.\d+)?)\%\)"#, options: .regularExpression) {
                let percentString = line[percentMatch].replacingOccurrences(of: "(", with: "")
                    .replacingOccurrences(of: "%)", with: "")
                if let percent = Double(percentString) {
                    let message = line.trimmingCharacters(in: .whitespaces)
                    progressHandler?(DownloadProgress(
                        status: .downloading,
                        message: message,
                        percentComplete: percent
                    ))
                    return
                }
            }

            // No percentage found, just report downloading
            progressHandler?(DownloadProgress(
                status: .downloading,
                message: line.trimmingCharacters(in: .whitespaces)
            ))
        } else if line.contains("extracting") || line.contains("Extracting") {
            progressHandler?(DownloadProgress(
                status: .extracting,
                message: line.trimmingCharacters(in: .whitespaces)
            ))
        }
    }
}
