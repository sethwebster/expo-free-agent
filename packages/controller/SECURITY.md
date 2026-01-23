# Security Model - Central Controller

## Overview

The Central Controller implements a **"trust network"** security model designed for localhost-only prototype deployment. This is **NOT production-ready** and should only be used in trusted network environments.

## Current Security Measures (MVP)

### 1. API Key Authentication

All API endpoints require an `X-API-Key` header with a shared secret:

```bash
curl -H "X-API-Key: your-api-key" http://localhost:3000/api/builds/submit
```

**Configuration:**
- Set via environment variable: `CONTROLLER_API_KEY=your-secure-key-min-16-chars`
- Or CLI flag: `--api-key "your-secure-key-min-16-chars"`
- Minimum length: 16 characters
- Default (insecure): `dev-insecure-key-change-in-production`

**Limitations:**
- Single shared key for all workers
- No per-worker authentication
- No key rotation
- No rate limiting

### 2. Worker Access Control

Source code and signing certificates are protected by worker verification:

**Endpoints:**
- `GET /api/builds/:id/source` - Requires `X-Worker-Id` header
- `GET /api/builds/:id/certs` - Requires `X-Worker-Id` header

**Validation:**
- Worker must be assigned to the build OR build must be pending
- Prevents workers from accessing other workers' builds

### 3. Path Traversal Protection

File storage validates all paths to prevent directory traversal attacks:

```typescript
// Blocked
storage.createReadStream('/etc/passwd')
storage.createReadStream('../../sensitive.txt')

// Allowed
storage.createReadStream('/storage/builds/abc123.zip')
```

### 4. Upload Size Limits

Multer configured with size limits to prevent DoS:

- Source files: 500MB (large iOS apps)
- Certificate files: 10MB (certs are small)
- Build results: 1GB (built IPAs can be large)

### 5. Atomic Job Assignment

Database transactions prevent race conditions:

- Multiple workers polling simultaneously cannot claim same build
- Build status and worker assignment updated atomically

### 6. Queue Persistence

Queue state restored from database on startup:

- Pending builds re-queued
- Assigned builds recovered
- Orphaned builds (worker gone) reset to pending

## Known Security Gaps (Production TODO)

### Critical

1. **No HTTPS** - All traffic unencrypted (localhost-only assumption)
2. **Shared API Key** - Single key for all workers (no individual accountability)
3. **No Rate Limiting** - Brute force API key attacks possible
4. **No Input Sanitization** - File uploads not validated for zip magic bytes
5. **No Malware Scanning** - Uploaded files could contain malicious code

### High

6. **No Audit Logging** - Security events not logged
7. **No Key Rotation** - API key cannot be changed without restart
8. **No Worker Deregistration** - Workers cannot be revoked
9. **No Build Cancellation** - No way to stop malicious builds
10. **Console Logging** - Secrets may leak to logs

### Medium

11. **No Session Management** - Workers never expire
12. **No Storage Quotas** - Unlimited disk usage possible
13. **No Build Timeouts** - Builds can hang forever
14. **Unbounded Queries** - `getAllBuilds()` can exhaust memory

## Deployment Guidelines

### Localhost-Only (MVP)

```bash
# Run on localhost
expo-controller start --api-key "localhost-dev-key-12345"

# Workers connect to localhost
curl -H "X-API-Key: localhost-dev-key-12345" \
     http://localhost:3000/api/workers/register
```

**Requirements:**
- Only bind to `127.0.0.1` (not `0.0.0.0`)
- Firewall blocks external access to port 3000
- All workers run on same machine or trusted LAN

### Trusted Network (Extended)

If deploying beyond localhost:

1. **Use strong API key**: `openssl rand -hex 32`
2. **Firewall**: Only allow connections from worker IPs
3. **VPN**: Require VPN for all controller access
4. **Monitoring**: Log all API requests with timestamps

```bash
# Generate secure key
export CONTROLLER_API_KEY=$(openssl rand -hex 32)

# Run with strong key
expo-controller start --port 3000
```

### Production (Future)

**Do NOT use current implementation for production.**

Required changes:
- [ ] HTTPS with TLS 1.3
- [ ] Per-worker API keys stored in database
- [ ] OAuth2 or JWT-based authentication
- [ ] Rate limiting (e.g., 10 req/min per worker)
- [ ] Input validation and sanitization
- [ ] Malware scanning (ClamAV integration)
- [ ] Structured logging (JSON to Splunk/DataDog)
- [ ] Audit trail for all security events
- [ ] Key rotation mechanism
- [ ] Worker blacklist/revocation
- [ ] Build timeout enforcement
- [ ] Storage quotas and cleanup policies
- [ ] Query pagination (no unbounded `SELECT *`)
- [ ] Security headers (CSP, HSTS, etc.)

## Security Testing

### Path Traversal Tests

```bash
cd packages/controller
bun test src/services/__tests__/FileStorage.test.ts
```

### API Key Tests

```bash
# Should fail - no API key
curl http://localhost:3000/api/builds/status/abc123

# Should fail - wrong API key
curl -H "X-API-Key: wrong-key" http://localhost:3000/api/builds/status/abc123

# Should succeed
curl -H "X-API-Key: $CONTROLLER_API_KEY" http://localhost:3000/api/builds/status/abc123
```

### Worker Access Tests

```bash
# Should fail - no worker ID
curl -H "X-API-Key: $CONTROLLER_API_KEY" \
     http://localhost:3000/api/builds/abc123/source

# Should fail - wrong worker ID
curl -H "X-API-Key: $CONTROLLER_API_KEY" \
     -H "X-Worker-Id: wrong-worker" \
     http://localhost:3000/api/builds/abc123/source

# Should succeed - correct worker ID
curl -H "X-API-Key: $CONTROLLER_API_KEY" \
     -H "X-Worker-Id: worker-xyz" \
     http://localhost:3000/api/builds/abc123/source
```

## Incident Response

If security breach suspected:

1. **Immediately stop controller**: `kill <pid>`
2. **Rotate API key**: `export CONTROLLER_API_KEY=$(openssl rand -hex 32)`
3. **Review logs**: Check for suspicious requests
4. **Audit storage**: Scan uploaded files for malware
5. **Review builds**: Check for unauthorized builds
6. **Notify team**: Alert stakeholders

## Reporting Security Issues

**Do NOT file public GitHub issues for security vulnerabilities.**

Contact: [Security contact TBD]

Include:
- Description of vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if known)
