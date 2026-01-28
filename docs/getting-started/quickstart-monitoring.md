# Quick Start: VM Monitoring Setup

Automated setup for adding build monitoring to your Tart VM base image.

## What This Does

The setup script automatically:
- ✅ Clones your base Tart VM
- ✅ Installs the monitoring script (`vm-monitor.sh`)
- ✅ Sets up SSH keys for automation
- ✅ Creates a production-ready monitored image
- ✅ Cleans up temporary files

## Prerequisites

1. **Tart installed**
   ```bash
   brew install cirruslabs/cli/tart
   ```

2. **Base image exists**
   ```bash
   tart list | grep expo-free-agent-tahoe-26.2-xcode-expo-54
   ```

3. **SSH enabled in base image**
   (Should already be configured per TART-SETUP.md)

## One Command Setup

```bash
./setup-vm-monitoring.sh
```

That's it! The script handles everything.

### Custom Base Image

If your base image has a different name:

```bash
./setup-vm-monitoring.sh your-custom-image-name
```

## What Happens During Setup

```
1. Prerequisites check          ✓
2. Clone base → temp VM         ✓
3. Start VM (headless)          ✓
4. Detect VM IP                 ✓
5. Test SSH connection          ✓
6. Install monitor script       ✓
7. Set up SSH keys              ✓
8. Stop VM                      ✓
9. Create final image           ✓
10. Cleanup                     ✓
```

**Time:** ~2-3 minutes

## Output

The script creates a new VM image:

```
expo-free-agent-tahoe-26.2-xcode-expo-54-monitored
```

And an SSH key for automation:

```
~/.ssh/tart_free_agent
~/.ssh/tart_free_agent.pub
```

## Verify Installation

### 1. Check the new image exists

```bash
tart list | grep monitored
```

### 2. Start the VM

```bash
tart run expo-free-agent-tahoe-26.2-xcode-expo-54-monitored --no-graphics &
```

### 3. Test SSH

```bash
tart ip expo-free-agent-tahoe-26.2-xcode-expo-54-monitored
ssh -i ~/.ssh/tart_free_agent admin@<vm-ip> "echo 'SSH works'"
```

### 4. Test monitor script

```bash
ssh -i ~/.ssh/tart_free_agent admin@<vm-ip> \
  "/usr/local/bin/vm-monitor.sh \
   http://localhost:3000 \
   test-build \
   test-worker \
   test-key \
   5"
```

Expected output:
```
[VM Monitor] Starting for build test-build
[VM Monitor] Sending heartbeats every 5s to http://localhost:3000
[VM Monitor] Heartbeat sent (progress: 0%)
[VM Monitor] Heartbeat sent (progress: 5%)
...
```

Press Ctrl+C to stop.

## Next Steps

### Update Worker Configuration

If using the Swift worker, update settings to use the new monitored image:

**GUI App Settings:**
- VM Image: `expo-free-agent-tahoe-26.2-xcode-expo-54-monitored`
- SSH Key: `~/.ssh/tart_free_agent`
- VM User: `admin`

**Or in config file:**

```json
{
  "vmImage": "expo-free-agent-tahoe-26.2-xcode-expo-54-monitored",
  "vmUser": "admin",
  "vmSshKey": "~/.ssh/tart_free_agent",
  "controllerUrl": "http://localhost:3000",
  "apiKey": "your-api-key"
}
```

### Test End-to-End

1. **Start controller**
   ```bash
   cd packages/controller
   CONTROLLER_API_KEY="test-api-key-1234567890" bun run start
   ```

2. **Start worker (GUI app)**
   ```bash
   cd free-agent
   .build/debug/FreeAgent
   ```

3. **Submit test build**
   ```bash
   cd cli
   EXPO_CONTROLLER_API_KEY="test-api-key-1234567890" \
     bun run dev submit /path/to/project.tar.gz
   ```

4. **Monitor progress**
   - Watch menu bar for active build
   - Green dot should appear on icon
   - Check controller logs for heartbeats:
     ```
     [timestamp] POST /api/builds/<id>/heartbeat
     ```

