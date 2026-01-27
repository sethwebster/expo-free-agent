import Foundation

extension Foundation.Bundle {
    /// Custom resource bundle accessor for production builds
    /// Looks in Contents/Resources/FreeAgent_FreeAgent.bundle
    static let resources: Bundle = {
        // Production path: Contents/Resources/FreeAgent_FreeAgent.bundle
        let resourcesPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("FreeAgent_FreeAgent.bundle")
            .path

        // Development path: directly in Sources
        let devResourcesPath = "/Users/sethwebster/Development/expo/expo-free-agent/free-agent/Sources/FreeAgent/Resources"

        if let bundle = Bundle(path: resourcesPath) {
            return bundle
        } else if let bundle = Bundle(path: devResourcesPath) {
            return bundle
        } else {
            // Create a bundle from the main bundle's resource path
            return Bundle.main
        }
    }()
}
