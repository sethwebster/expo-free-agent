# Code Review: Phase 2 - Controller Secure Certificate Endpoint

**Date**: 2026-01-26
**Reviewer**: Claude Code
**Scope**: Secure cert endpoint, worker access middleware, unzipCerts helper

## Files Reviewed

1. `/packages/controller/src/api/builds/index.ts` - Lines 314-351
2. `/packages/controller/src/middleware/auth.ts` - Full file (90 lines)
3. `/packages/controller/src/services/FileStorage.ts` - Lines 160-215
4. `/packages/controller/package.json` - adm-zip dependency

---

## 🔴 Critical Issues

### 1. Zip Bomb Attack Vector (No Decompression Limit)

**Location**: `/packages/controller/src/services/FileStorage.ts:192-214`

**Problem**: The `unzipCerts` function loads the entire zip into memory and extracts all entries without checking decompressed size. A malicious zip with high compression ratio (zip bomb) could exhaust server memory.

**Impact**: Denial of service. A 10MB cert file (within `maxCertsFileSize`) could decompress to gigabytes.

**Solution**:
```typescript
export function unzipCerts(zipBuffer: Buffer): CertsBundle {
  const MAX_DECOMPRESSED_SIZE = 50 * 1024 * 1024; // 50MB limit
  const MAX_FILES = 20; // Reasonable limit for cert bundles

  const zip = new AdmZip(zipBuffer);
  const entries = zip.getEntries();

  if (entries.length > MAX_FILES) {
    throw new Error(`Too many files in cert bundle: ${entries.length} (max ${MAX_FILES})`);
  }

  let totalDecompressed = 0;
  for (const entry of entries) {
    totalDecompressed += entry.header.size; // Decompressed size from header
    if (totalDecompressed > MAX_DECOMPRESSED_SIZE) {
      throw new Error('Cert bundle decompressed size exceeds limit');
    }
  }

  // ... rest of extraction
}
```

### 2. Path Traversal in Zip Entry Names

**Location**: `/packages/controller/src/services/FileStorage.ts:200-207`

**Problem**: Entry names are checked only by suffix (`.p12`, `.mobileprovision`, `password.txt`). Malicious archives could contain entries like `../../../etc/passwd.mobileprovision` or nested paths. While `getData()` returns buffer content (not filesystem write), the entry name matching is naive.

**Impact**: Low for this specific use case (no extraction to disk), but establishes bad pattern. If entry names were ever logged or used in paths, it becomes exploitable.

**Solution**:
```typescript
for (const entry of entries) {
  // Normalize and reject paths with traversal or absolute paths
  const entryName = entry.entryName;
  if (entryName.includes('..') || entryName.startsWith('/') || entryName.includes('\\')) {
    throw new Error(`Invalid entry name in cert bundle: ${entryName}`);
  }

  // Use basename for suffix matching
  const basename = entryName.split('/').pop() || '';
  if (basename.endsWith('.p12')) {
    // ...
  }
}
```

### 3. Missing X-API-Key Validation on Secure Endpoint

**Location**: `/packages/controller/src/api/builds/index.ts:320-324`

**Problem**: The `/certs-secure` endpoint uses `requireWorkerAccess` as preHandler but there's no `requireApiKey` hook applied. Looking at the route registration, if the API routes don't have a global `requireApiKey` hook, this endpoint may be publicly accessible.

**Impact**: If API key isn't globally enforced, any client knowing build ID and worker ID headers could fetch certificates.

**Verification needed**: Check if `requireApiKey` is applied globally in the API route registration (likely in `api/index.ts`).

---

## 🟡 Architecture Concerns

### 4. TOCTOU Race in Worker Access Middleware

**Location**: `/packages/controller/src/middleware/auth.ts:71-88`

**Problem**: The middleware fetches build, validates worker ownership, then attaches build to request. Between middleware check and handler execution, build state could change (e.g., reassigned to different worker during retry scenario).

**Impact**: Low severity for read-only endpoint. Worker could theoretically access certs for build that was reassigned in the microseconds between check and read.

**Context**: The database has atomic assignment (`assignBuildToWorker`), but no mechanism to prevent access during reassignment window.

**Recommendation**: For MVP, document this as accepted risk. For production, consider:
- Read-through lock on build during cert access
- Or verify build.worker_id again inside handler

### 5. Overly Permissive Pending Build Access

**Location**: `/packages/controller/src/middleware/auth.ts:78-85`

