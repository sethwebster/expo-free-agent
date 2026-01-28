# API Reference

Complete reference for the Expo Free Agent Controller API.

## Base URL

```
http://localhost:3000    # Local development
https://your-domain.com  # Production
```

## Authentication

All API endpoints (except `/health`) require authentication via API key.

### Header Format

```http
Authorization: Bearer YOUR_API_KEY
```

### Example

```bash
curl -H "Authorization: Bearer abc123..." \
  http://localhost:3000/api/builds
```

### Obtaining API Key

The API key is displayed when starting the controller:

```bash
$ bun controller
🚀 Expo Free Agent Controller
🔑 API Key: eyJhbGc...xyz (save this!)
```

Or set your own:

```bash
export CONTROLLER_API_KEY="your-secure-key-min-16-chars"
bun controller
```

---

## Builds API

### Submit Build

Submit a new build for processing.

**Endpoint:** `POST /api/builds/submit`

**Authentication:** Required

**Request:**

```http
POST /api/builds/submit HTTP/1.1
Host: localhost:3000
Authorization: Bearer YOUR_API_KEY
Content-Type: multipart/form-data

--boundary
Content-Disposition: form-data; name="source"; filename="source.tar.gz"
Content-Type: application/gzip

[binary data]
--boundary
Content-Disposition: form-data; name="platform"

ios
--boundary
Content-Disposition: form-data; name="metadata"

{"projectName":"MyApp","version":"1.0.0"}
--boundary--
```

**Parameters:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `source` | File | Yes | Source code tarball (.tar.gz) |
| `platform` | String | Yes | Build platform: `ios` or `android` |
| `metadata` | JSON | No | Additional build metadata |
| `credentials` | File | No | Signing credentials (.p12, .mobileprovision) |

**Response:**

```json
{
  "buildId": "build-abc123",
  "jobId": "job-xyz789",
  "status": "pending",
  "createdAt": "2024-01-28T10:15:23Z"
}
```

**Status Codes:**

- `201` - Build submitted successfully
- `400` - Invalid request (missing required fields)
- `401` - Unauthorized (invalid API key)
- `413` - Payload too large
- `500` - Server error

**Example:**

```bash
curl -X POST \
  -H "Authorization: Bearer $API_KEY" \
  -F "source=@source.tar.gz" \
  -F "platform=ios" \
  -F 'metadata={"projectName":"MyApp"}' \
  http://localhost:3000/api/builds/submit
```

---

### Get Build Status

Check the status of a build.

**Endpoint:** `GET /api/builds/:buildId/status`

**Authentication:** Required

**Parameters:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `buildId` | Path | Yes | Build identifier (e.g., `build-abc123`) |

**Response:**

```json
{
  "buildId": "build-abc123",
  "status": "completed",
  "platform": "ios",
  "createdAt": "2024-01-28T10:15:23Z",
  "startedAt": "2024-01-28T10:16:00Z",
  "completedAt": "2024-01-28T10:28:34Z",
  "duration": 754,
  "worker": {
    "id": "worker-001",
    "name": "mac-mini-office"
  },
  "artifacts": [
    {
      "name": "MyApp.ipa",
      "size": 56789012,
      "checksum": "sha256:abc123..."
    }
  ]
}
```

**Build Status Values:**

- `pending` - Waiting for worker assignment
- `assigned` - Assigned to worker, not yet started
- `running` - Build in progress
- `completed` - Build successful
- `failed` - Build failed
- `timeout` - Build exceeded time limit
- `cancelled` - Build cancelled by user

**Status Codes:**

- `200` - Success
- `401` - Unauthorized
- `404` - Build not found
- `500` - Server error

**Example:**

```bash
curl -H "Authorization: Bearer $API_KEY" \
  http://localhost:3000/api/builds/build-abc123/status
```

---

### Download Build Artifacts

Download completed build artifacts.

**Endpoint:** `GET /api/builds/:buildId/artifacts/:filename`

**Authentication:** Required

**Parameters:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `buildId` | Path | Yes | Build identifier |
| `filename` | Path | Yes | Artifact filename (e.g., `MyApp.ipa`) |

**Response:**

Binary stream of the requested file.

**Headers:**

```http
Content-Type: application/octet-stream
Content-Disposition: attachment; filename="MyApp.ipa"
Content-Length: 56789012
X-Checksum-SHA256: abc123...
```

**Status Codes:**

- `200` - Success (file stream)
- `401` - Unauthorized
- `404` - Build or artifact not found
- `500` - Server error

**Example:**

```bash
curl -H "Authorization: Bearer $API_KEY" \
  -o MyApp.ipa \
  http://localhost:3000/api/builds/build-abc123/artifacts/MyApp.ipa
```

---

### Get Build Logs

Retrieve build logs.

**Endpoint:** `GET /api/builds/:buildId/logs`

**Authentication:** Required

**Parameters:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `buildId` | Path | Yes | Build identifier |
| `tail` | Query | No | Return last N lines (default: all) |
| `follow` | Query | No | Stream logs in real-time (default: false) |

**Response:**

