# Expo Free Agent - Security Architecture

## Overview

Expo Free Agent is designed with security as a foundational principle. This document explains the security model, threat boundaries, and protections that make the system safe for distributed build execution.

## Security Model

### Core Principles

1. **Defense in Depth**: Multiple layers of security, no single point of failure
2. **Least Privilege**: Components only have access to what they need
3. **Isolation First**: Build workloads are isolated from host and each other
4. **Trust but Verify**: All inputs validated, all outputs verified
5. **Transparency**: Security through design, not obscurity

### Trust Boundaries

```
┌─────────────────────────────────────────────────────────────┐
│ User Machine (Untrusted)                                    │
│ ┌──────────────┐                                            │
│ │ Submit CLI   │ ──────────────────────────────────────┐    │
│ └──────────────┘                                        │    │
└─────────────────────────────────────────────────────────┼────┘
                                                          │
                          HTTPS + API Key                 │
                                                          ▼
┌─────────────────────────────────────────────────────────────┐
│ Controller (Trusted)                                        │
│ ┌──────────────────────────────────────────────────────┐   │
│ │ • Authentication & authorization                      │   │
│ │ • Input validation & sanitization                     │   │
│ │ • Path traversal protection                           │   │
│ │ • Rate limiting                                        │   │
│ │ • Audit logging                                        │   │
│ └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                                │
                                │ Job Assignment (Isolated)
                                ▼
┌─────────────────────────────────────────────────────────────┐
│ Worker Machine (Semi-Trusted)                               │
│ ┌────────────────────────────────────────────────────┐     │
│ │ VM (Isolated Build Environment)                     │     │
│ │ ┌────────────────────────────────────────────────┐ │     │
│ │ │ Build Process (Untrusted Code)                 │ │     │
│ │ │ • No network access (blocked)                  │ │     │
│ │ │ • Read-only system files                       │ │     │
│ │ │ • Temporary filesystem                         │ │     │
│ │ │ • No host access                               │ │     │
│ │ │ • Resource limits enforced                     │ │     │
│ │ └────────────────────────────────────────────────┘ │     │
│ │ Apple Virtualization Framework (Hardware isolation) │     │
│ └────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

## Threat Model

### What We Protect Against

#### 1. Malicious Build Code
**Threat**: User submits build that attempts to:
- Steal secrets from worker machine
- Mine cryptocurrency
- Attack other systems on network
- Exfiltrate data
- Persist after build completes

**Mitigation**:
- ✅ **VM isolation**: Build runs in disposable VM
- ✅ **No host access**: VM cannot access worker machine filesystem, processes, or memory
- ✅ **Network isolation**: No outbound network access from build (optional: allow specific domains)
- ✅ **Ephemeral environment**: VM destroyed after build, no persistence
- ✅ **Resource limits**: CPU, memory, disk, and time limits enforced
- ✅ **Apple Virtualization Framework**: Hardware-level isolation (not containers)

#### 2. Source Code Exposure
**Threat**: User's proprietary source code exposed to:
- Controller operator
- Worker operator
- Network eavesdroppers
- Storage leaks

**Mitigation**:
- ✅ **HTTPS everywhere**: All network traffic encrypted (TLS 1.3)
- ✅ **Temporary storage**: Source deleted immediately after build
- ✅ **No logging of code**: Logs never contain source code
- ✅ **Isolated builds**: Workers cannot access other users' builds
- ✅ **Worker trust model**: Workers are semi-trusted (user-operated or vetted)

#### 3. Artifact Tampering
**Threat**: Build artifacts modified between:
- Worker → Controller
- Controller → User
- Or replaced with malicious versions

**Mitigation**:
- ✅ **Checksums**: SHA-256 hashes computed and verified
- ✅ **HTTPS transport**: No man-in-the-middle possible
- ✅ **Atomic operations**: Files written atomically, no partial states
- ✅ **Immutable storage**: Artifacts cannot be modified after creation
- ✅ **Code signing**: Apple-signed artifacts (Developer ID)

#### 4. Authentication Bypass
**Threat**: Unauthorized access to:
- Submit builds
- Download artifacts
- Access controller admin functions
- Impersonate workers

**Mitigation**:
- ✅ **API key authentication**: Required for all operations
- ✅ **Key rotation**: Users can regenerate keys anytime
- ✅ **No default credentials**: Keys must be explicitly set
- ✅ **Worker authentication**: Workers authenticate with controller
- ✅ **Rate limiting**: Prevents brute force attacks

#### 5. Path Traversal
**Threat**: Attacker uses `../` in filenames to:
- Access files outside storage directory
- Overwrite system files
- Read sensitive data

**Mitigation**:
- ✅ **Path normalization**: All paths normalized and validated
- ✅ **Jail to storage directory**: All operations confined to storage root
- ✅ **Filename sanitization**: Dangerous characters rejected
- ✅ **Symlink protection**: Symlinks rejected or resolved safely
- ✅ **Tests**: Explicit path traversal attack tests in test suite

#### 6. Resource Exhaustion (DoS)
**Threat**: Attacker exhausts resources via:
- Infinite build loops
- Large file uploads
- Rapid API requests
- Disk space consumption

**Mitigation**:
- ✅ **Build timeouts**: Maximum build time enforced (default: 30 minutes)
- ✅ **File size limits**: Maximum upload size (configurable)
- ✅ **Rate limiting**: API request throttling
- ✅ **Storage quotas**: Maximum storage per user/build
- ✅ **VM resource limits**: CPU and memory capped per build
- ✅ **Cleanup**: Old builds auto-deleted after retention period

#### 7. Worker Compromise
**Threat**: Worker machine compromised by:
- Malware
- Malicious operator
- Persistent attacker

**Impact Mitigation**:
- ✅ **Ephemeral VMs**: Even compromised worker cannot persist in VM
- ✅ **No secrets in VMs**: Workers don't have access to user secrets
- ✅ **Limited blast radius**: Compromised worker only affects jobs assigned to it
- ✅ **Audit logs**: All worker actions logged at controller
- ✅ **Worker reputation**: (Future) Track worker reliability and security

#### 8. Controller Compromise
**Threat**: Controller database/storage accessed by attacker

**Mitigation**:
- ✅ **Filesystem permissions**: SQLite database has restrictive permissions
- ✅ **No plaintext secrets**: API keys hashed (bcrypt)
- ✅ **Separated storage**: User artifacts isolated by directory
- ✅ **Audit logging**: All access logged
- ⚠️ **Encryption at rest**: (Future) Encrypt stored artifacts
- ⚠️ **HSM integration**: (Future) Store keys in hardware security module

## Isolation Mechanisms

### VM-Based Isolation

**Why VMs, not containers?**

Containers (Docker, Podman) share the host kernel and are vulnerable to:
- Kernel exploits
- Container escape vulnerabilities
- Resource namespace attacks

**Apple Virtualization Framework**:
- Hardware-level isolation (uses Hypervisor.framework)
- Separate kernel per VM
- No shared kernel surfaces
- Enforced by macOS security model
- Same technology as Parallels, UTM

### Build Environment Hardening

Inside each VM:
- **Read-only system files**: `/System`, `/Library`, `/usr` mounted read-only
- **Temporary workspace**: Build happens in isolated `/tmp/build-{id}`
- **No persistent state**: Filesystem changes discarded after build
- **Limited network**: Outbound network blocked by default
- **No GUI access**: Headless execution only
- **Process isolation**: Build process cannot see other processes

### Network Security

**Controller**:
- HTTPS required (no HTTP fallback)
- TLS 1.3 preferred
- Strong cipher suites only
- HSTS headers
- Certificate validation enforced

**Worker → Controller**:
- Mutual authentication via API key
- HTTPS for artifact upload/download
- Exponential backoff on failures
- Connection timeout protection

**Build → Network** (inside VM):
- No outbound network by default
- Optional: allowlist specific domains (npm registry, GitHub)
- DNS controlled (can block exfiltration domains)
- No SSH/remote access into VMs

## Code Signing & Notarization

### Why It Matters

macOS Gatekeeper blocks unsigned or improperly signed apps. This protects users from:
- Malware distribution
- Tampering with downloaded apps
- Unsigned code execution

### Our Implementation

**FreeAgent.app (Worker)**:
- ✅ Signed with Developer ID Application certificate
- ✅ Hardened runtime enabled (`--options runtime`)
- ✅ Entitlements declared (`com.apple.vm.hypervisor`)
- ✅ Notarized by Apple (malware scan passed)
- ✅ Stapled ticket (works offline)

**Verification**:
```bash
# Signature verification
codesign --verify --deep --strict FreeAgent.app

