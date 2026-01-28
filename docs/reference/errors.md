# Error Reference

Complete catalog of error codes, messages, and solutions for Expo Free Agent.

## Error Code Format

```
EXPO-{COMPONENT}-{CODE}
```

- **COMPONENT**: Controller, Worker, CLI
- **CODE**: Numeric error code

**Example:** `EXPO-CLI-1001` = CLI authentication error

---

## CLI Errors (1000-1999)

### EXPO-CLI-1001: Authentication Failed

**Message:**
```
Error: Authentication failed
Invalid or missing API key
```

**Cause:** API key not provided or incorrect

**Solution:**
```bash
# Set API key
export EXPO_CONTROLLER_API_KEY="your-key-here"

# Or save to config file
echo '{"apiKey":"your-key"}' > ~/.expo-free-agent
```

### EXPO-CLI-1002: Controller Unreachable

**Message:**
```
Error: Unable to connect to controller
Connection refused at http://localhost:3000
```

**Cause:** Controller not running or wrong URL

**Solution:**
```bash
# Check controller is running
curl http://localhost:3000/health

# Or start controller
bun controller

# Verify URL
export EXPO_CONTROLLER_URL="http://192.168.1.100:3000"
```

### EXPO-CLI-1003: Upload Failed

**Message:**
```
Error: Upload failed
Request entity too large (413)
```

**Cause:** Project size exceeds controller limit

**Solution:**
```bash
# Reduce project size
echo "node_modules/" >> .gitignore
echo ".expo/" >> .gitignore

# Or increase controller limit (requires restart)
```

### EXPO-CLI-1004: Download Failed

**Message:**
```
Error: Download failed
File not found (404)
```

**Cause:** Build not complete or artifacts missing

**Solution:**
```bash
# Check build status
expo-build status build-abc123

# Wait for completion
expo-build wait build-abc123

# Then download
expo-build download build-abc123
```

### EXPO-CLI-1005: Invalid Build ID

**Message:**
```
Error: Invalid build ID format
Expected format: build-XXXXXX
```

**Cause:** Malformed build ID

**Solution:**
```bash
# List recent builds
expo-build list

# Use correct format
expo-build status build-abc123
```

### EXPO-CLI-1006: Timeout

**Message:**
```
Error: Request timeout
No response from controller after 30s
```

**Cause:** Network slow or controller unresponsive

**Solution:**
```bash
# Increase timeout
expo-build submit --timeout 120

# Check network
ping controller-ip
```

---

## Controller Errors (2000-2999)

### EXPO-CTL-2001: Port Already in Use

**Message:**
```
Error: EADDRINUSE: address already in use :::3000
```

**Cause:** Another process using port 3000

**Solution:**
```bash
# Find and kill process
kill $(lsof -t -i:3000)

# Or use different port
bun controller -- --port 8080
```

### EXPO-CTL-2002: Database Locked

**Message:**
```
Error: SQLITE_BUSY: database is locked
```

**Cause:** Database in use by another process

**Solution:**
```bash
# Stop all controller instances
pkill -f controller

# Restart
bun controller
```

### EXPO-CTL-2003: Disk Full

**Message:**
```
Error: ENOSPC: no space left on device
```

**Cause:** Storage directory full

**Solution:**
```bash
# Check disk usage
df -h

# Clean old builds
find storage/builds -mtime +30 -exec rm -rf {} +
```

### EXPO-CTL-2004: Invalid API Key

**Message:**
```
Error: Invalid API key format
Must be at least 16 characters
```

**Cause:** API key too short or missing

**Solution:**
```bash
# Generate secure key
export CONTROLLER_API_KEY=$(openssl rand -base64 32)

# Start controller
bun controller
```

### EXPO-CTL-2005: Database Corruption

**Message:**
```
Error: SQLITE_CORRUPT: database disk image is malformed
```

**Cause:** Database file corrupted

**Solution:**
```bash
# Restore from backup
cp ~/backups/controller-latest.db data/controller.db

# Or rebuild (loses data)
rm data/controller.db
bun controller
```

### EXPO-CTL-2006: Worker Not Found

**Message:**
```
Error: Worker not found
No worker with ID: worker-xyz
```

**Cause:** Worker disconnected or never registered

**Solution:**
```bash
# List active workers
curl http://localhost:3000/api/workers

# Reconnect worker
# Worker → Settings → Connect
```

---

## Worker Errors (3000-3999)