```json
{
  "buildId": "build-abc123",
  "logs": [
    {
      "timestamp": "2024-01-28T10:16:05Z",
      "level": "info",
      "message": "Installing dependencies..."
    },
    {
      "timestamp": "2024-01-28T10:18:23Z",
      "level": "info",
      "message": "Building application..."
    },
    {
      "timestamp": "2024-01-28T10:28:30Z",
      "level": "info",
      "message": "Build completed successfully"
    }
  ]
}
```

**Example:**

```bash
# Get all logs
curl -H "Authorization: Bearer $API_KEY" \
  http://localhost:3000/api/builds/build-abc123/logs

# Get last 100 lines
curl -H "Authorization: Bearer $API_KEY" \
  "http://localhost:3000/api/builds/build-abc123/logs?tail=100"

# Stream logs (Server-Sent Events)
curl -H "Authorization: Bearer $API_KEY" \
  -H "Accept: text/event-stream" \
  "http://localhost:3000/api/builds/build-abc123/logs?follow=true"
```

---

### List Builds

Get a list of all builds.

**Endpoint:** `GET /api/builds`

**Authentication:** Required

**Query Parameters:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `status` | String | all | Filter by status (pending, running, completed, failed) |
| `platform` | String | all | Filter by platform (ios, android) |
| `limit` | Number | 50 | Max results to return (1-100) |
| `offset` | Number | 0 | Pagination offset |
| `since` | ISO Date | - | Only builds after this date |

**Response:**

```json
{
  "builds": [
    {
      "buildId": "build-abc123",
      "status": "completed",
      "platform": "ios",
      "createdAt": "2024-01-28T10:15:23Z",
      "duration": 754
    },
    {
      "buildId": "build-def456",
      "status": "running",
      "platform": "android",
      "createdAt": "2024-01-28T11:20:00Z",
      "duration": 180
    }
  ],
  "total": 42,
  "limit": 50,
  "offset": 0
}
```

**Example:**

```bash
# List all builds
curl -H "Authorization: Bearer $API_KEY" \
  http://localhost:3000/api/builds

# List completed iOS builds
curl -H "Authorization: Bearer $API_KEY" \
  "http://localhost:3000/api/builds?status=completed&platform=ios"

# Pagination
curl -H "Authorization: Bearer $API_KEY" \
  "http://localhost:3000/api/builds?limit=10&offset=20"
```

---

### Cancel Build

Cancel a pending or running build.

**Endpoint:** `DELETE /api/builds/:buildId`

**Authentication:** Required

**Parameters:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `buildId` | Path | Yes | Build identifier |

**Response:**

```json
{
  "buildId": "build-abc123",
  "status": "cancelled",
  "message": "Build cancelled successfully"
}
```

**Status Codes:**

- `200` - Build cancelled
- `400` - Build cannot be cancelled (already completed/failed)
- `401` - Unauthorized
- `404` - Build not found
- `500` - Server error

**Example:**

```bash
curl -X DELETE \
  -H "Authorization: Bearer $API_KEY" \
  http://localhost:3000/api/builds/build-abc123
```

---

## Workers API

### Register Worker

Register a new worker with the controller.

**Endpoint:** `POST /api/workers/register`

**Authentication:** Required

**Request:**

```json
{
  "name": "mac-mini-office",
  "capabilities": {
    "platforms": ["ios", "android"],
    "xcodeVersion": "15.1",
    "maxConcurrentBuilds": 2
  },
  "resources": {
    "cpu": 8,
    "memory": 16384,
    "disk": 256000
  }
}
```

**Response:**

```json
{
  "workerId": "worker-001",
  "name": "mac-mini-office",
  "status": "online",
  "registeredAt": "2024-01-28T10:00:00Z"
}
```

**Example:**

```bash
curl -X POST \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "mac-mini-office",
    "capabilities": {
      "platforms": ["ios"],
      "xcodeVersion": "15.1"
    }
  }' \
  http://localhost:3000/api/workers/register
```

---

### Poll for Jobs

Workers poll this endpoint to receive build jobs.

**Endpoint:** `GET /api/workers/:workerId/poll`

**Authentication:** Required

**Parameters:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `workerId` | Path | Yes | Worker identifier |

**Response (Job Available):**

```json
{
  "jobId": "job-xyz789",
  "buildId": "build-abc123",
  "platform": "ios",
  "source": {
    "url": "http://localhost:3000/api/builds/build-abc123/source",
    "checksum": "sha256:abc123..."
  },
  "timeout": 1800
}
```

**Response (No Jobs):**

```json
{
  "message": "No jobs available"
}
```

**Status Codes:**

- `200` - Job assigned or no jobs
- `401` - Unauthorized
- `404` - Worker not found
- `500` - Server error

**Example:**

```bash
curl -H "Authorization: Bearer $API_KEY" \
  http://localhost:3000/api/workers/worker-001/poll
```

---

### Update Job Status

Workers update job status during build execution.

**Endpoint:** `PUT /api/workers/:workerId/jobs/:jobId`

**Authentication:** Required

**Request:**

```json
{
  "status": "running",
  "progress": 45,
  "message": "Installing dependencies..."
}
```

