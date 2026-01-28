# VM Bootstrap Infrastructure

Phase 1 implementation of secure certificate handling for Expo Free Agent VMs.

## Overview

These files enable secure certificate handling where VMs fetch signing certs directly from the controller without host machine access.

**Security Benefits:**
- Host never sees plaintext certificates
- VM becomes inaccessible after boot (SSH blocked)
- Random keychain password per build
- Certificates deleted immediately after installation

## Auto-Update System

The VM agent scripts can automatically update themselves from the latest release when the VM boots. This ensures workers always run the latest version without manual intervention.

**How it works:**
1. LaunchDaemon calls `/usr/local/bin/free-agent-auto-update` at VM boot
2. Auto-update script downloads latest `vm-scripts.tar.gz` from GitHub releases
3. Compares version with `/usr/local/etc/free-agent-version`
4. Updates scripts if newer version available
5. Execs bootstrap script with updated version

**Configuration:**
- Default URL: `https://github.com/sethwebster/expo-free-agent/releases/latest/download/vm-scripts.tar.gz`
- Override with env var: `FREE_AGENT_SCRIPTS_URL`

**Update process:**
1. Downloads scripts to temp directory
2. Validates all required scripts present
3. Backs up current scripts
4. Installs new scripts
5. Updates version file
6. Execs bootstrap

**Safety:**
- Non-fatal: If update fails, continues with existing version
- Automatic rollback on installation failure
- Version tracking prevents redundant updates

## Files

### 1. `free-agent-auto-update`

Launch wrapper that handles automatic script updates before bootstrap.

**Responsibilities:**
1. Downloads latest vm-scripts.tar.gz from GitHub
2. Extracts and validates scripts
3. Compares versions
4. Updates scripts if newer
5. Execs bootstrap script

**Environment Variables:**
- `FREE_AGENT_SCRIPTS_URL` (optional) - Override default download URL

**Exit Codes:**
- 0: Success (updated or already latest)
- Errors are non-fatal - continues with existing version

### 2. `free-agent-vm-bootstrap`

Main bootstrap script that runs at VM boot via LaunchDaemon.

**Responsibilities:**
1. Randomizes admin password (32-byte secure random)
2. Removes SSH authorized_keys
3. Validates environment variables
4. Fetches certs from controller with retry logic (3x: 5s, 15s, 45s backoff)
5. Calls cert installer
6. Shreds cert files
7. Signals ready via `/tmp/free-agent-ready`

**Environment Variables (passed by Tart):**
- `BUILD_ID` - Build identifier
- `WORKER_ID` - Worker identifier
- `API_KEY` - Authentication key
- `CONTROLLER_URL` - Controller base URL

**Exit Codes:**
- 0: Success
- 1: Missing environment variables
- 2: Certificate fetch failed
- 3: Certificate installation failed

### 2. `install-signing-certs`

Helper script to install iOS signing certificates and provisioning profiles.

**Responsibilities:**
1. Parses JSON cert bundle (`--certs` argument)
2. Decodes base64 P12 and profiles
3. Creates keychain with random password from JSON
4. Imports P12 with user-provided password
5. Sets partition list (allow codesign)
6. Installs provisioning profiles to `~/Library/MobileDevice/Provisioning Profiles/`
7. Shreds P12 file
8. Verifies installation

**Usage:**
```bash
install-signing-certs --certs /tmp/certs-secure.json
```

**JSON Structure:**
```json
{
  "p12": "base64-encoded-p12-file",
  "p12Password": "password-for-p12",
  "keychainPassword": "random-keychain-password",
  "provisioningProfiles": ["base64-profile1", "base64-profile2"]
}
```

**Exit Codes:**
- 0: Success
- 1: Invalid arguments
- 2: JSON parsing failed
- 3: P12 import failed
- 4: Keychain configuration failed
- 5: Profile installation failed
- 6: Verification failed

### 3. `free-agent-run-job`

Main build execution script that runs inside the VM.

**Responsibilities:**
1. Extracts source code
2. Installs dependencies
3. Runs Expo prebuild
4. Installs CocoaPods
5. Builds with xcodebuild
6. Exports IPA
7. Copies artifact to output

### 4. `vm-monitor.sh`

Background monitor that sends heartbeats and telemetry to controller.

**Responsibilities:**
1. Sends periodic heartbeats
2. Reports system metrics (CPU, memory, disk)
3. Detects build stage from logs
4. Securely loads credentials from file

### 5. `com.expo.free-agent.bootstrap.plist`

LaunchDaemon configuration that runs auto-update/bootstrap at VM boot.

**Configuration:**
- Runs at load (RunAtLoad: true)
- Executes `/usr/local/bin/free-agent-vm-bootstrap`
- Logs to `/tmp/free-agent-bootstrap.log`
- Environment variables inherited from Tart VM context
- One-shot execution (no restart on failure)

## Installation to VM Template

Follow these steps to prepare a secure VM template:

### Prerequisites

Boot base Tart VM and install dependencies:

```bash
# Inside VM
brew install jq
```

### Install Scripts

```bash
# Copy scripts to VM (from host)
tart copy <vm-name> free-agent-vm-bootstrap /usr/local/bin/
tart copy <vm-name> install-signing-certs /usr/local/bin/
tart copy <vm-name> com.expo.free-agent.bootstrap.plist /tmp/

# Inside VM: Set permissions and install LaunchDaemon
tart exec <vm-name> -- chmod +x /usr/local/bin/free-agent-vm-bootstrap
tart exec <vm-name> -- chmod +x /usr/local/bin/install-signing-certs
tart exec <vm-name> -- sudo cp /tmp/com.expo.free-agent.bootstrap.plist /Library/LaunchDaemons/
tart exec <vm-name> -- sudo chown root:wheel /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist
tart exec <vm-name> -- sudo chmod 644 /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist
```