### EXPO-WKR-3001: Connection Failed

**Message:**
```
Error: Failed to connect to controller
Connection refused
```

**Cause:** Controller URL wrong or controller offline

**Solution:**
```bash
# Verify controller URL
ping controller-ip

# Test endpoint
curl http://controller-ip:3000/health

# Update worker settings
# Worker → Settings → Controller URL
```

### EXPO-WKR-3002: VM Creation Failed

**Message:**
```
Error: Failed to create VM
Operation not permitted
```

**Cause:** Missing permissions for virtualization

**Solution:**
```bash
# Grant Full Disk Access
# System Settings → Privacy & Security → Full Disk Access
# Add: /Applications/FreeAgent.app
```

### EXPO-WKR-3003: Out of Memory

**Message:**
```
Error: Cannot allocate memory
Requested: 8 GB, Available: 4 GB
```

**Cause:** Insufficient RAM for VM

**Solution:**
```bash
# Reduce VM memory
# Worker → Settings → Memory per VM: 4 GB

# Or upgrade Mac RAM
```

### EXPO-WKR-3004: Disk Space Low

**Message:**
```
Error: Insufficient disk space
Required: 20 GB, Available: 5 GB
```

**Cause:** Not enough disk space for build

**Solution:**
```bash
# Free up space
# Delete old VMs
# Worker → Maintenance → Clean VMs

# Check disk usage
df -h
```

### EXPO-WKR-3005: Upload Failed

**Message:**
```
Error: Failed to upload artifacts
Network error or timeout
```

**Cause:** Network issue or controller unreachable

**Solution:**
```bash
# Check network
ping controller-ip

# Retry upload
# (Currently manual: resubmit build)

# Check controller disk space
ssh user@controller
df -h
```

### EXPO-WKR-3006: Build Timeout

**Message:**
```
Error: Build exceeded timeout
Maximum: 30 minutes, Actual: 31 minutes
```

**Cause:** Build took too long

**Solution:**
```bash
# Increase timeout
expo-build submit --timeout 60

# Or optimize build:
# - Use faster Mac
# - Optimize dependencies
# - Enable build cache
```

---

## Build Errors (4000-4999)

### EXPO-BLD-4001: Dependency Resolution Failed

**Message:**
```
npm ERR! ERESOLVE unable to resolve dependency tree
```

**Cause:** Conflicting dependency versions

**Solution:**
```bash
# Use legacy peer deps
echo "legacy-peer-deps=true" >> .npmrc

# Or fix package.json
npm install package@compatible-version
```

### EXPO-BLD-4002: Code Signing Failed

**Message:**
```
error: No certificate for team 'ABC123' matching 'Apple Distribution'
```

**Cause:** Missing or invalid signing certificate

**Solution:**
```bash
# Export new certificate
# Xcode → Preferences → Accounts → Manage Certificates → Export

# Resubmit with cert
expo-build submit --cert dist-cert.p12
```

### EXPO-BLD-4003: Provisioning Profile Invalid

**Message:**
```
error: Provisioning profile has expired
```

**Cause:** Provisioning profile expired

**Solution:**
```bash
# Download new profile
# developer.apple.com → Certificates, IDs & Profiles

# Resubmit
expo-build submit --provision new-profile.mobileprovision
```

### EXPO-BLD-4004: Build Script Failed

**Message:**
```
Error: Build script exited with code 1
```

**Cause:** Custom build script failed

**Solution:**
```bash
# Check build logs
expo-build logs build-abc123

# Debug locally
npm run build

# Fix script and retry
```

### EXPO-BLD-4005: Native Module Linking Failed

**Message:**
```
Undefined symbols for architecture arm64
```

**Cause:** Missing native dependencies

**Solution:**
```bash
# Install pods
cd ios && pod install && cd ..

# Or update pods
cd ios && pod update && cd ..

# Resubmit
expo-build submit
```

### EXPO-BLD-4006: Configuration Invalid

**Message:**
```
Error: Invalid app.json
Missing required field: "expo.ios.bundleIdentifier"
```

**Cause:** Incorrect or missing configuration

**Solution:**
```json
{
  "expo": {
    "ios": {
      "bundleIdentifier": "com.company.app"
    }
  }
}
```

---

## Network Errors (5000-5999)

### EXPO-NET-5001: Connection Timeout

**Message:**
```
Error: ETIMEDOUT
Connection timed out after 30s
```

