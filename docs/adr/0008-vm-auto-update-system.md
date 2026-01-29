# ADR-0008: VM Auto-Update System for Script Distribution

**Status:** Accepted

**Date:** 2026-01-27 (Commit b150321)

## Context

VM execution scripts (`free-agent-run-job`, `free-agent-auto-update`) are baked into base VM image during template creation. When bugs are found or features added:

**Original workflow:**
1. Fix script in `vm-setup/` directory
2. Rebuild entire VM image (~30 min)
3. Push 50GB image to container registry (~20 min)
4. Workers pull new image on next boot (~10 min)
5. Total time to deploy fix: **60+ minutes**

**Problem scenarios:**
- P0 bug in job execution script → 1 hour to fix all workers
- Security vulnerability in credential handling → emergency rebuild required
- Feature addition (log streaming) → cannot deploy without VM rebuild
- No rollback mechanism if new image breaks

## Decision

Implement **auto-update system** that downloads scripts from GitHub releases at VM boot:

### Architecture

```
VM boot
  ↓
LaunchDaemon runs free-agent-auto-update
  ↓
Check /usr/local/etc/VERSION file
  ↓
Download vm-scripts.tar.gz from GitHub releases
  ↓
Compare VERSION in tarball vs installed
  ↓
If newer: extract to /usr/local/bin/, update VERSION file
  ↓
Exec free-agent-bootstrap (continue boot)
```

### Implementation Details

**LaunchDaemon** (`com.sethwebster.free-agent-auto-update.plist`):
```xml
<key>ProgramArguments</key>
<array>
  <string>/usr/local/bin/free-agent-auto-update</string>
</array>
<key>RunAtLoad</key>
<true/>
```

**Update Script** (`free-agent-auto-update`):
```bash
#!/bin/bash
CURRENT_VERSION=$(cat /usr/local/etc/VERSION 2>/dev/null || echo "none")
RELEASE_URL="https://github.com/.../releases/latest/download/vm-scripts.tar.gz"

curl -sL "$RELEASE_URL" -o /tmp/vm-scripts.tar.gz
tar -xzf /tmp/vm-scripts.tar.gz -C /tmp/

NEW_VERSION=$(cat /tmp/VERSION)
if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
  sudo cp /tmp/free-agent-* /usr/local/bin/
  sudo chmod +x /usr/local/bin/free-agent-*
  echo "$NEW_VERSION" | sudo tee /usr/local/etc/VERSION
fi

exec /usr/local/bin/free-agent-bootstrap
```

**Fallback:** If download fails, exec existing scripts (no boot failure).

## Consequences

### Positive

- **Instant hotfixes:** Script fixes deploy in seconds vs hours
  - No VM rebuild required
  - No image push/pull required
  - Workers auto-update on next boot
- **Versioned rollback:** Can pin workers to specific VERSION
- **Staged rollouts:** Deploy to subset of workers, monitor, rollout
- **Public installer:** `curl | bash` setup script uses same mechanism
- **Graceful degradation:** Download failure doesn't brick VM
- **Minimal overhead:** VERSION check skips download if current
- **Audit trail:** VERSION file shows what's running

### Negative

- **Network dependency:** VMs must reach GitHub at boot
  - Breaks in airgapped environments
  - Adds 2-5s boot latency
- **No signature verification:** Scripts downloaded over HTTPS but not GPG signed
  - Vulnerable to GitHub compromise
  - Vulnerable to MITM if TLS broken
- **Boot-time updates only:** Running VMs don't get updates (ephemeral VMs = okay)
- **No atomic rollback:** Bad update could break all VMs until next release
- **GitHub dependency:** Outage blocks new VMs (existing VMs fallback to old scripts)
- **Version skew:** Worker and VM scripts could be out of sync
- **Credential exposure:** Scripts write API key to temp file in VM (mitigated by 0600 + delete)

### Security Considerations

**Threat: GitHub release hijack**
- Attack: Compromise GitHub account, push malicious scripts
- Impact: All booting VMs execute malicious code
- Mitigations:
  - 2FA on GitHub account (implemented)
  - GitHub audit log monitoring
  - **TODO:** GPG sign vm-scripts.tar.gz, verify signature before extraction

**Threat: TLS MITM during download**
- Attack: Intercept HTTPS connection, replace scripts
- Impact: Worker executes malicious scripts
- Mitigations:
  - TLS certificate validation (curl default behavior)
  - **TODO:** Pin GitHub TLS certificate or use checksum verification

**Threat: Malicious VERSION file**
- Attack: Craft VERSION file to trigger command injection
- Impact: Arbitrary code execution during VERSION comparison
- Mitigation: VERSION file read with `cat`, used in string comparison (safe)

## Performance Impact

**Boot time overhead:**
- Check VERSION file: ~1ms
- Download tarball (2KB): ~500ms
- Extract + install: ~100ms
- Total: **~600ms per boot**

Acceptable for 5-30 minute build jobs.

**Network usage:**
- 2KB download per VM boot
- 100 VMs/hour = 200KB/hour = negligible

## Alternative Approaches Considered

### Bake scripts into worker app, inject at clone time

**Approach:** Worker app bundles scripts, writes to VM disk at clone creation.

**Pros:**
- No network dependency at boot
- Scripts versioned with worker app
- No GitHub availability requirement

**Cons:**
- Worker app version determines VM scripts (tight coupling)
- Requires filesystem access to VM disk (Tart limitation)
- No hotfix path without worker app update
- Workers must restart to get new scripts

**Rejected:** Tight coupling prevents independent script updates.

### Pull scripts on every job execution

**Approach:** Download scripts at start of each build, not at boot.

**Pros:**
- Always latest version
- No LaunchDaemon required

**Cons:**
- Network latency on every build
- Failure mid-build if GitHub down
- 100 builds/day = 100 downloads vs 1 at boot
- Race condition: script changes mid-build

**Rejected:** Network dependency during build execution too risky.

### Use tart run --script to inject scripts

**Approach:** Tart supports `--script` flag to run command at boot.

**Pros:**
- No LaunchDaemon required
- Scripts managed by worker app

**Cons:**
- Script must be specified at `tart run` time
- Tight coupling to worker implementation
- No standalone VM bootstrap
- Tart version dependency

**Rejected:** Reduces VM portability.

## Migration Path

**Current state:** All workers using auto-update (v0.1.23+)

**Future improvements:**
1. Add GPG signing to release workflow
2. Verify signature in auto-update script
3. Add checksum verification as backup
4. Implement staged rollouts (VERSION=v0.1.24-beta for subset)
5. Add update metrics (track which versions running)

## Public Installer

`vm-setup/install.sh` uses same mechanism:
```bash
curl -sL https://github.com/.../releases/latest/download/vm-scripts.tar.gz | \
  tar -xzf - -C /tmp
sudo cp /tmp/free-agent-* /usr/local/bin/
```

Enables one-line VM setup:
```bash
curl -fsSL https://github.com/.../vm-setup/install.sh | bash
```

## References

- Auto-update script: `vm-setup/free-agent-auto-update`
- Bootstrap script: `vm-setup/free-agent-bootstrap`
- LaunchDaemon plist: `vm-setup/com.sethwebster.free-agent-auto-update.plist`
- Public installer: `vm-setup/install.sh`
- Release workflow: `.github/workflows/release-vm-scripts.yml` (if exists)
