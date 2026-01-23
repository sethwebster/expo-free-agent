import Foundation
import Virtualization

@available(macOS 14.0, *)
public class VMManager: NSObject {
    private let configuration: VMConfiguration
    private var virtualMachine: VZVirtualMachine?
    private var vmConfiguration: VZVirtualMachineConfiguration?
    private var vmCrashed = false
    private var vmError: Error?

    public init(configuration: VMConfiguration) throws {
        self.configuration = configuration
        super.init()
    }

    public func executeBuild(
        sourceCodePath: URL,
        signingCertsPath: URL,
        buildTimeout: TimeInterval
    ) async throws -> BuildResult {
        // Create and start VM
        try await createVM()
        try await startVM()

        // Check for VM crash during startup
        if vmCrashed {
            throw vmError ?? VMError.buildFailed
        }

        guard let vm = virtualMachine else {
            throw VMError.vmNotInitialized
        }

        let executor = XcodeBuildExecutor(vm: vm)

        var logs = ""

        do {
            // Copy source code to VM
            print("Copying source code to VM...")
            logs += "Copying source code to VM...\n"
            try await copySourceCode(sourceCodePath, executor: executor)
            logs += "✓ Source code copied\n\n"

            // Check for crash
            if vmCrashed {
                throw vmError ?? VMError.buildFailed
            }

            // Install signing certificates
            logs += "Installing certificates...\n"
            try await installSigningCertificates(signingCertsPath)
            logs += "✓ Certificates installed\n\n"

            // Check for crash
            if vmCrashed {
                throw vmError ?? VMError.buildFailed
            }

            // Execute build with timeout
            let result = try await executor.executeBuild(timeout: buildTimeout)
            logs += result.logs

            // Check for crash
            if vmCrashed {
                throw vmError ?? VMError.buildFailed
            }

            // Extract artifacts
            if result.success {
                logs += "\nExtracting build artifact...\n"
                if let artifactPath = try await extractArtifact() {
                    try? await stopVM()
                    return BuildResult(success: true, logs: logs, artifactPath: artifactPath)
                } else {
                    logs += "✗ No artifact found\n"
                    try? await stopVM()
                    return BuildResult(success: false, logs: logs, artifactPath: nil)
                }
            } else {
                try? await stopVM()
                return BuildResult(success: false, logs: logs, artifactPath: nil)
            }

        } catch {
            logs += "\n✗ Build failed: \(error)\n"
            try? await stopVM()
            return BuildResult(success: false, logs: logs, artifactPath: nil)
        }
    }

    private func copySourceCode(_ sourceCodePath: URL, executor: XcodeBuildExecutor) async throws {
        // Create project directory in VM
        _ = try await executor.executeCommand("mkdir -p /Users/builder/project", timeout: 10)

        // If source is a zip, copy and extract
        if sourceCodePath.pathExtension == "zip" {
            try await executor.copyFileToVM(localPath: sourceCodePath, remotePath: "/Users/builder/project.zip")
            _ = try await executor.executeCommand("cd /Users/builder && unzip -q project.zip -d project", timeout: 60)
            _ = try await executor.executeCommand("rm /Users/builder/project.zip", timeout: 10)
        } else {
            // Copy directory
            try await executor.copyDirectoryToVM(localPath: sourceCodePath, remotePath: "/Users/builder/project")
        }

        print("✓ Source code copied to VM")
    }

    public func cleanup() async throws {
        try await stopVM()

        // Remove VM disk image if not reusing
        if !configuration.reuseVMs {
            // TODO: Remove VM disk files
        }
    }

    // MARK: - VM Lifecycle

    private func createVM() async throws {
        guard VZVirtualMachine.isSupported else {
            throw VMError.virtualizationNotSupported
        }

        // Load or create VM configuration
        let config = try await loadOrCreateVMConfiguration()
        vmConfiguration = config

        // Validate configuration
        try config.validate()

        // Create virtual machine
        virtualMachine = VZVirtualMachine(configuration: config)
        virtualMachine?.delegate = self

        print("VM created successfully")
    }

