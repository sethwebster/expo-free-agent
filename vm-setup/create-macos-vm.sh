#!/bin/bash

# create-macos-vm.sh
# Creates a macOS VM image with Xcode for iOS builds
# Requires: macOS 14+, Xcode 15+, ~50GB disk space

set -e

VM_NAME="${1:-free-agent-builder}"
VM_DIR="$HOME/Library/Application Support/FreeAgent/VMs/$VM_NAME"
DISK_SIZE_GB="${2:-80}"
INSTALL_XCODE="${3:-yes}"

echo "Creating Free Agent Build VM: $VM_NAME"
echo "VM Directory: $VM_DIR"
echo "Disk Size: ${DISK_SIZE_GB}GB"
echo ""

# Check prerequisites
if ! sw_vers | grep -q "14\|15"; then
    echo "Error: macOS 14+ required"
    exit 1
fi

# Create VM directory
mkdir -p "$VM_DIR"

# Download macOS IPSW if not exists
IPSW_PATH="$HOME/Library/Application Support/FreeAgent/macOS-restore.ipsw"
if [ ! -f "$IPSW_PATH" ]; then
    echo "Downloading macOS restore image..."
    echo "Note: This requires manual download from Apple's servers"
    echo ""
    echo "Options:"
    echo "1. Use softwareupdate to download:"
    echo "   softwareupdate --fetch-full-installer --full-installer-version 14.0"
    echo ""
    echo "2. Or download IPSW from https://ipsw.me/product/Mac"
    echo ""
    echo "3. Or use this script to get latest available:"

    # Try to get latest IPSW URL
    # This uses Apple's public API to find restore images
    IPSW_URL=$(curl -s 'https://api.ipsw.me/v4/device/Mac14,3' | \
               python3 -c "import sys, json; data = json.load(sys.stdin); print(data['firmwares'][0]['url'])" 2>/dev/null || echo "")

    if [ -n "$IPSW_URL" ]; then
        echo ""
        echo "Latest IPSW found: $IPSW_URL"
        echo "Downloading (this will take 10-20 minutes)..."
        curl -L --progress-bar "$IPSW_URL" -o "$IPSW_PATH"
        echo "Download complete!"
    else
        echo "Could not auto-detect IPSW URL."
        echo "Please download manually and place at: $IPSW_PATH"
        exit 1
    fi
fi

# Create Swift helper to install macOS
SWIFT_INSTALLER=$(cat <<'EOF'
import Foundation
import Virtualization

@available(macOS 14.0, *)
class VMInstaller: NSObject {
    let vmDir: URL
    let ipsw: URL
    let diskSizeGB: Int

    init(vmDir: String, ipsw: String, diskSizeGB: Int) {
        self.vmDir = URL(fileURLWithPath: vmDir)
        self.ipsw = URL(fileURLWithPath: ipsw)
        self.diskSizeGB = diskSizeGB
        super.init()
    }

    func run() async throws {
        print("Loading IPSW...")
        let image = try await VZMacOSRestoreImage.image(from: ipsw)

        guard let macOSConfiguration = image.mostFeaturefulSupportedConfiguration else {
            throw NSError(domain: "VMInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: "No supported configuration found"])
        }

        print("Creating hardware model...")
        let hardwareModel = macOSConfiguration.hardwareModel
        try hardwareModel.dataRepresentation.write(to: vmDir.appendingPathComponent("HardwareModel"))

        print("Creating machine identifier...")
        let machineIdentifier = VZMacMachineIdentifier()
        try machineIdentifier.dataRepresentation.write(to: vmDir.appendingPathComponent("MachineIdentifier"))

        print("Creating auxiliary storage...")
        let auxStorage = try VZMacAuxiliaryStorage(
            creatingStorageAt: vmDir.appendingPathComponent("AuxStorage"),
            hardwareModel: hardwareModel
        )

        print("Creating disk image (\(diskSizeGB)GB)...")
        let diskPath = vmDir.appendingPathComponent("Disk.img")
        FileManager.default.createFile(atPath: diskPath.path, contents: nil)
        let handle = try FileHandle(forWritingTo: diskPath)
        try handle.truncate(atOffset: UInt64(diskSizeGB) * 1024 * 1024 * 1024)
        try handle.close()

        print("Configuring VM...")
        let config = VZVirtualMachineConfiguration()

        let platform = VZMacPlatformConfiguration()
        platform.hardwareModel = hardwareModel
        platform.machineIdentifier = machineIdentifier
        platform.auxiliaryStorage = auxStorage
        config.platform = platform

        config.bootLoader = VZMacOSBootLoader()
        config.cpuCount = min(4, ProcessInfo.processInfo.processorCount)
        config.memorySize = 8 * 1024 * 1024 * 1024 // 8GB

        let diskAttachment = try VZDiskImageStorageDeviceAttachment(url: diskPath, readOnly: false)
        config.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: diskAttachment)]

        config.networkDevices = [VZVirtioNetworkDeviceConfiguration()]
        if let attachment = config.networkDevices.first as? VZVirtioNetworkDeviceConfiguration {
            attachment.attachment = VZNATNetworkDeviceAttachment()
        }

        let graphics = VZMacGraphicsDeviceConfiguration()
        graphics.displays = [VZMacGraphicsDisplayConfiguration(widthInPixels: 1920, heightInPixels: 1080, pixelsPerInch: 220)]
        config.graphicsDevices = [graphics]

        config.keyboards = [VZUSBKeyboardConfiguration()]
        config.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]
        config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

        try config.validate()

        print("Starting installation (this will take 30-60 minutes)...")
        let installer = VZMacOSInstaller(virtualMachine: VZVirtualMachine(configuration: config), restoringFromImageAt: ipsw)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            installer.install { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        print("✓ macOS installation complete!")
    }
}

