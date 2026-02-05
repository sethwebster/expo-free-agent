import XCTest
@testable import WorkerCore

final class WorkerProgressTests: XCTestCase {
    func testDecodeBuildProgressParsesProgressPercentAndMessage() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let progressPath = tempDir.appendingPathComponent("progress.json")
        let payload = """
        {
          "status": "running",
          "phase": "building",
          "progress_percent": 30,
          "message": "Running xcodebuild...",
          "updated_at": "2026-02-05T15:10:08Z"
        }
        """
        try payload.data(using: .utf8)!.write(to: progressPath)

        let progress = try WorkerService.decodeBuildProgress(at: progressPath)
        XCTAssertEqual(progress?.progressPercent, 30)
        XCTAssertEqual(progress?.message, "Running xcodebuild...")
    }

    func testDiagnosticsScriptIncludesBuildLogAndProcessSections() throws {
        guard let scriptURL = Bundle.module.url(
            forResource: "diagnostics",
            withExtension: "sh"
        ) else {
            XCTFail("diagnostics.sh not found in bundle")
            return
        }

        let contents = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("Build Log"), "Expected Build Log section")
        XCTAssertTrue(contents.contains("build.log"), "Expected build.log reference")
        XCTAssertTrue(contents.contains("Process Snapshot (build tools)"))
    }
}