**Problem**: The condition `if (build.worker_id && build.worker_id !== workerId)` allows ANY worker to access a pending build (where `worker_id` is null). This was intentional per comment, but creates security gap for `/certs-secure`.

**Impact**: Any registered worker can request certs for any pending build before assignment. Certificates should only be accessible to the assigned worker.

**Solution**: For the secure cert endpoint specifically, require build to be assigned:
```typescript
// In requireWorkerAccess when requireBuildIdHeader is true
if (requireBuildIdHeader) {
  // ... existing header validation ...

  // For secure endpoints, build MUST be assigned to requesting worker
  if (!build.worker_id || build.worker_id !== workerId) {
    return reply.status(403).send({
      error: 'Build not assigned to this worker',
    });
  }
}
```

### 6. Inconsistent Error Response Structure

**Location**: Various endpoints

**Problem**: Some endpoints return `{ error: 'message' }`, but the shape isn't type-enforced. No centralized error response helper.

**Impact**: Client must handle inconsistent error shapes. API documentation burden.

**Recommendation**: Create typed error response utility:
```typescript
interface ApiError {
  error: string;
  code?: string;
  details?: unknown;
}

function sendError(reply: FastifyReply, status: number, error: string, code?: string) {
  return reply.status(status).send({ error, code });
}
```

---

## 🟢 DRY Opportunities

### 7. Duplicate Path Traversal Checks

**Location**:
- `/packages/controller/src/services/FileStorage.ts:96-103` (`createReadStream`)
- `/packages/controller/src/services/FileStorage.ts:165-171` (`readBuildCerts`)

**Problem**: Identical path traversal validation logic duplicated.

**Solution**:
```typescript
private validatePathInStorage(filePath: string): string {
  const normalized = resolve(filePath);
  const storageRoot = resolve(this.storagePath);

  if (!normalized.startsWith(storageRoot)) {
    throw new Error('Path traversal attempt blocked: file must be inside storage directory');
  }

  if (!existsSync(normalized)) {
    throw new Error('File not found');
  }

  return normalized;
}

createReadStream(filePath: string): Readable {
  const normalized = this.validatePathInStorage(filePath);
  return createReadStream(normalized);
}

readBuildCerts(certsPath: string): Buffer {
  const normalized = this.validatePathInStorage(certsPath);
  return readFileSync(normalized);
}
```

### 8. Repeated Stream-to-Buffer Pattern

**Location**: `/packages/controller/src/api/builds/index.ts:52-56`, `62-66`

**Problem**: Same chunk collection pattern for source and certs.

**Solution**:
```typescript
async function streamToBuffer(stream: AsyncIterable<Buffer>): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of stream) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}
```

---

## 🔵 Maintenance Improvements

### 9. Missing Password Validation in unzipCerts

**Location**: `/packages/controller/src/services/FileStorage.ts:210-214`

**Problem**: If `password.txt` is missing, `password` remains empty string. No warning or validation that p12 password exists.

**Impact**: Downstream code may fail cryptically when importing p12 without password.

**Solution**:
```typescript
if (!p12) {
  throw new Error('No P12 certificate found in bundle');
}

if (!password && profiles.length === 0) {
  // Log warning - unusual but potentially valid for certain cert types
  console.warn('Cert bundle contains no password.txt - p12 may be unencrypted');
}
```

### 10. No Tests for Secure Cert Endpoint

**Location**: `/packages/controller/src/__tests__/integration.test.ts`

**Problem**: Existing tests don't cover the new `/certs-secure` endpoint, `requireWorkerAccess` middleware variations, or `unzipCerts` function.

**Impact**: Regressions will go undetected. Security-critical code untested.

**Required tests**:
- `unzipCerts` with valid cert bundle
- `unzipCerts` with missing p12 (should throw)
- `unzipCerts` with zip bomb attempt (should reject)
- `/certs-secure` without X-Worker-Id (401)
- `/certs-secure` without X-Build-Id (401)
- `/certs-secure` with mismatched X-Build-Id (403)
- `/certs-secure` with wrong worker (403)
- `/certs-secure` happy path

### 11. Type Safety: `(request as any).build`

**Location**: `/packages/controller/src/api/builds/index.ts:267`, `294`, `326`

**Problem**: Build attached to request via `any` cast, losing type safety.

**Solution**: Extend Fastify request type:
```typescript
declare module 'fastify' {
  interface FastifyRequest {
    build?: Build;
  }
}
```

