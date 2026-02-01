// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreeAgent",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "FreeAgent",
            targets: ["FreeAgent"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "FreeAgent",
            dependencies: ["BuildVM", "WorkerCore", "DiagnosticsCore"],
            path: "Sources/FreeAgent",
            exclude: ["Resources"]
        ),
        .target(
            name: "BuildVM",
            dependencies: [],
            path: "Sources/BuildVM",
            exclude: ["VMManager.swift", "XcodeBuildExecutor.swift", "CertificateManager.swift"]
        ),
        .target(
            name: "WorkerCore",
            dependencies: ["BuildVM"],
            path: "Sources/WorkerCore",
            resources: [
                .copy("Resources/free-agent-bootstrap.sh")
            ]
        ),
        .target(
            name: "DiagnosticsCore",
            dependencies: [],
            path: "Sources/DiagnosticsCore"
        ),
        .testTarget(
            name: "FreeAgentTests",
            dependencies: ["FreeAgent"],
            path: "Tests/FreeAgentTests"
        )
    ]
)