# Gatekeeper acceptance
spctl --assess --type execute --verbose FreeAgent.app
# Output: accepted source=Notarized Developer ID

# Notarization ticket
xcrun stapler validate FreeAgent.app
```

**Protection Against**:
- ❌ Unsigned modifications (signature breaks)
- ❌ Code injection (signature breaks)
- ❌ Malware (Apple scan rejects)
- ❌ Unknown developers (gatekeeper blocks)

### Distribution Security

**Worker Installer**:
- Downloads from HTTPS only
- Verifies SHA-256 checksum
- Uses native `tar` (preserves code signatures)
- Uses `ditto` for installation (preserves signatures)
- Never removes quarantine attributes (respects Gatekeeper)

**Anti-Patterns Avoided**:
- ❌ `npm tar` package (creates AppleDouble files, breaks signatures)
- ❌ `xattr -cr` (removes quarantine, bypasses Gatekeeper)
- ❌ `spctl --add` (adds exception, weakens security)
- ❌ Generic file copying (breaks extended attributes)

See: [Gatekeeper Documentation](../operations/gatekeeper.md)

## Data Protection

### In Transit
- ✅ TLS 1.3 for all network communication
- ✅ No plaintext protocols
- ✅ Certificate validation enforced
- ✅ Strong cipher suites only

### At Rest
- ✅ Restrictive filesystem permissions (0600 for sensitive files)
- ✅ API keys hashed (bcrypt, not plaintext)
- ✅ Temporary files cleaned up immediately
- ⚠️ Artifacts stored unencrypted (future: encryption at rest)
- ⚠️ Database unencrypted (future: SQLCipher)

### In Use
- ✅ No secrets in logs
- ✅ API keys redacted in verbose output
- ✅ Build logs sanitized (no env vars leaked)
- ✅ Memory-safe operations (Bun/Node.js memory management)

## Authentication & Authorization

### API Key Model

**Generation**:
- Cryptographically random (32 bytes)
- Base64 encoded
- Unique per user

**Storage**:
- Controller: bcrypt hashed (cost factor 10)
- User: stored in `~/.expo-free-agent` or env var
- CLI: never passed via command-line args (shell history leak)

**Validation**:
```typescript
// Timing-safe comparison to prevent timing attacks
const isValid = await bcrypt.compare(providedKey, storedHash)
```

**Rotation**:
- Users can regenerate keys anytime
- Old key immediately invalidated
- No grace period (fail fast)

### Authorization Model

Currently: **Single-tenant** (one user per controller instance)

Future: **Multi-tenant** with:
- User isolation (users cannot see each other's builds)
- Role-based access control (admin, user, worker)
- Build ownership (only owner can download artifacts)
- Worker pools (assign workers to specific users)

## Audit Logging

**What We Log**:
- Build submission (user, timestamp, metadata)
- Worker registration and heartbeats
- Job assignment and completion
- Artifact downloads
- Authentication failures
- API errors

**What We Don't Log**:
- Source code contents
- Environment variables
- API keys (even hashed)
- File contents
- User secrets

**Log Retention**:
- Configurable (default: 30 days)
- Automatic cleanup
- No PII in logs

## Security Best Practices for Operators

### Controller Deployment

**Recommended**:
- Run on dedicated VPS or isolated VM
- Firewall rules (only expose HTTPS port)
- Regular security updates
- Separate user account (non-root)
- Backup database and storage regularly
- Monitor logs for suspicious activity

**Configuration**:
```bash
# Set restrictive permissions
chmod 700 ~/expo-free-agent/data
chmod 600 ~/expo-free-agent/data/controller.db