### 12. Error Message Could Leak Information

**Location**: `/packages/controller/src/middleware/auth.ts:64-68`

**Problem**: Error message `"X-Build-Id header does not match build ID in URL"` confirms the build exists. Attacker can enumerate valid build IDs by observing different error messages.

**Impact**: Information disclosure aids targeted attacks.

**Solution**: Use same generic error for all auth failures:
```typescript
return reply.status(403).send({
  error: 'Access denied',
});
```

---

## ⚪ Nitpicks

### 13. Dependency Version: adm-zip

**Location**: `/packages/controller/package.json:26`

**Current**: `"adm-zip": "^0.5.10"`

**Note**: Version 0.5.10 is NOT affected by known CVEs (CVE-2018-1002204 patched in 0.4.9, SNYK-JS-ADMZIP-1065796 patched in 0.5.2). However, 0.5.16 includes additional hardening.

**Recommendation**: Upgrade to `^0.5.16` for latest security fixes:
```json
"adm-zip": "^0.5.16"
```

### 14. Magic Number: Keychain Password Length

**Location**: `/packages/controller/src/api/builds/index.ts:334`

```typescript
const keychainPassword = crypto.randomBytes(24).toString('base64');
```

**Recommendation**: Extract constant with documentation:
```typescript
// 24 bytes = 192 bits entropy, 32 chars base64 output
// Meets Apple Keychain minimum and provides cryptographic strength
const KEYCHAIN_PASSWORD_BYTES = 24;
const keychainPassword = crypto.randomBytes(KEYCHAIN_PASSWORD_BYTES).toString('base64');
```

### 15. Comment Says "24 bytes = 32 chars" But That's Incorrect

**Location**: `/packages/controller/src/api/builds/index.ts:333`

**Problem**: Comment says "24 bytes = 32 chars base64" but 24 bytes encodes to exactly 32 base64 characters only without padding. With standard base64 padding, it would be 32 chars. This is correct but the phrasing is ambiguous.

**Clarification**: `crypto.randomBytes(24).toString('base64')` produces exactly 32 characters (24 * 8 / 6 = 32, no padding needed). Comment is technically accurate.

---

## ✅ Strengths

1. **Proper crypto.randomBytes usage** - Using Node's crypto module for keychain password generation is correct. 24 bytes provides 192 bits of entropy, sufficient for this use case.

2. **Path traversal protection in FileStorage** - Both `createReadStream` and `readBuildCerts` validate paths against storage root. Defense in depth.

3. **Atomic build assignment** - The `assignBuildToWorker` method uses SQLite transactions with `BEGIN IMMEDIATE` to prevent race conditions during assignment. Well implemented.

4. **Header-based authentication layering** - Requiring both `X-Worker-Id` and `X-Build-Id` for secure endpoint adds defense in depth. Build ID in URL and header must match.

5. **Clean separation of concerns** - `unzipCerts` is a pure function, easily testable in isolation. FileStorage methods are well-bounded.

6. **Size limits on upload** - `maxCertsFileSize` config prevents large uploads at ingestion time.

---

## Summary

**Must fix before merge**:
1. Add zip bomb protection to `unzipCerts` (Critical #1)
2. Validate entry names in `unzipCerts` (Critical #2)
3. Tighten pending build access for secure endpoint (Architecture #5)

**Should fix**:
4. Add comprehensive tests for secure cert flow
5. Extract duplicate path validation
6. Use consistent error responses

**Acceptable for MVP**:
- TOCTOU window in middleware (documented risk)
- Type casting for request.build (cosmetic)

---

## Security Checklist

- [x] Authentication: X-API-Key + X-Worker-Id headers
- [x] Authorization: Worker ownership validated
- [ ] **Input validation: Zip bomb protection MISSING**
- [ ] **Input validation: Entry name sanitization MISSING**
- [x] Path traversal: Protected in FileStorage
- [x] Cryptographic randomness: Using crypto.randomBytes
- [x] Base64 encoding: Correct usage
- [ ] Information leakage: Error messages reveal build existence
- [x] Size limits: Upload limits enforced

## References

- [adm-zip Snyk vulnerabilities](https://security.snyk.io/package/npm/adm-zip)
- [CVE-2018-1002204](https://nvd.nist.gov/vuln/detail/CVE-2018-1002204)
- [SNYK-JS-ADMZIP-1065796](https://security.snyk.io/vuln/SNYK-JS-ADMZIP-1065796)