    private func startVM() async throws {
        guard let vm = virtualMachine else {
            throw VMError.vmNotInitialized
        }

        print("Starting VM...")

        return try await withCheckedThrowingContinuation { continuation in
            vm.start { result in
                switch result {
                case .success:
                    print("✓ VM started")
                    continuation.resume()
                case .failure(let error):
                    print("✗ VM start failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func stopVM() async throws {
        guard let vm = virtualMachine else { return }

        print("Stopping VM...")

        return try await withCheckedThrowingContinuation { continuation in
            vm.stop { error in
                if let error = error {
                    print("✗ VM stop failed: \(error)")
                    continuation.resume(throwing: error)
                } else {
                    print("✓ VM stopped")
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - VM Configuration

    private func loadOrCreateVMConfiguration() async throws -> VZVirtualMachineConfiguration {
        let config = VZVirtualMachineConfiguration()

        // Platform configuration (Apple Silicon)
        let platform = try createPlatformConfiguration()
        config.platform = platform

        // Boot loader (macOS)
        config.bootLoader = createBootLoader()

        // CPU configuration
        let cpuCount = ProcessInfo.processInfo.processorCount
        let allocatedCPUs = min(cpuCount, Int(Double(cpuCount) * configuration.maxCPUPercent / 100.0))
        config.cpuCount = max(2, allocatedCPUs) // Minimum 2 CPUs

        // Memory configuration
        let memorySize = UInt64(configuration.maxMemoryGB * 1024 * 1024 * 1024)
        config.memorySize = memorySize

        // Storage
        let diskAttachment = try createDiskAttachment()
        config.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: diskAttachment)]

        // Network
        let networkDevice = createNetworkDevice()
        config.networkDevices = [networkDevice]

        // Graphics (headless)
        config.graphicsDevices = [createGraphicsDevice()]

        // Audio (none needed for builds)
        config.audioDevices = []

        // Keyboard and pointing devices
        config.keyboards = [VZUSBKeyboardConfiguration()]
        config.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]

        // Entropy (random number generation)
        config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

        return config
    }

    private func createPlatformConfiguration() throws -> VZMacPlatformConfiguration {
        // For a new VM, create new platform configuration
        let platform = VZMacPlatformConfiguration()

        // Load hardware model
        let hardwareModelPath = vmStorageURL.appendingPathComponent("HardwareModel")
        if FileManager.default.fileExists(atPath: hardwareModelPath.path) {
            let data = try Data(contentsOf: hardwareModelPath)
            if let hardwareModel = VZMacHardwareModel(dataRepresentation: data) {
                platform.hardwareModel = hardwareModel
            } else {
                throw VMError.invalidHardwareModel
            }
        } else {
            // For first run, need to use supported hardware model
            // This should be set during VM creation process
            throw VMError.invalidHardwareModel
        }

        // Load machine identifier
        let machineIdentifierPath = vmStorageURL.appendingPathComponent("MachineIdentifier")
        if FileManager.default.fileExists(atPath: machineIdentifierPath.path) {
            let data = try Data(contentsOf: machineIdentifierPath)
            if let identifier = VZMacMachineIdentifier(dataRepresentation: data) {
                platform.machineIdentifier = identifier
            } else {
                throw VMError.invalidMachineIdentifier
            }
        } else {
            platform.machineIdentifier = VZMacMachineIdentifier()
            try platform.machineIdentifier.dataRepresentation.write(to: machineIdentifierPath)
        }

        // Auxiliary storage (NVRAM)
        let auxStoragePath = vmStorageURL.appendingPathComponent("AuxStorage")
        if !FileManager.default.fileExists(atPath: auxStoragePath.path) {
            // Create new auxiliary storage
            _ = try VZMacAuxiliaryStorage(creatingStorageAt: auxStoragePath, hardwareModel: platform.hardwareModel)
        }
        platform.auxiliaryStorage = VZMacAuxiliaryStorage(contentsOf: auxStoragePath)

        return platform
    }

    private func createBootLoader() -> VZMacOSBootLoader {
        return VZMacOSBootLoader()
    }

    private func createDiskAttachment() throws -> VZDiskImageStorageDeviceAttachment {
        let diskPath = vmStorageURL.appendingPathComponent("Disk.img")

        if !FileManager.default.fileExists(atPath: diskPath.path) {
            // Create disk image
            let diskSize = UInt64(configuration.vmDiskSizeGB * 1024 * 1024 * 1024)
            FileManager.default.createFile(atPath: diskPath.path, contents: nil)

            let handle = try FileHandle(forWritingTo: diskPath)
            try handle.truncate(atOffset: diskSize)
            try handle.close()
        }

        return try VZDiskImageStorageDeviceAttachment(url: diskPath, readOnly: false)
    }

    private func createNetworkDevice() -> VZVirtioNetworkDeviceConfiguration {
        let networkDevice = VZVirtioNetworkDeviceConfiguration()

        // NAT network attachment
        networkDevice.attachment = VZNATNetworkDeviceAttachment()

        return networkDevice
    }

    private func createGraphicsDevice() -> VZMacGraphicsDeviceConfiguration {
        let graphicsConfig = VZMacGraphicsDeviceConfiguration()
        graphicsConfig.displays = [
            VZMacGraphicsDisplayConfiguration(widthInPixels: 1920, heightInPixels: 1080, pixelsPerInch: 220)
        ]
        return graphicsConfig
    }

    // MARK: - Build Operations

    private func installSigningCertificates(_ certsPath: URL) async throws {
        guard let vm = virtualMachine else {
            throw VMError.vmNotInitialized
        }

        let executor = XcodeBuildExecutor(vm: vm)
        let certManager = CertificateManager(executor: executor)

        // Find P12 file in certs directory
        let contents = try FileManager.default.contentsOfDirectory(at: certsPath, includingPropertiesForKeys: nil)
        let p12Files = contents.filter { $0.pathExtension == "p12" }
        let provisioningProfiles = contents.filter { $0.pathExtension == "mobileprovision" }

        guard let p12File = p12Files.first else {
            throw VMError.buildFailed
        }

        // Extract password from password.txt if exists
        let passwordFile = certsPath.appendingPathComponent("password.txt")
        let password: String
        if FileManager.default.fileExists(atPath: passwordFile.path) {
            password = try String(contentsOf: passwordFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            password = "" // Empty password
        }

        print("Installing signing certificates from \(certsPath.path)")
        try await certManager.installCertificates(
            p12Path: p12File,
            p12Password: password,
            provisioningProfiles: provisioningProfiles
        )
    }

    private func extractArtifact() async throws -> URL? {
        guard let vm = virtualMachine else {
            throw VMError.vmNotInitialized
        }

        let executor = XcodeBuildExecutor(vm: vm)

        // Find IPA in VM DerivedData
        let findCmd = """
        find ~/Library/Developer/Xcode/DerivedData -name "*.ipa" -type f 2>/dev/null | head -n 1
        """

        let ipaPath = try await executor.executeCommand(findCmd, timeout: 30)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        if ipaPath.isEmpty {
            print("No IPA found in VM")
            return nil
        }

        print("Found IPA at: \(ipaPath)")

        // Create temp directory for artifact
        let tempDir = FileManager.default.temporaryDirectory
        let localIPAPath = tempDir.appendingPathComponent("build-\(UUID().uuidString).ipa")

        // Copy from VM to host
        try await executor.copyFileFromVM(remotePath: ipaPath, localPath: localIPAPath)

        // Verify IPA
        guard FileManager.default.fileExists(atPath: localIPAPath.path) else {
            throw VMError.artifactNotFound
        }

        let fileSize = try FileManager.default.attributesOfItem(atPath: localIPAPath.path)[.size] as? UInt64 ?? 0
        print("✓ Extracted IPA: \(localIPAPath.path) (\(fileSize / 1024 / 1024) MB)")

        return localIPAPath
    }

    // MARK: - Storage

    private var vmStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let vmDir = appSupport.appendingPathComponent("FreeAgent/VMs/default")
        try? FileManager.default.createDirectory(at: vmDir, withIntermediateDirectories: true)
        return vmDir
    }
}

// MARK: - VZVirtualMachineDelegate

@available(macOS 14.0, *)
extension VMManager: VZVirtualMachineDelegate {
    public func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        print("Guest OS stopped")
    }

    public func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        print("VM stopped with error: \(error)")
        vmCrashed = true
        vmError = error
    }
}

// MARK: - Errors

public enum VMError: Error {
    case virtualizationNotSupported
    case vmNotInitialized
    case invalidHardwareModel
    case invalidMachineIdentifier
    case installationFailed
    case buildFailed
    case artifactNotFound
}

struct TimeoutError: Error {}