# Use strong API key
CONTROLLER_API_KEY=$(openssl rand -base64 32)

# Enable HTTPS (behind reverse proxy)
# Let Nginx/Caddy handle TLS termination
```

### Worker Deployment

**Recommended**:
- Dedicated Mac (not your development machine)
- Automatic updates enabled
- FileVault disk encryption enabled
- Standard user account (not admin)
- Network isolated from sensitive systems
- Monitor CPU/memory usage

**Configuration**:
```bash
# Limit VM resources
defaults write com.expo.freeagent maxVMCPUs 4
defaults write com.expo.freeagent maxVMMemoryGB 8

# Set build timeout
defaults write com.expo.freeagent buildTimeoutMinutes 30
```

## Known Limitations & Future Improvements

### Current Limitations

1. **No artifact encryption**: Artifacts stored unencrypted on controller disk
   - *Impact*: Controller compromise exposes all artifacts
   - *Mitigation*: Restrict controller access, use encrypted filesystem
   - *Future*: Encrypt artifacts with user-specific keys

2. **Single-tenant controller**: No multi-user isolation
   - *Impact*: All users trust controller operator
   - *Future*: Multi-tenant mode with user isolation

3. **No worker attestation**: Workers not cryptographically verified
   - *Impact*: Malicious worker could be added
   - *Mitigation*: Workers are user-operated or vetted
   - *Future*: Worker registration requires approval + attestation

4. **Limited audit logging**: No centralized log aggregation
   - *Impact*: Difficult to detect attacks across components
   - *Future*: Structured logging + SIEM integration

5. **No rate limiting per user**: Rate limits global
   - *Impact*: One user can exhaust quota
   - *Future*: Per-user rate limits and quotas

### Roadmap

**Short term** (next 3 months):
- [ ] Artifact encryption at rest
- [ ] Enhanced audit logging
- [ ] Worker approval workflow
- [ ] Per-user rate limits

**Medium term** (6 months):
- [ ] Multi-tenant controller mode
- [ ] Role-based access control
- [ ] Build secrets management (encrypted env vars)
- [ ] Worker reputation system

**Long term** (12 months):
- [ ] Hardware security module (HSM) integration
- [ ] Confidential computing (encrypted VMs)
- [ ] Zero-knowledge architecture (controller never sees source)
- [ ] Blockchain-based audit trail

## Security Disclosure

**Found a security vulnerability?**

Please report it privately:
- Email: security@expo.dev
- Or: Create private security advisory on GitHub

**Do not**:
- Open public GitHub issue
- Disclose on social media
- Exploit in production

**We commit to**:
- Acknowledge within 48 hours
- Fix critical issues within 7 days
- Credit researchers (with permission)
- Transparent disclosure after fix

## Compliance & Standards

### Current Status

- ✅ OWASP Top 10 mitigations implemented
- ✅ CWE/SANS Top 25 considered
- ✅ Least privilege principle enforced
- ✅ Input validation throughout
- ⚠️ SOC 2 (not pursued yet, small team)
- ⚠️ ISO 27001 (not pursued yet)

### Security Testing

**Regular testing**:
- Path traversal attacks (automated tests)
- Input validation fuzzing
- Dependency vulnerability scanning (Dependabot)
- Code review for security issues

**Penetration testing**:
- Not yet performed (future: annual pentests)
- Community security reviews welcome

## Conclusion

Expo Free Agent prioritizes security through:
1. **Hardware-isolated VMs** (not containers)
2. **Defense in depth** (multiple protection layers)
3. **Least privilege** (minimal permissions)
4. **Apple code signing** (verified, notarized apps)
5. **Path traversal protection** (tested and validated)
6. **Audit logging** (transparency and accountability)

The architecture is designed to be secure by default, with additional hardening available for production deployments.

For operational security details, see:
- [Gatekeeper](../operations/gatekeeper.md) - Code signing and notarization
- [Release Process](../operations/release.md) - Secure build and distribution
- [Setup Remote](../getting-started/setup-remote.md) - Production deployment security

---

**Last Updated**: 2026-01-28
**Review Cycle**: Quarterly