## Troubleshooting

### "Base image not found"

**Problem:** Tart can't find your base image

**Solution:**
```bash
tart list  # Verify the exact name
./setup-vm-monitoring.sh <exact-name>
```

### "SSH connection failed"

**Problem:** Can't connect to VM via SSH

**Causes:**
1. Remote Login not enabled in base image
2. VM not fully booted
3. Firewall blocking connection

**Solution:**
```bash
# Manual setup:
tart run expo-free-agent-tahoe-26.2-xcode-expo-54

# Inside VM:
sudo systemsetup -setremotelogin on

# Shut down VM, run script again
```

### "Final image already exists"

**Problem:** Previous setup created the monitored image

**Solution:**
```bash
# Delete old image
tart delete expo-free-agent-tahoe-26.2-xcode-expo-54-monitored

# Run setup again
./setup-vm-monitoring.sh
```

### Script hangs at "Waiting for VM to boot"

**Problem:** VM taking longer than 30s to start

**Solution:**
Wait longer (VMs can take 1-2 minutes on first boot), or:

```bash
# Kill the script (Ctrl+C)
# Manually check VM status
tart list
tart ip expo-free-agent-tahoe-26.2-xcode-expo-54-setup-temp

# Once VM is up, re-run script
```

### Heartbeats not appearing in controller logs

**Checklist:**
- [ ] Controller is running
- [ ] Monitor script exists: `ssh admin@<vm> "ls -l /usr/local/bin/vm-monitor.sh"`
- [ ] curl works in VM: `ssh admin@<vm> "curl http://localhost:3000/health"`
- [ ] API key matches between worker and controller
- [ ] Worker ID is correct (check worker registration logs)

## Security Notes

### SSH Key Isolation

The setup creates a dedicated SSH key (`~/.ssh/tart_free_agent`) specifically for VM automation. This is separate from your personal SSH keys.

**Best practices:**
- ✅ One key per use case (VM automation vs personal)
- ✅ Key is passwordless (for automation)
- ✅ Key only works for `admin` user in Tart VMs
- ✅ Rotate keys quarterly

### API Key Security

The monitor script receives the API key as a parameter when started by the worker. The key is:
- ❌ Never stored in the VM image
- ❌ Never hardcoded in scripts
- ✅ Passed at runtime only
- ✅ Transmitted over HTTPS in production

### VM Network Isolation

In production, VMs should:
- ✅ Only access controller URL
- ❌ Not access public internet (prevents data exfiltration)
- ❌ Not access AWS metadata (169.254.169.254)

Use firewall rules or network policies to enforce this.

## Advanced Usage

### Multiple Base Images

Set up monitoring for multiple base images:

```bash
./setup-vm-monitoring.sh expo-ios-base
./setup-vm-monitoring.sh expo-android-base
./setup-vm-monitoring.sh expo-custom-base
```

Each creates a corresponding `-monitored` image.

### Custom Heartbeat Interval

The default heartbeat interval is 30 seconds. To change:

Edit `vm-monitor.sh` and modify:
```bash
INTERVAL="${5:-30}"  # Change 30 to your preferred interval
```

Shorter intervals = faster timeout detection, but more API calls.

### Real Progress Tracking

For accurate build progress instead of estimates, integrate with your build tool:

**Fastlane example:**
```ruby
lane :build do
  send_heartbeat(10)
  match(type: "appstore")
  send_heartbeat(40)
  gym
  send_heartbeat(90)
end
```

**Xcode script:**
Parse build log and call `curl` with progress updates.

## Cleanup

To remove the monitored image:

```bash
tart delete expo-free-agent-tahoe-26.2-xcode-expo-54-monitored
```

To remove the SSH key:

```bash
rm ~/.ssh/tart_free_agent*
```

## Support

For issues or questions:
- Check `VM_SETUP.md` for detailed VM configuration
- Check `SETUP_LOCAL.md` for full E2E setup
- Review controller logs for heartbeat errors
- Verify SSH connectivity with manual test commands
