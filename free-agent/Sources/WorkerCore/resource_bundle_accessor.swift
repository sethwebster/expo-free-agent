import Foundation

extension Foundation.Bundle {
    private static func findWorkerCoreResourceBundle() -> Bundle {
        // Production path: Contents/Resources/WorkerCore_WorkerCore.bundle
        let resourcesPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("WorkerCore_WorkerCore.bundle")
            .path

        // Development path: directly in Sources
        let devResourcesPath = "/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/WorkerCore/Resources"

        if let bundle = Bundle(path: resourcesPath) {
            return bundle
        } else if let bundle = Bundle(path: devResourcesPath) {
            return bundle
        } else {
            Swift.fatalError("could not load WorkerCore resource bundle: from \(resourcesPath) or \(devResourcesPath)")
        }
    }

    static let workerCoreResources: Bundle = findWorkerCoreResourceBundle()
}