@available(macOS 14.0, *)
@main
struct Main {
    static func main() async {
        guard CommandLine.arguments.count == 4 else {
            print("Usage: installer <vm-dir> <ipsw-path> <disk-size-gb>")
            exit(1)
        }

        let installer = VMInstaller(
            vmDir: CommandLine.arguments[1],
            ipsw: CommandLine.arguments[2],
            diskSizeGB: Int(CommandLine.arguments[3]) ?? 80
        )

        do {
            try await installer.run()
        } catch {
            print("Installation failed: \(error)")
            exit(1)
        }
    }
}
EOF
)

# Compile and run installer
INSTALLER_DIR=$(mktemp -d)
echo "$SWIFT_INSTALLER" > "$INSTALLER_DIR/installer.swift"

echo "Compiling VM installer..."
swiftc -o "$INSTALLER_DIR/installer" \
    -framework Foundation \
    -framework Virtualization \
    "$INSTALLER_DIR/installer.swift"

echo "Installing macOS (30-60 minutes)..."
"$INSTALLER_DIR/installer" "$VM_DIR" "$IPSW_PATH" "$DISK_SIZE_GB"

rm -rf "$INSTALLER_DIR"

if [ "$INSTALL_XCODE" = "yes" ]; then
    echo ""
    echo "====================================="
    echo "Post-Installation Setup Required"
    echo "====================================="
    echo ""
    echo "The VM is now installed. Next steps:"
    echo ""
    echo "1. Boot the VM manually once:"
    echo "   cd \"$VM_DIR\""
    echo "   # Use UTM or Virtualization.framework to boot"
    echo ""
    echo "2. Inside the VM, run:"
    echo "   # Install Xcode CLI tools"
    echo "   xcode-select --install"
    echo ""
    echo "   # Install Homebrew"
    echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    echo ""
    echo "   # Install Node.js and EAS CLI"
    echo "   brew install node"
    echo "   npm install -g eas-cli"
    echo ""
    echo "   # Enable SSH server"
    echo "   sudo systemsetup -setremotelogin on"
    echo ""
    echo "   # Create build user"
    echo "   sudo dscl . -create /Users/builder"
    echo "   sudo dscl . -create /Users/builder UserShell /bin/bash"
    echo "   sudo dscl . -create /Users/builder RealName \"Build User\""
    echo "   sudo dscl . -create /Users/builder UniqueID 502"
    echo "   sudo dscl . -create /Users/builder PrimaryGroupID 20"
    echo "   sudo dscl . -create /Users/builder NFSHomeDirectory /Users/builder"
    echo "   sudo createhomedir -c -u builder"
    echo ""
    echo "   # Set up SSH key authentication (paste your public key)"
    echo "   sudo mkdir -p /Users/builder/.ssh"
    echo "   sudo nano /Users/builder/.ssh/authorized_keys"
    echo "   sudo chown -R builder:staff /Users/builder/.ssh"
    echo "   sudo chmod 700 /Users/builder/.ssh"
    echo "   sudo chmod 600 /Users/builder/.ssh/authorized_keys"
    echo ""
    echo "3. Shut down the VM"
    echo ""
    echo "4. Create a snapshot (optional but recommended):"
    echo "   cp \"$VM_DIR/Disk.img\" \"$VM_DIR/Disk-clean.img\""
    echo ""
    echo "The VM is now ready for builds!"
fi

echo ""
echo "VM created successfully at: $VM_DIR"
echo ""
echo "VM Configuration:"
echo "  - Hardware Model: $VM_DIR/HardwareModel"
echo "  - Machine ID: $VM_DIR/MachineIdentifier"
echo "  - Disk: $VM_DIR/Disk.img (${DISK_SIZE_GB}GB)"
echo "  - Aux Storage: $VM_DIR/AuxStorage"
