# API Error Reference

Comprehensive guide to error responses, status codes, and troubleshooting.

---

## Table of Contents

- [Error Response Format](#error-response-format)
- [HTTP Status Codes](#http-status-codes)
- [Authentication Errors (401, 403)](#authentication-errors-401-403)
- [Client Errors (400, 404, 413, 422)](#client-errors-400-404-413-422)
- [Server Errors (500)](#server-errors-500)
- [Build-Specific Errors](#build-specific-errors)
- [Worker-Specific Errors](#worker-specific-errors)
- [Troubleshooting Guide](#troubleshooting-guide)

---

## Error Response Format

All API errors return JSON with this structure:

```json
{
  "error": "Human-readable error message"
}
```

For errors requiring additional context:

```json
{
  "error": "Primary error message",
  "reason": "Technical details or additional context"
}
```

For validation errors:

```json
{
  "error": "Registration failed",
  "details": {
    "name": ["can't be blank"],
    "capabilities": ["is invalid"]
  }
}
```

---

## HTTP Status Codes

| Code | Category | Description |
|------|----------|-------------|
| `200 OK` | Success | Request completed successfully |
| `201 Created` | Success | Resource created (build submitted, worker registered) |
| `400 Bad Request` | Client Error | Invalid input, missing required fields |
| `401 Unauthorized` | Auth Error | Missing authentication credentials |
| `403 Forbidden` | Auth Error | Invalid or insufficient credentials |
| `404 Not Found` | Client Error | Resource not found (build, worker, file) |
| `413 Payload Too Large` | Client Error | Uploaded file exceeds size limit |
| `422 Unprocessable Entity` | Client Error | Validation failed |
| `500 Internal Server Error` | Server Error | Unexpected server failure |

---

## Authentication Errors (401, 403)

### 401 Unauthorized - Missing X-API-Key

**Occurs when:** No `X-API-Key` header provided for admin endpoint

```json
HTTP/1.1 401 Unauthorized
{
  "error": "Missing X-API-Key header"
}
```

**How to fix:**
```bash
# Add X-API-Key header
curl -H "X-API-Key: your-api-key" \
  http://localhost:4000/api/builds
```

**Related:** [API.md - Authentication](./API.md#authentication)

---

### 401 Unauthorized - Missing X-Build-Token

**Occurs when:** No authentication provided for build-specific endpoint

```json
HTTP/1.1 401 Unauthorized
{
  "error": "Missing X-API-Key or X-Build-Token header"
}
```

**How to fix:**
```bash
# Use build token from submit response
curl -H "X-Build-Token: xEj8kP3nR5mT..." \
  http://localhost:4000/api/builds/V1bN8xK9rLmQ/status
```

**Related:** [API.md - Build Token Authentication](./API.md#2-build-token-build-owner-access)

---

### 401 Unauthorized - Missing X-Worker-Id

**Occurs when:** Worker endpoint called without worker authentication

```json
HTTP/1.1 401 Unauthorized
{
  "error": "Missing X-Worker-Id header"
}
```

**How to fix:**
```bash
# Add X-Worker-Id header
curl -H "X-Worker-Id: worker-abc" \
  http://localhost:4000/api/builds/V1bN8xK9rLmQ/source
```

**Related:** [API.md - Worker ID Authentication](./API.md#3-worker-id-worker-access)

---

### 401 Unauthorized - Missing X-Build-Id

**Occurs when:** Secure cert endpoint called without build ID header

```json
HTTP/1.1 401 Unauthorized
{
  "error": "Missing X-Build-Id header"
}
```

**How to fix:**
```bash
# Add both X-Worker-Id and X-Build-Id headers
curl -H "X-Worker-Id: worker-abc" \
     -H "X-Build-Id: V1bN8xK9rLmQ" \
  http://localhost:4000/api/builds/V1bN8xK9rLmQ/certs-secure
```

**Security Note:** `X-Build-Id` prevents URL tampering. Must match build ID in URL path.

**Related:** [API.md - GET /api/builds/:id/certs-secure](./API.md#get-apibuildsidcerts-secure)

---

### 403 Forbidden - Invalid API Key

**Occurs when:** Wrong API key provided

```json
HTTP/1.1 403 Forbidden
{
  "error": "Invalid API key"
}
```

**How to fix:**
- Verify API key matches controller configuration
- Check for typos or extra whitespace
- Ensure API key environment variable is set correctly

```bash
# Check your API key
echo $CONTROLLER_API_KEY

# Test with correct key
curl -H "X-API-Key: correct-api-key" \
  http://localhost:4000/api/builds
```

**Related:** [SETUP_LOCAL.md - API Key Configuration](../../docs/getting-started/setup-local.md)

---

### 403 Forbidden - Invalid or Expired Build Token

**Occurs when:** Build token doesn't match build or has been invalidated

```json
HTTP/1.1 403 Forbidden
{
  "error": "Invalid or expired build token"
}
```

**How to fix:**
- Verify you're using the token from the submit response
- Check that build ID in URL matches token
- Build tokens don't expire, but verify you copied the full token

```bash
# Verify build ID and token match
BUILD_ID="V1bN8xK9rLmQ"
TOKEN="xEj8kP3nR5mT..."

curl -H "X-Build-Token: $TOKEN" \
  "http://localhost:4000/api/builds/$BUILD_ID/status"
```

---

### 403 Forbidden - Worker Not Assigned to Build

**Occurs when:** Worker tries to access build not assigned to them

```json
HTTP/1.1 403 Forbidden
{
  "error": "Worker not assigned to this build"
}
```

**How to fix:**
- Verify worker ID matches the worker that polled and received this job
- Check that build wasn't reassigned to another worker
- Ensure you're using the correct worker ID from registration

```bash
# Only access builds assigned to you via poll
RESPONSE=$(curl -H "X-API-Key: dev-key-12345" \
  "http://localhost:4000/api/workers/poll?worker_id=$WORKER_ID")

BUILD_ID=$(echo "$RESPONSE" | jq -r '.job.id')

# Then use that build ID
curl -H "X-Worker-Id: $WORKER_ID" \
  "http://localhost:4000/api/builds/$BUILD_ID/source"
```

---

### 403 Forbidden - Worker Not Authorized for Build

**Occurs when:** Worker tries to operate on another worker's build

```json
HTTP/1.1 403 Forbidden
{
  "error": "Worker not authorized for this build"
}
```

**How to fix:**
- Only upload results for builds assigned to your worker
- Don't hardcode build IDs - use IDs from poll response
- If worker crashed and restarted, build may have been reassigned

---

### 403 Forbidden - Build Not Assigned to This Worker

**Occurs when:** Heartbeat sent for build worker doesn't own

```json
HTTP/1.1 403 Forbidden
{
  "error": "Build not assigned to this worker"
}
```

**How to fix:**
```bash
# Ensure worker_id query param matches assigned worker
curl -X POST \
  "http://localhost:4000/api/builds/$BUILD_ID/heartbeat?worker_id=$CORRECT_WORKER_ID" \
  -H "Content-Type: application/json" \
  -d '{}'
```

---

### 403 Forbidden - X-Build-Id Does Not Match URL

**Occurs when:** `X-Build-Id` header doesn't match build ID in URL path

```json
HTTP/1.1 403 Forbidden
{
  "error": "X-Build-Id header does not match build ID in URL"
}
```

**How to fix:**
```bash
# Ensure X-Build-Id header matches URL path
BUILD_ID="V1bN8xK9rLmQ"

curl -H "X-Worker-Id: worker-abc" \
     -H "X-Build-Id: $BUILD_ID" \
  "http://localhost:4000/api/builds/$BUILD_ID/certs-secure"
```

**Security Note:** This prevents workers from accessing other builds' certificates via URL manipulation.

---

## Client Errors (400, 404, 413, 422)

### 400 Bad Request - Content Must Be Multipart

**Occurs when:** File upload endpoint called without multipart content type

```json
HTTP/1.1 400 Bad Request
{
  "error": "Content must be multipart/form-data"
}
```

**How to fix:**
```bash
# Use -F flag for multipart uploads, not -d
curl -X POST http://localhost:4000/api/builds/submit \
  -H "X-API-Key: dev-key-12345" \
  -F "platform=ios" \
  -F "source=@app.tar.gz"
```

**Related:** [API.md - POST /api/builds/submit](./API.md#post-apibuildssubmit)

---

### 400 Bad Request - Source File Required

**Occurs when:** Build submitted without source file

```json
HTTP/1.1 400 Bad Request
{
  "error": "Source file required"
}
```

**How to fix:**
```bash
# Include source file in upload
curl -X POST http://localhost:4000/api/builds/submit \
  -H "X-API-Key: dev-key-12345" \
  -F "platform=ios" \
  -F "source=@app.tar.gz"  # Required
```

---

### 400 Bad Request - Valid Platform Required

**Occurs when:** Platform field missing or invalid

```json
HTTP/1.1 400 Bad Request
{
  "error": "Valid platform required (ios|android)"
}
```

**How to fix:**
```bash
# Platform must be exactly "ios" or "android"
curl -X POST http://localhost:4000/api/builds/submit \
  -H "X-API-Key: dev-key-12345" \
  -F "platform=ios" \  # Not "iOS" or "IOS"
  -F "source=@app.tar.gz"
```

---

### 400 Bad Request - Invalid Platform

**Occurs when:** Platform value not recognized (Elixir-specific)

```json
HTTP/1.1 400 Bad Request
{
  "error": "Invalid platform. Must be 'ios' or 'android'"
}
```

**How to fix:**
- Use lowercase: `ios` or `android`
- No quotes in form data
- Check for typos

---

### 400 Bad Request - Missing Source File

**Occurs when:** No file attached to `source` field (Elixir-specific)

```json
HTTP/1.1 400 Bad Request
{
  "error": "Missing source file"
}
```

**How to fix:**
```bash
# Ensure file exists and path is correct
ls -lh app.tar.gz  # Verify file exists

curl -X POST http://localhost:4000/api/builds/submit \
  -H "X-API-Key: dev-key-12345" \
  -F "platform=ios" \
  -F "source=@app.tar.gz"  # @ prefix required for file upload
```

---

### 400 Bad Request - Build Not Completed

**Occurs when:** Attempting to download result before build finishes

```json
HTTP/1.1 400 Bad Request
{
  "error": "Build not completed"
}
```

**How to fix:**
- Poll `/api/builds/:id/status` until `status == "completed"`
- Don't attempt download if status is `pending`, `assigned`, `building`, or `failed`

```bash
# Check status first
STATUS=$(curl -s -H "X-Build-Token: $TOKEN" \
  "http://localhost:4000/api/builds/$BUILD_ID/status" \
  | jq -r '.status')

if [ "$STATUS" == "completed" ]; then
  curl -H "X-Build-Token: $TOKEN" \
    "http://localhost:4000/api/builds/$BUILD_ID/download" \
    -o app.ipa
else
  echo "Build not ready: $STATUS"
fi
```

---

### 400 Bad Request - Build Already Finished

**Occurs when:** Attempting to cancel completed or failed build

```json
HTTP/1.1 400 Bad Request
{
  "error": "Build already finished"
}
```

**How to fix:**
- Only cancel builds with status `pending`, `assigned`, or `building`
- Check status before cancelling

```bash
curl -H "X-API-Key: dev-key-12345" \
  "http://localhost:4000/api/builds/$BUILD_ID/status"
```

---

### 400 Bad Request - Original Build Source No Longer Available

**Occurs when:** Retry attempted but source files were deleted

```json
HTTP/1.1 400 Bad Request
{
  "error": "Original build source no longer available. Please submit a new build."
}
```

**How to fix:**
- Submit new build with fresh source instead of retrying
- Source files may be purged after retention period
- Worker storage may have been cleared

```bash
# Submit fresh build instead
curl -X POST http://localhost:4000/api/builds/submit \
  -H "X-API-Key: dev-key-12345" \
  -F "platform=ios" \
  -F "source=@app.tar.gz" \
  -F "certs=@certs.zip"
```

---

### 400 Bad Request - Worker ID Required

**Occurs when:** Heartbeat endpoint called without `worker_id` query param

```json
HTTP/1.1 400 Bad Request
{
  "error": "worker_id required"
}
```

**How to fix:**
```bash
# Include worker_id in query string
curl -X POST \
  "http://localhost:4000/api/builds/$BUILD_ID/heartbeat?worker_id=$WORKER_ID" \
  -H "Content-Type: application/json" \
  -d '{}'
```

---

### 400 Bad Request - Invalid Log Level

**Occurs when:** Log level not `info`, `warn`, or `error`

```json
HTTP/1.1 400 Bad Request
{
  "error": "Invalid log level. Must be: info, warn, or error"
}
```

**How to fix:**
```bash
# Use valid log level
curl -X POST http://localhost:4000/api/builds/$BUILD_ID/logs \
  -H "X-Worker-Id: $WORKER_ID" \
  -H "Content-Type: application/json" \
  -d '{"level": "info", "message": "Build started"}'
```

---

### 400 Bad Request - Invalid Body

**Occurs when:** Log request doesn't match expected format

```json
HTTP/1.1 400 Bad Request
{
  "error": "Invalid body. Expected { level, message } or { logs: [...] }"
}
```

**How to fix:**
```bash
# Single log format
curl -X POST http://localhost:4000/api/builds/$BUILD_ID/logs \
  -H "X-Worker-Id: $WORKER_ID" \
  -H "Content-Type: application/json" \
  -d '{"level": "info", "message": "Log text"}'

# OR batch format
curl -X POST http://localhost:4000/api/builds/$BUILD_ID/logs \
  -H "X-Worker-Id: $WORKER_ID" \
  -H "Content-Type: application/json" \
  -d '{"logs": [{"level": "info", "message": "Log 1"}]}'
```

---

### 400 Bad Request - Missing Result File

**Occurs when:** Worker uploads success without result file

```json
HTTP/1.1 400 Bad Request
{
  "error": "Missing result file"
}
```

**How to fix:**
```bash
# Include result file when success=true
curl -X POST http://localhost:4000/api/workers/upload \
  -H "X-API-Key: dev-key-12345" \
  -F "build_id=$BUILD_ID" \
  -F "worker_id=$WORKER_ID" \
  -F "success=true" \
  -F "result=@app.ipa"  # Required when success=true
```

---

### 400 Bad Request - Build ID and Worker ID Required

**Occurs when:** Upload missing required fields

```json
HTTP/1.1 400 Bad Request
{
  "error": "build_id and worker_id required"
}
```

**How to fix:**
```bash
# Include both fields
curl -X POST http://localhost:4000/api/workers/upload \
  -H "X-API-Key: dev-key-12345" \
  -F "build_id=$BUILD_ID" \
  -F "worker_id=$WORKER_ID" \
  -F "success=true" \
  -F "result=@app.ipa"
```

---

### 400 Bad Request - Invalid File Type

**Occurs when:** Download requested for invalid file type (Elixir-specific)

```json
HTTP/1.1 400 Bad Request
{
  "error": "Invalid file type"
}
```

**How to fix:**
- Use `/api/builds/:id/download` (defaults to result)
- Valid types: `source`, `result`

---

### 404 Not Found - Build Not Found

**Occurs when:** Build ID doesn't exist in database

```json
HTTP/1.1 404 Not Found
{
  "error": "Build not found"
}
```

**How to fix:**
- Verify build ID is correct (case-sensitive)
- Check if build was purged due to retention policy
- Ensure you're using production vs. dev database

```bash
# List all builds to verify ID exists
curl -H "X-API-Key: dev-key-12345" \
  http://localhost:4000/api/builds
```

---

### 404 Not Found - Worker Not Found

**Occurs when:** Worker ID doesn't exist or hasn't registered

```json
HTTP/1.1 404 Not Found
{
  "error": "Worker not found"
}
```

**How to fix:**
```bash
# Register worker first
curl -X POST http://localhost:4000/api/workers/register \
  -H "X-API-Key: dev-key-12345" \
  -H "Content-Type: application/json" \
  -d "{\"id\": \"$WORKER_ID\", \"name\": \"Worker Name\", \"capabilities\": {}}"

# Then poll
curl -H "X-API-Key: dev-key-12345" \
  "http://localhost:4000/api/workers/poll?worker_id=$WORKER_ID"
```

---

### 404 Not Found - Build Result Not Found

**Occurs when:** Result file doesn't exist (internal error or file deleted)

```json
HTTP/1.1 404 Not Found
{
  "error": "Build result not found"
}
```

**How to fix:**
- Verify build status is `completed`
- Check controller storage directory for file
- This usually indicates server-side storage issue

**Debug:**
```bash
# Check build details
curl -H "X-API-Key: dev-key-12345" \
  "http://localhost:4000/api/builds/$BUILD_ID/status"

# Check controller logs for storage errors
tail -f controller.log | grep ERROR
```

---

### 404 Not Found - Certs Not Found

**Occurs when:** Build submitted without certificates, worker tries to download

```json
HTTP/1.1 404 Not Found
{
  "error": "Certs not found"
}
```

**How to fix:**
- Check if `certs_url` is `null` in poll response before attempting download
- Not all builds require certificates (Android, some iOS dev builds)

```bash
# Check if certs exist before downloading
CERTS_URL=$(curl -s -H "X-API-Key: dev-key-12345" \
  "http://localhost:4000/api/workers/poll?worker_id=$WORKER_ID" \
  | jq -r '.job.certs_url')

if [ "$CERTS_URL" != "null" ]; then
  curl -H "X-Worker-Id: $WORKER_ID" \
    "http://localhost:4000$CERTS_URL" -o certs.zip
fi
```

---

### 413 Payload Too Large - Source File Too Large

**Occurs when:** Source archive exceeds configured limit (default 500MB)

```json
HTTP/1.1 413 Payload Too Large
{
  "error": "Source file too large"
}
```

**How to fix:**
- Reduce source archive size
- Remove unnecessary files (node_modules, build artifacts)
- Use `.gitignore` patterns when creating archive

```bash
# Check archive size
ls -lh app.tar.gz

# Create smaller archive
tar -czf app.tar.gz \
  --exclude=node_modules \
  --exclude=ios/build \
  --exclude=android/build \
  --exclude=.git \
  .
```

---

### 413 Payload Too Large - Certs File Too Large

**Occurs when:** Certificates archive exceeds configured limit (default 50MB)

```json
HTTP/1.1 413 Payload Too Large
{
  "error": "Certs file too large"
}
```

**How to fix:**
- Certs should be small (typically < 1MB)
- Check for accidentally included files
- Only include `.p12` and `.mobileprovision` files

```bash
# Verify certs archive contents
unzip -l certs.zip

# Rebuild certs archive with only required files
zip certs.zip cert.p12 *.mobileprovision
```

---

### 413 Payload Too Large - Result File Too Large

**Occurs when:** Build result exceeds configured limit (default 2GB)

```json
HTTP/1.1 413 Payload Too Large
{
  "error": "Result file too large"
}
```

**How to fix:**
- Result should be compiled app only (`.ipa` or `.apk`)
- Check for accidentally included debug symbols or logs
- Strip unnecessary resources

---

### 422 Unprocessable Entity - Registration Failed

**Occurs when:** Worker registration validation failed (Elixir-specific)

```json
HTTP/1.1 422 Unprocessable Entity
{
  "error": "Registration failed",
  "details": {
    "name": ["can't be blank"],
    "id": ["has invalid format"]
  }
}
```

**How to fix:**
- Provide valid `id`, `name`, and `capabilities`
- Ensure JSON is valid
- Check field types match schema

```bash
curl -X POST http://localhost:4000/api/workers/register \
  -H "X-API-Key: dev-key-12345" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "worker-valid-id-123",
    "name": "Valid Worker Name",
    "capabilities": {}
  }'
```

---

## Server Errors (500)

### 500 Internal Server Error - Build Submission Failed

**Occurs when:** Unexpected error during build submission

```json
HTTP/1.1 500 Internal Server Error
{
  "error": "Build submission failed"
}
```

**How to fix:**
- Check controller logs for detailed error
- Verify storage directory is writable
- Check database connectivity
- Ensure sufficient disk space

**Debug:**
```bash
# Check controller logs
tail -f controller.log

# Check disk space
df -h

# Verify storage directory permissions
ls -ld storage/
```

---

### 500 Internal Server Error - Build Creation Failed

**Occurs when:** Database or storage failure (Elixir-specific)

```json
HTTP/1.1 500 Internal Server Error
{
  "error": "Build creation failed",
  "reason": "Database constraint violation"
}
```

**How to fix:**
- Check PostgreSQL/database logs
- Verify database schema is up to date
- Check for disk space issues

---

### 500 Internal Server Error - Upload Failed

**Occurs when:** Worker result upload encountered server error

```json
HTTP/1.1 500 Internal Server Error
{
  "error": "Upload failed"
}
```

**How to fix:**
- Check controller storage directory permissions
- Verify disk space available
- Check controller logs for specific error

---

### 500 Internal Server Error - Failed to Read Build Result

**Occurs when:** Controller can't read result file from storage

```json
HTTP/1.1 500 Internal Server Error
{
  "error": "Failed to read build result"
}
```

**How to fix:**
- Check storage directory integrity
- Verify file permissions
- Check for disk errors
- Review controller logs

---

### 500 Internal Server Error - Failed to Add Log

**Occurs when:** Database error when storing log entry

```json
HTTP/1.1 500 Internal Server Error
{
  "error": "Failed to add log"
}
```

**How to fix:**
- Check database connectivity
- Verify database disk space
- Check for database corruption

---

## Build-Specific Errors

### Build Timeout

**Occurs when:** No heartbeat received for 2 minutes

**Logged as:**
```
Build timeout - worker stopped responding
```

**How to fix:**
- Ensure worker sends heartbeats every 30 seconds
- Check worker process didn't crash
- Verify network connectivity
- Check VM resource constraints

**Prevention:**
```bash
# Send heartbeat every 30 seconds
while build_running; do
  curl -s -X POST \
    "http://localhost:4000/api/builds/$BUILD_ID/heartbeat?worker_id=$WORKER_ID" \
    -H "Content-Type: application/json" \
    -d '{}' > /dev/null
  sleep 30
done
```

---

### Build Cancelled by User

**Occurs when:** User calls cancel endpoint

**Status:** Build marked as `failed`

**Error message:**
```
Build cancelled by user
```

**Related:** [API.md - POST /api/builds/:id/cancel](./API.md#post-apibuildsidcancel)

---

## Worker-Specific Errors

### Worker Disconnect

**Symptom:** Worker polling returns 404

**Cause:** Worker record deleted or expired

**How to fix:**
```bash
# Re-register worker
curl -X POST http://localhost:4000/api/workers/register \
  -H "X-API-Key: dev-key-12345" \
  -H "Content-Type: application/json" \
  -d "{\"id\": \"$WORKER_ID\", \"name\": \"Worker\", \"capabilities\": {}}"
```

---

## Troubleshooting Guide

### Quick Diagnostics

```bash
#!/bin/bash

echo "=== Controller Diagnostics ==="

# 1. Health check
echo -n "Health: "
curl -s http://localhost:4000/health | jq -r '.status'

# 2. API authentication
echo -n "API Auth: "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "X-API-Key: $API_KEY" \
  http://localhost:4000/api/builds)
[ "$HTTP_CODE" == "200" ] && echo "OK" || echo "FAILED ($HTTP_CODE)"

# 3. Active builds
echo -n "Active Builds: "
curl -s -H "X-API-Key: $API_KEY" \
  http://localhost:4000/api/builds/active | jq -r '.builds | length'

# 4. Queue status
echo -n "Queue: "
curl -s http://localhost:4000/health | jq -r '"Pending: \(.queue.pending) Active: \(.queue.active)"'
```

---

### Common Issue Checklist

**Build stuck in pending:**
- [ ] Any workers online? Check `/health` for `nodesOnline`
- [ ] Workers polling? Check worker logs
- [ ] Queue full? Check `/health` for queue stats

**Build timing out:**
- [ ] Worker sending heartbeats? Check build logs
- [ ] Network connectivity between worker and controller?
- [ ] VM resource constraints (CPU, memory)?

**Download fails:**
- [ ] Build status is `completed`? Check `/api/builds/:id/status`
- [ ] Using correct authentication (API key or build token)?
- [ ] Sufficient disk space on client?

**Worker can't register:**
- [ ] API key correct?
- [ ] Controller reachable? Check `curl http://controller:4000/health`
- [ ] Valid JSON in request body?

---

### Debug Mode

Enable verbose logging:

```bash
# Client-side: Add -v flag
curl -v -H "X-API-Key: dev-key-12345" \
  http://localhost:4000/api/builds

# Save response headers
curl -D headers.txt \
  -H "X-API-Key: dev-key-12345" \
  http://localhost:4000/api/builds
cat headers.txt
```

---

### Network Debugging

```bash
# Test controller reachability
ping controller.example.com

# Test port open
nc -zv controller.example.com 4000

# Test DNS resolution
nslookup controller.example.com

# Trace route
traceroute controller.example.com
```

---

### Log Analysis

```bash
# Find recent errors
grep ERROR controller.log | tail -20

# Find build-specific errors
grep "build_id.*abc123" controller.log | grep ERROR

# Monitor live logs
tail -f controller.log | grep --line-buffered ERROR
```

---

## Getting Help

If you encounter an error not covered here:

1. **Check controller logs** for detailed error messages
2. **Verify authentication** credentials are correct
3. **Test with curl** to isolate client vs. server issues
4. **Check system resources** (disk space, memory, CPU)
5. **File an issue** on GitHub with:
   - Error message and HTTP status code
   - Request/response details
   - Controller logs (redact sensitive info)
   - Controller version

---

## Related Documentation

- [API.md](./API.md) - Complete API reference
- [INTEGRATION_EXAMPLES.md](./INTEGRATION_EXAMPLES.md) - Working examples
- [docs/INDEX.md](../../docs/INDEX.md) - Architecture and setup guides

---

*Last updated: 2024-01-28*
