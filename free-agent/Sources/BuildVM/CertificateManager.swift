import Foundation
import Security

@available(macOS 14.0, *)
public class CertificateManager {
    private let executor: XcodeBuildExecutor

    public init(executor: XcodeBuildExecutor) {
        self.executor = executor
    }

    /// Install P12 certificate and provisioning profile in VM
    public func installCertificates(
        p12Path: URL,
        p12Password: String,
        provisioningProfiles: [URL] = []
    ) async throws {
        // Copy certificate to VM
        let remoteCertPath = "/Users/builder/cert.p12"
        try await executor.copyFileToVM(localPath: p12Path, remotePath: remoteCertPath)

        // Create keychain if doesn't exist
        let keychainPath = "\\$HOME/Library/Keychains/build.keychain-db"
        let keychainPassword = "build123"

        // Delete existing keychain if present
        _ = try? await executor.executeCommand(
            "security delete-keychain '\(keychainPath)' || true",
            timeout: 10
        )

        // Create new keychain
        _ = try await executor.executeCommand(
            "security create-keychain -p '\(keychainPassword)' '\(keychainPath)'",
            timeout: 10
        )

        // Set keychain as default
        _ = try await executor.executeCommand(
            "security default-keychain -s '\(keychainPath)'",
            timeout: 10
        )

        // Unlock keychain
        _ = try await executor.executeCommand(
            "security unlock-keychain -p '\(keychainPassword)' '\(keychainPath)'",
            timeout: 10
        )

        // Set keychain timeout to 1 hour
        _ = try await executor.executeCommand(
            "security set-keychain-settings -t 3600 -l '\(keychainPath)'",
            timeout: 10
        )

        // Import P12 certificate
        let importCmd = "security import '\(remoteCertPath)' -k '\(keychainPath)' -P '\(p12Password)' -T /usr/bin/codesign -T /usr/bin/security"
        _ = try await executor.executeCommand(importCmd, timeout: 30)

        // Set key partition list (allow codesign to access)
        let partitionCmd = "security set-key-partition-list -S apple-tool:,apple: -s -k '\(keychainPassword)' '\(keychainPath)'"
        _ = try? await executor.executeCommand(partitionCmd, timeout: 10)

        // Install provisioning profiles
        for profilePath in provisioningProfiles {
            try await installProvisioningProfile(profilePath)
        }

        // Verify certificate installation
        try await verifyCertificates()

        // Clean up certificate file
        _ = try? await executor.executeCommand("rm '\(remoteCertPath)'", timeout: 10)

        print("✓ Certificates installed successfully")
    }

    private func installProvisioningProfile(_ profilePath: URL) async throws {
        let profilesDir = "\\$HOME/Library/MobileDevice/Provisioning\\ Profiles"

        // Create profiles directory
        _ = try await executor.executeCommand("mkdir -p \(profilesDir)", timeout: 10)

        // Copy profile to VM
        let remoteProfilePath = "~/Library/MobileDevice/Provisioning\\ Profiles/\(profilePath.lastPathComponent)"
        try await executor.copyFileToVM(localPath: profilePath, remotePath: remoteProfilePath)

        print("✓ Installed provisioning profile: \(profilePath.lastPathComponent)")
    }

    private func verifyCertificates() async throws {
        // List certificates in keychain
        let listCmd = """
        security find-identity -v -p codesigning
        """
        let output = try await executor.executeCommand(listCmd, timeout: 10)

        if output.contains("0 valid identities found") {
            throw CertificateError.noCertificatesFound
        }

        print("✓ Certificate verification passed")
        print(output)
    }

    /// Get list of signing identities in VM
    public func listSigningIdentities() async throws -> [String] {
        let output = try await executor.executeCommand(
            "security find-identity -v -p codesigning | grep -o '\"[^\"]*\"' | sed 's/\"//g'",
            timeout: 10
        )

        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Clean up certificates and keychain
    public func cleanup() async throws {
        let keychainPath = "\\$HOME/Library/Keychains/build.keychain-db"

        // Delete keychain
        _ = try? await executor.executeCommand(
            "security delete-keychain '\(keychainPath)' || true",
            timeout: 10
        )

        // Clean up provisioning profiles
        _ = try? await executor.executeCommand(
            "rm -rf \\$HOME/Library/MobileDevice/Provisioning\\ Profiles/*",
            timeout: 10
        )

        print("✓ Certificate cleanup complete")
    }
}

public enum CertificateError: Error {
    case noCertificatesFound
    case invalidP12File
    case keychainAccessDenied
    case installationFailed(reason: String)
}
