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
            dependencies: ["BuildVM", "WorkerCore"],
            path: "Sources/FreeAgent"
        ),
        .target(
            name: "BuildVM",
            dependencies: [],
            path: "Sources/BuildVM"
        ),
        .target(
            name: "WorkerCore",
            dependencies: ["BuildVM"],
            path: "Sources/WorkerCore"
        ),
        .testTarget(
            name: "FreeAgentTests",
            dependencies: ["FreeAgent", "BuildVM", "WorkerCore"]
        )
    ]
)
