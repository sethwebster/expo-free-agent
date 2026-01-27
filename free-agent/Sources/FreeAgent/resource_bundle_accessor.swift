import Foundation

extension Foundation.Bundle {
    /// Custom resource bundle accessor for production builds
    /// Overrides SPM auto-generated accessor to look in Contents/Resources/
    private static func findResourceBundle() -> Bundle {
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
            Swift.fatalError("could not load resource bundle: from \(resourcesPath) or \(devResourcesPath)")
        }
    }

    /// SPM-compatible accessor (overrides auto-generated version)
    static let module: Bundle = findResourceBundle()

    /// Convenience accessor
    static let resources: Bundle = findResourceBundle()
}
