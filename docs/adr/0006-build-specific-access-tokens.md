# ADR-0006: Build-Specific Access Tokens for Multi-Tenant Isolation

**Status:** Accepted

**Date:** 2026-01-27 (Commit d7de840)

## Context

Original authentication model used single admin API key for all operations:
- CLI sent `X-API-Key: <shared-secret>` header
- All endpoints validated against same key
- No isolation between build submitters
- Anyone with API key could access any build

**Security problem:** If user A submits build #123, user B with the API key can:
- View build status
- Download build artifacts
- Read build logs
- Retry the build

This violates multi-tenant security: submitters should only access their own builds.

## Decision

Implement **dual-authentication model** with build-specific tokens:

### Authentication Hierarchy

1. **Admin API key** (`X-API-Key` header)
   - Full access to all builds and operations
   - Used by controller operators for debugging/monitoring
   - Env var: `CONTROLLER_API_KEY` (32+ chars required)

2. **Build access tokens** (`X-Build-Token` header)
   - Scoped to single build
   - Generated at submission time (crypto.randomBytes(32).toString('base64url'))
   - Returned only to submitter
   - Enables self-service without admin key

### Endpoint Protection

```typescript
// Before: All or nothing
app.get('/api/builds/:id', requireApiKey, handler)

// After: Admin OR build-specific access
app.get('/api/builds/:id', requireBuildAccess, handler)
```

`requireBuildAccess()` middleware:
1. Check for `X-API-Key` → if valid, allow (admin access)
2. Check for `X-Build-Token` → validate token matches build ID → allow (scoped access)
3. No valid auth → 401 Unauthorized

### CLI Token Storage

Tokens stored in `~/.expo-free-agent/build-tokens.json`:
```json
{
  "abc123": "pL8K9mN3qR5tV7wX2yZ4bD6fH8jL0nP",
  "def456": "aB1cD2eF3gH4iJ5kL6mN7oP8qR9sT0u"
}
```

File permissions: `0600` (owner read/write only)

Atomic writes: temp file + rename pattern prevents corruption.

## Consequences

### Positive

- **Build isolation:** Submitters cannot access each other's builds
- **Self-service:** Users can check status/download without admin key
- **Audit trail:** Build tokens log which build was accessed
- **No state on server:** Tokens validated against database (stateless)
- **Backwards compatible:** Admin key continues working for all operations
- **Secure storage:** 0600 permissions protect tokens on CLI machine

### Negative

- **Unbounded growth:** Token file grows indefinitely (no cleanup after download)
- **No expiration:** Tokens valid forever (until build deleted)
- **No revocation:** Cannot invalidate token without deleting build
- **Single machine:** Token file not synced across machines
- **Cleartext storage:** Tokens stored as plaintext in JSON file
- **Database migration required:** Added `access_token` column to `builds` table

### Security Analysis

**Threat: Token theft from CLI machine**
- Mitigated by: File permissions (0600)
- Residual risk: Root access or malware can read file
- Acceptable for prototype (production should use keychain)

**Threat: Token interception over network**
- Mitigated by: HTTPS in production
- Residual risk: HTTP in local dev exposes tokens
- Acceptable for localhost-only deployment

**Threat: Token enumeration**
- Prevented by: 256-bit random tokens (2^256 keyspace)
- Attack infeasible (would take longer than age of universe)

**Threat: Admin key compromise**
- Consequence: Full system access
- Mitigation: 32-char minimum, env var only (never CLI arg)
- Acceptable for prototype (production should use proper auth service)

## Protected Endpoints

Endpoints requiring build access:
- `GET /api/builds/:id` - Status check
- `GET /api/builds/:id/logs` - Log retrieval
- `GET /api/builds/:id/download` - Artifact download
- `POST /api/builds/:id/retry` - Retry build

Endpoints still requiring admin key:
- `GET /api/builds` - List all builds
- `POST /api/builds` - Submit new build (generates token)
- `DELETE /api/builds/:id` - Delete build

Worker endpoints use separate auth (`X-Worker-Id` header).

## Future Improvements

1. **Token expiration:** Set TTL (e.g., 7 days or after download)
2. **Revocation API:** `POST /api/builds/:id/revoke-token`
3. **Token rotation:** Generate new token on each download
4. **Keychain storage:** Use OS keychain instead of JSON file
5. **Per-operation tokens:** Separate read/download/retry tokens
6. **Rate limiting:** Prevent token brute force (though infeasible)

## References

- Middleware implementation: `packages/controller/src/middleware/auth.ts`
- CLI token storage: `cli/src/build-tokens.ts`
- Database schema: `packages/controller/src/db/schema.sql` (`access_token` column)
- Security documentation: `docs/architecture/security.md`
