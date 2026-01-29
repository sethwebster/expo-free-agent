# ADR-0010: Automatic Worker Token Rotation with Short TTL

**Status:** Accepted

**Date:** 2026-01-29 (Commits in Elixir migration)

## Context

Original worker authentication used static worker IDs:
- Workers register once, receive permanent ID
- ID used for all subsequent API calls
- No credential expiration
- Compromised worker ID grants permanent access

**Security problems:**
1. **Credential theft:** Stolen worker ID valid forever
2. **No revocation:** Cannot invalidate compromised credentials without database manipulation
3. **Lateral movement:** Attacker with one worker ID can impersonate worker indefinitely
4. **Audit gap:** Cannot determine when credential was actually used (vs stolen and replayed)

**Operational problem:**
- Decommissioned workers not automatically cleaned up (ID remains valid)
- No way to enforce "workers must check in regularly"

## Decision

Implement **automatic token rotation** with 90-second TTL:

### Flow

1. **Registration:**
   - Worker sends `POST /api/workers/register` (no auth)
   - Controller generates: `worker_id` (UUID) + `access_token` (32 random bytes)
   - Sets `access_token_expires_at = NOW() + 90 seconds`
   - Returns both to worker

2. **Polling (every 30 seconds):**
   - Worker sends `GET /api/workers/poll` with `X-Worker-Id` and `X-Access-Token` headers
   - Controller validates token + expiration
   - Generates **new token** with fresh 90s TTL
   - Returns new token in response: `{ token: "new-token", ... }`
   - Worker stores new token, uses for next poll

3. **Expiration:**
   - If worker doesn't poll within 90s, token expires
   - Next poll request with expired token → 401 Unauthorized
   - Worker automatically re-registers (transparent to operator)

### Database Schema

```sql
CREATE TABLE workers (
  id UUID PRIMARY KEY,
  access_token VARCHAR(64) NOT NULL,
  access_token_expires_at TIMESTAMP NOT NULL,
  last_seen_at TIMESTAMP NOT NULL,
  ...
)
CREATE INDEX idx_workers_access_token ON workers(access_token);
CREATE INDEX idx_workers_expires_at ON workers(access_token_expires_at);
```

### Worker Implementation

```swift
class WorkerService {
  var accessToken: String?

  func poll() async throws -> Job? {
    do {
      let response = try await api.poll(token: accessToken)
      self.accessToken = response.newToken  // Rotate
      return response.job
    } catch AuthError.unauthorized {
      try await reRegister()
      return try await poll()  // Retry with new credentials
    }
  }
}
```

## Consequences

### Positive

#### Security
- **Limited blast radius:** Stolen token valid for max 90 seconds
- **Forward secrecy:** Old tokens cannot be reused after rotation
- **Automatic cleanup:** Inactive workers auto-expire (no manual revocation needed)
- **Audit trail:** `last_seen_at` timestamp shows worker activity
- **No long-term secrets:** Workers don't store permanent credentials

#### Operations
- **Self-healing:** Workers transparently re-register on token expiration
- **Zero configuration:** Token rotation automatic, no operator intervention
- **Stale detection:** Workers not polling for 90s are truly offline
- **Cleanup:** Expired workers easily identified (`access_token_expires_at < NOW()`)

#### Compliance
- **Principle of least privilege:** Credentials expire quickly
- **Credential rotation:** Satisfies security policy requirements
- **Non-repudiation:** Timestamps prove worker was active when action taken

### Negative

#### Network Dependency
- **Must poll every 90s:** Workers >90s offline lose access
- **Re-registration overhead:** Network interruption triggers full re-registration (~1s)
- **Failure cascade:** Controller outage >90s expires all worker tokens

#### Database Load
- **Write amplification:** Every poll updates `access_token` + `access_token_expires_at` + `last_seen_at`
- **Index overhead:** Token expiration query requires index on `access_token_expires_at`
- **100 workers polling every 30s:** 200 writes/min (acceptable, but non-zero)

#### Implementation Complexity
- **State management:** Workers must store and rotate tokens
- **Error handling:** Must distinguish token expiration from other auth errors
- **Testing:** Must mock time for expiration tests

### Safety Margins

**Poll interval:** 30 seconds default
**Token TTL:** 90 seconds
**Safety margin:** 60 seconds (2 missed polls before expiration)

**Rationale:** Allows 2 missed polls (network blip, system suspend) before expiration triggers re-registration.

## Security Analysis

### Threat: Token Theft During Transit

**Attack:** Intercept network traffic to steal token during poll.

**Mitigations:**
- HTTPS required in production (TLS encryption)
- Token only valid for 90s (limits damage)
- Next rotation invalidates stolen token