**Cause:** Network too slow or firewall blocking

**Solution:**
```bash
# Check connectivity
ping controller-ip

# Check firewall
sudo ufw status

# Increase timeout
expo-build submit --timeout 120
```

### EXPO-NET-5002: SSL Verification Failed

**Message:**
```
Error: UNABLE_TO_VERIFY_LEAF_SIGNATURE
Self-signed certificate
```

**Cause:** Invalid or self-signed SSL certificate

**Solution:**
```bash
# For production: Use valid certificate (Let's Encrypt)

# For development only (not secure):
export NODE_TLS_REJECT_UNAUTHORIZED=0
```

### EXPO-NET-5003: DNS Resolution Failed

**Message:**
```
Error: ENOTFOUND
Could not resolve hostname
```

**Cause:** DNS issue or hostname typo

**Solution:**
```bash
# Use IP address instead
export EXPO_CONTROLLER_URL="http://192.168.1.100:3000"

# Or check DNS
nslookup controller.example.com
```

### EXPO-NET-5004: Connection Refused

**Message:**
```
Error: ECONNREFUSED
Connection refused
```

**Cause:** Service not running or port blocked

**Solution:**
```bash
# Check service is running
curl http://localhost:3000/health

# Check port is open
telnet localhost 3000

# Start service
bun controller
```

---

## Platform-Specific Errors (6000-6999)

### EXPO-IOS-6001: Xcode Not Found

**Message:**
```
Error: Xcode not found
Required for iOS builds
```

**Cause:** Xcode not installed on worker

**Solution:**
```bash
# Install Xcode from App Store

# Accept license
sudo xcodebuild -license accept

# Install components
sudo xcodebuild -runFirstLaunch
```

### EXPO-IOS-6002: Simulator Not Available

**Message:**
```
Error: No iOS simulator available
```

**Cause:** iOS simulators not installed

**Solution:**
```bash
# Install simulators
xcode-select --install

# List available
xcrun simctl list devices

# Create new
xcrun simctl create "iPhone 15" com.apple.CoreSimulator.SimDeviceType.iPhone-15
```

### EXPO-AND-6001: Android SDK Not Found

**Message:**
```
Error: Android SDK not found
Required for Android builds
```

**Cause:** Android SDK not installed

**Solution:**
```bash
# Install Android Studio

# Set ANDROID_HOME
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/tools
export PATH=$PATH:$ANDROID_HOME/platform-tools
```

### EXPO-MAC-6001: Virtualization Not Supported

**Message:**
```
Error: Virtualization not supported
Apple Virtualization Framework unavailable
```

**Cause:** macOS too old or not Apple Silicon/Intel VT-x

**Solution:**
```
# Upgrade to macOS 13.0+ (Ventura)

# Or use Apple Silicon Mac (M1/M2/M3)

# Intel Macs: Ensure VT-x enabled in BIOS
```

---

## Error Code Quick Reference

| Code | Category | Severity | Typical Cause |
|------|----------|----------|---------------|
| 1001-1099 | CLI Auth | Error | API key issues |
| 1100-1199 | CLI Network | Error | Connectivity |
| 1200-1299 | CLI Operation | Error | Invalid input |
| 2001-2099 | Controller Setup | Fatal | Configuration |
| 2100-2199 | Controller DB | Fatal | Database issues |
| 2200-2299 | Controller API | Error | API errors |
| 3001-3099 | Worker Connection | Error | Network/auth |
| 3100-3199 | Worker VM | Error | Virtualization |
| 3200-3299 | Worker Resources | Error | Memory/disk |
| 4001-4099 | Build Deps | Error | Dependencies |
| 4100-4199 | Build Signing | Error | Certificates |
| 4200-4299 | Build Compile | Error | Code errors |
| 5001-5099 | Network General | Error | Connectivity |
| 5100-5199 | Network SSL | Error | Certificates |
| 6001-6099 | Platform iOS | Error | iOS-specific |
| 6100-6199 | Platform Android | Error | Android-specific |

---

## Getting Additional Help

If your error isn't listed:

1. **Check logs:** `expo-build logs build-id`
2. **Search GitHub Issues:** [github.com/expo/expo-free-agent/issues](https://github.com/expo/expo-free-agent/issues)
3. **Create bug report:** Include error code, logs, and steps to reproduce
4. **Join Discord:** [discord.gg/expo](https://discord.gg/expo) (future)

---

**Last Updated:** 2026-01-28
