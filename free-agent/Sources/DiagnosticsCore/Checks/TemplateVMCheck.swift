import Foundation

/// Check if template VM exists (auto-fixable via tart pull)
public actor TemplateVMCheck: DiagnosticCheck {
    public let name = "template_vm_exists"
    public let autoFixable = true
    private let tartPath: String
    private let templateImage: String

    public init(tartPath: String = "/opt/homebrew/bin/tart", templateImage: String) {
        self.tartPath = tartPath
        self.templateImage = templateImage
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

        do {
            let (exitCode, output) = try await executeCommand(tartPath, ["pull", templateImage])

            if exitCode == 0 {
                print("✓ Template VM pulled successfully")
                return true
            } else {
                print("✗ Failed to pull template VM: \(output)")
                return false
            }
        } catch {
            print("✗ Error pulling template VM: \(error.localizedDescription)")
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
}