**Residual risk:** MITM during unencrypted HTTP (localhost dev only).

### Threat: Token Theft from Worker Memory

**Attack:** Memory dump of running worker process reveals current token.

**Mitigations:**
- Token rotates every 30s (short window for exploitation)
- Worker process runs with standard user permissions (not root)
- macOS code signing prevents tampering

**Residual risk:** Root access or debugger attachment can read memory (acceptable for on-premises workers).

### Threat: Token Replay After Theft

**Attack:** Attacker steals token, replays poll requests to impersonate worker.

**Mitigations:**
- Legitimate worker gets new token on next poll, invalidates attacker's token
- Controller sees two workers with same ID, logs anomaly
- `last_seen_at` timestamp shows unusual activity pattern

**Residual risk:** Attacker can impersonate for max 90s, then loses access.

### Threat: Database Compromise

**Attack:** Attacker gains read access to PostgreSQL, steals all tokens.

**Mitigations:**
- All tokens expire within 90s (not long-term exposure)
- Can force mass re-registration by resetting all `access_token_expires_at` to past

**Residual risk:** Active attacker can continuously steal fresh tokens (requires database encryption at rest).

## Configuration

**TTL tuning:**
```elixir
# config/config.exs
config :expo_controller,
  worker_token_ttl_seconds: 90  # Default, can be overridden
```

**Poll interval (worker-side):**
```swift
// WorkerConfiguration.swift
let pollIntervalSeconds = 30  // Must be < token TTL
```

**Recommended values:**
- Development: TTL=300s (5min), Poll=60s (more lenient)
- Production: TTL=90s, Poll=30s (default)
- High-security: TTL=60s, Poll=20s (tighter rotation)

**DO NOT** set TTL < Poll interval (workers would constantly re-register).

## Performance Impact

**Database writes per worker:**
- Poll every 30s = 2 polls/min
- Each poll updates 3 columns = 2 writes/min/worker

**100 workers:**
- 200 writes/min = 3.3 writes/sec
- Negligible load for PostgreSQL

**Token validation query:**
```sql
-- Executed on every worker API request
SELECT * FROM workers
WHERE access_token = $1
  AND access_token_expires_at > NOW()
LIMIT 1
```

**Index:** `idx_workers_access_token` ensures O(log n) lookup.

## Alternatives Considered

### Static Worker IDs (Original Approach)

**Pros:**
- Simple implementation
- Zero database writes for auth
- No expiration handling

**Cons:**
- Permanent credentials (security risk)
- No automatic cleanup
- Cannot revoke without database manipulation

**Rejected:** Security risk outweighs implementation simplicity.

### JWT with Long Expiration

**Approach:** Issue JWT tokens with 24-hour expiration.

**Pros:**
- Stateless validation (no database lookup)
- Industry standard
- Expiration built-in

**Cons:**
- Cannot revoke before expiration
- 24 hours too long for compromised credential
- Requires secret key management
- Token size larger (JSON payload)

**Rejected:** Cannot invalidate compromised token until expiration.

### API Keys with Manual Rotation

**Approach:** Workers configured with long-lived API keys, operator rotates manually.

**Pros:**
- Familiar pattern
- No automatic expiration

**Cons:**
- Operator burden (manual rotation)
- Rotation requires worker restart
- No automatic cleanup
- Compromised key valid until rotation

**Rejected:** Automation better than manual operations.

### Certificate-Based Authentication

**Approach:** Workers use client TLS certificates for mutual TLS.

**Pros:**
- Industry standard for machine authentication
- Cryptographically strong
- Revocation via CRL/OCSP

**Cons:**
- Certificate management complexity (CA, expiration, renewal)
- Reverse proxy configuration required
- Worker code needs TLS client cert support
- Overkill for prototype

**Rejected:** Complexity outweighs benefits for current scale.

## Future Enhancements

1. **Token families:** Track token generation chain for anomaly detection
2. **Geolocation validation:** Reject polls from unexpected IP ranges
3. **Rate limiting:** Prevent brute force token guessing (already infeasible with 256-bit tokens)
4. **Audit logging:** Log all token rotations for forensics
5. **Graceful shutdown:** Workers send explicit deregister to invalidate token immediately

## References

- Worker registration: `packages/controller_elixir/lib/expo_controller/workers.ex`
- Token rotation middleware: `packages/controller_elixir/lib/expo_controller_web/plugs/auth.ex`
- Worker implementation: `free-agent/Sources/WorkerCore/WorkerService.swift`
- Migration: `packages/controller_elixir/priv/repo/migrations/*_add_access_token_to_workers.exs`