### Load LaunchDaemon

```bash
# Inside VM
tart exec <vm-name> -- sudo launchctl load /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist
```

### Test Bootstrap

```bash
# Stop VM
tart stop <vm-name>

# Start with test env vars
tart run <vm-name> \
  --env BUILD_ID=test-123 \
  --env WORKER_ID=test-worker \
  --env API_KEY=test-key \
  --env CONTROLLER_URL=http://localhost:3000

# In another terminal, monitor bootstrap log
tart exec <vm-name> -- tail -f /tmp/free-agent-bootstrap.log

# Check for ready signal
tart exec <vm-name> -- test -f /tmp/free-agent-ready && echo "Ready!"

# Verify SSH blocked (should fail)
tart ip <vm-name>
ssh admin@<vm-ip>  # Should fail with "Permission denied"
```

### Save Template

```bash
# Shutdown VM cleanly
tart stop <vm-name>

# Clone to production template
tart clone <vm-name> expo-free-agent-tahoe-26.2-xcode-expo-54-secure
```

## Testing

### Unit Test: Bootstrap Script

```bash
# Test without env vars (should fail)
./free-agent-vm-bootstrap
# Expected: "ERROR: Missing required environment variables"

# Test with env vars (will fail at cert fetch without controller)
BUILD_ID=test-123 \
WORKER_ID=test-worker \
API_KEY=test-key \
CONTROLLER_URL=http://localhost:3000 \
./free-agent-vm-bootstrap
```

### Unit Test: Cert Installer

```bash
# Test with missing argument
./install-signing-certs
# Expected: Usage message

# Test with help flag
./install-signing-certs --help
# Expected: Usage documentation

# Test with test cert bundle (create mock JSON)
cat > /tmp/test-certs.json << 'EOF'
{
  "p12": "MIIJqQIBAzCC...base64...",
  "p12Password": "test123",
  "keychainPassword": "random-keychain-pass-123",
  "provisioningProfiles": []
}
EOF

./install-signing-certs --certs /tmp/test-certs.json
# Expected: Installation output, keychain created
```

### Integration Test: End-to-End

1. Start controller with `/api/builds/:id/certs-secure` endpoint
2. Upload test cert bundle to controller
3. Boot VM with real env vars
4. Monitor bootstrap log for success
5. Verify keychain contains signing identity
6. Verify provisioning profiles installed
7. Verify SSH access blocked
8. Run test build with code signing

## Security Validation

After VM boots:

```bash
# 1. Verify SSH blocked
ssh admin@<vm-ip>
# Should fail: "Permission denied"

# 2. Check cert files deleted
tart exec <vm-name> -- ls -la /tmp/*.p12 /tmp/*certs*.json
# Should show: "No such file or directory"

# 3. Verify keychain exists
tart exec <vm-name> -- security list-keychains
# Should include: "build.keychain-db"

# 4. Verify signing identity
tart exec <vm-name> -- security find-identity -v -p codesigning build.keychain-db
# Should list certificate(s)

# 5. Verify profiles installed
tart exec <vm-name> -- ls -la ~/Library/MobileDevice/Provisioning\ Profiles/
# Should list .mobileprovision files

# 6. Check bootstrap log
tart exec <vm-name> -- cat /tmp/free-agent-bootstrap.log
# Should show: "Bootstrap complete! VM ready for builds."
```

## Troubleshooting

### Bootstrap fails with timeout

Check bootstrap log:
```bash
tart exec <vm-name> -- cat /tmp/free-agent-bootstrap.log
```

Common issues:
- Controller URL unreachable (check network)
- Invalid API key (check credentials)
- Cert bundle not found (check build has certs uploaded)
- Worker not authorized for build (check X-Worker-Id header)

### Keychain import fails

Check installer output in bootstrap log:
```bash
tart exec <vm-name> -- grep "install-signing-certs" /tmp/free-agent-bootstrap.log
```

Common issues:
- Invalid P12 password
- Corrupted P12 file (check base64 encoding)
- Keychain already exists (old VM not cleaned)

### LaunchDaemon not running

Check LaunchDaemon status:
```bash
tart exec <vm-name> -- sudo launchctl list | grep free-agent
```

If not listed:
```bash
# Load manually
tart exec <vm-name> -- sudo launchctl load /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist
```

Check ownership and permissions:
```bash
tart exec <vm-name> -- ls -la /Library/LaunchDaemons/com.expo.free-agent.bootstrap.plist
# Should be: -rw-r--r-- root:wheel
```

## Dependencies

**Required in VM:**
- `curl` - Certificate fetching
- `openssl` - Password generation, file operations
- `jq` - JSON parsing
- `security` - Keychain management
- `base64` - Decoding
- `shred` - Secure file deletion (optional, falls back to rm)

**Install missing dependencies:**
```bash
tart exec <vm-name> -- brew install jq
```

## Next Steps

After Phase 1 implementation:

1. **Phase 2:** Implement controller endpoint `/api/builds/:id/certs-secure`
2. **Phase 3:** Update Swift worker to pass env vars (remove cert download)
3. **Phase 4:** Enable code signing in build script
4. **Phase 5:** End-to-end testing with real certs
5. **Phase 6:** Gradual rollout to workers

## References

- **Tracker:** `/plans/secure-cert-handling-tracker.md`
- **Tart Documentation:** https://github.com/cirruslabs/tart
- **Apple Keychain Guide:** https://developer.apple.com/documentation/security/keychain_services