**Status Values:**

- `assigned` - Job received by worker
- `running` - Build in progress
- `uploading` - Uploading artifacts
- `completed` - Build successful
- `failed` - Build failed

**Response:**

```json
{
  "jobId": "job-xyz789",
  "status": "running",
  "updatedAt": "2024-01-28T10:18:00Z"
}
```

**Example:**

```bash
curl -X PUT \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"status":"running","progress":45}' \
  http://localhost:3000/api/workers/worker-001/jobs/job-xyz789
```

---

### Upload Artifacts

Workers upload build artifacts after successful build.

**Endpoint:** `POST /api/workers/:workerId/jobs/:jobId/artifacts`

**Authentication:** Required

**Request:**

```http
POST /api/workers/worker-001/jobs/job-xyz789/artifacts HTTP/1.1
Content-Type: multipart/form-data

--boundary
Content-Disposition: form-data; name="artifact"; filename="MyApp.ipa"
Content-Type: application/octet-stream

[binary data]
--boundary--
```

**Response:**

```json
{
  "artifacts": [
    {
      "name": "MyApp.ipa",
      "size": 56789012,
      "checksum": "sha256:abc123...",
      "uploadedAt": "2024-01-28T10:28:30Z"
    }
  ]
}
```

**Example:**

```bash
curl -X POST \
  -H "Authorization: Bearer $API_KEY" \
  -F "artifact=@MyApp.ipa" \
  http://localhost:3000/api/workers/worker-001/jobs/job-xyz789/artifacts
```

---

### List Workers

Get all registered workers.

**Endpoint:** `GET /api/workers`

**Authentication:** Required

**Response:**

```json
{
  "workers": [
    {
      "workerId": "worker-001",
      "name": "mac-mini-office",
      "status": "online",
      "currentJobs": 1,
      "totalBuilds": 42,
      "lastSeen": "2024-01-28T10:29:00Z"
    },
    {
      "workerId": "worker-002",
      "name": "macbook-pro-15",
      "status": "offline",
      "currentJobs": 0,
      "totalBuilds": 18,
      "lastSeen": "2024-01-27T18:30:00Z"
    }
  ]
}
```

**Example:**

```bash
curl -H "Authorization: Bearer $API_KEY" \
  http://localhost:3000/api/workers
```

---

## Health & Monitoring

### Health Check

Check controller health and get statistics.

**Endpoint:** `GET /health`

**Authentication:** Not required

**Response:**

```json
{
  "status": "healthy",
  "version": "0.1.23",
  "uptime": 3600,
  "stats": {
    "totalBuilds": 123,
    "pendingBuilds": 2,
    "runningBuilds": 3,
    "completedBuilds": 115,
    "failedBuilds": 3,
    "activeWorkers": 4,
    "queueDepth": 2
  },
  "timestamp": "2024-01-28T10:30:00Z"
}
```

**Example:**

```bash
curl http://localhost:3000/health
```

---

## Rate Limits

Current implementation has no rate limits. Future versions will implement:

- **Authenticated requests:** 1000 requests/hour
- **Build submissions:** 50 builds/hour
- **Artifact downloads:** Unlimited (bandwidth limited by network)

Rate limit headers (future):

```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 987
X-RateLimit-Reset: 1706438400
```

---

## Error Responses

All errors follow this format:

```json
{
  "error": {
    "code": "EXPO-CLI-1001",
    "message": "Authentication failed",
    "details": "Invalid or missing API key"
  }
}
```

Common error codes:

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `INVALID_API_KEY` | 401 | API key invalid or missing |
| `BUILD_NOT_FOUND` | 404 | Build ID does not exist |
| `WORKER_NOT_FOUND` | 404 | Worker ID does not exist |
| `PAYLOAD_TOO_LARGE` | 413 | Upload exceeds size limit |
| `BUILD_TIMEOUT` | 408 | Build exceeded time limit |
| `INTERNAL_ERROR` | 500 | Server error |

See [Error Reference](./errors.md) for complete list.

---

## Versioning

API version is included in response headers:

```http
X-API-Version: 0.1.23
```

Breaking changes will increment major version. Current API is `v1` (implicit).

Future versioning (when needed):

```
/api/v2/builds
```

---

## Changelog

### v0.1.23 (2024-01-28)
- Initial API implementation
- Build submission and status endpoints
- Worker registration and polling
- Artifact upload/download

### Future Additions
- Webhook support for build events
- GraphQL API (optional)
- Batch operations
- Advanced filtering and search

---

## Feedback

**Was this API reference helpful?** 👍 👎

Help us improve:
- [Report missing endpoints](https://github.com/expo/expo-free-agent/issues/new?labels=documentation,api&title=API%20Reference:%20)
- [Request better examples](https://github.com/expo/expo-free-agent/discussions)
- [Edit this page](https://github.com/expo/expo-free-agent/edit/main/docs/reference/api.md)

**What would make this better?**
- More code examples?
- Additional endpoints needed?
- Clearer parameter descriptions?
- SDK/library examples?

Let us know!

---

**Last Updated:** 2026-01-28
