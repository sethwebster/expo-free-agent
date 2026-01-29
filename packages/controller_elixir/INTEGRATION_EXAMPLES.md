# API Integration Examples

Real-world scenarios for integrating with the Expo Free Agent Controller API.

---

## Table of Contents

- [Scenario 1: Submit and Monitor a Build (CLI)](#scenario-1-submit-and-monitor-a-build-cli)
- [Scenario 2: Worker Lifecycle (Complete Flow)](#scenario-2-worker-lifecycle-complete-flow)
- [Scenario 3: Build Retry After Failure](#scenario-3-build-retry-after-failure)
- [Scenario 4: Monitoring Active Builds](#scenario-4-monitoring-active-builds)
- [Scenario 5: Health Check for Load Balancers](#scenario-5-health-check-for-load-balancers)
- [Scenario 6: CI/CD Integration (GitHub Actions)](#scenario-6-cicd-integration-github-actions)
- [Scenario 7: Landing Page Stats Integration](#scenario-7-landing-page-stats-integration)

---

## Scenario 1: Submit and Monitor a Build (CLI)

**Use Case:** Developer submits iOS app build and waits for result.

### Step 1: Submit Build

```bash
curl -X POST http://localhost:4000/api/builds/submit \
  -H "X-API-Key: dev-key-12345" \
  -F "platform=ios" \
  -F "source=@app.tar.gz" \
  -F "certs=@certs.zip"
```

**Response:**
```json
{
  "id": "V1bN8xK9rLmQ",
  "status": "pending",
  "platform": "ios",
  "submitted_at": "2024-01-28T12:00:00Z",
  "access_token": "xEj8kP3nR5mT..."
}
```

**Save the `access_token`** - you'll need it to check status and download results.

---

### Step 2: Poll Build Status

Poll every 5 seconds until status is `completed` or `failed`:

```bash
while true; do
  STATUS=$(curl -s \
    -H "X-Build-Token: xEj8kP3nR5mT..." \
    http://localhost:4000/api/builds/V1bN8xK9rLmQ/status \
    | jq -r '.status')

  echo "Build status: $STATUS"

  if [ "$STATUS" == "completed" ] || [ "$STATUS" == "failed" ]; then
    break
  fi

  sleep 5
done
```

**Response (Building):**
```json
{
  "id": "V1bN8xK9rLmQ",
  "status": "building",
  "platform": "ios",
  "worker_id": "worker-abc",
  "submitted_at": 1706450400000,
  "started_at": 1706450460000,
  "completed_at": null,
  "error_message": null
}
```

**Response (Completed):**
```json
{
  "id": "V1bN8xK9rLmQ",
  "status": "completed",
  "platform": "ios",
  "worker_id": "worker-abc",
  "submitted_at": 1706450400000,
  "started_at": 1706450460000,
  "completed_at": 1706451260000,
  "error_message": null
}
```

---

### Step 3: View Logs (Optional)

```bash
curl -s \
  -H "X-Build-Token: xEj8kP3nR5mT..." \
  http://localhost:4000/api/builds/V1bN8xK9rLmQ/logs \
  | jq -r '.logs[] | "\(.timestamp) [\(.level | ascii_upcase)] \(.message)"'
```

**Output:**
```
2024-01-28T12:00:00Z [INFO] Build submitted
2024-01-28T12:01:00Z [INFO] Assigned to worker MacBook Pro (Seth)
2024-01-28T12:05:00Z [INFO] [VM] Stage: building | CPU: 78.2% | Mem: 2048MB
2024-01-28T12:14:00Z [INFO] Build completed successfully
```

---

### Step 4: Download Result

```bash
curl -H "X-Build-Token: xEj8kP3nR5mT..." \
  http://localhost:4000/api/builds/V1bN8xK9rLmQ/download \
  -o app.ipa
```

**Output:**
```
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 45.2M  100 45.2M    0     0  89.3M      0 --:--:-- --:--:-- --:--:-- 89.3M
```

---

### Complete Script

```bash
#!/bin/bash
set -e

API_KEY="dev-key-12345"
CONTROLLER_URL="http://localhost:4000"

# Submit build
echo "Submitting build..."
RESPONSE=$(curl -s -X POST "$CONTROLLER_URL/api/builds/submit" \
  -H "X-API-Key: $API_KEY" \
  -F "platform=ios" \
  -F "source=@app.tar.gz" \
  -F "certs=@certs.zip")

BUILD_ID=$(echo "$RESPONSE" | jq -r '.id')
ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')

echo "Build submitted: $BUILD_ID"
echo "Access token: $ACCESS_TOKEN"

# Poll status
echo "Waiting for build to complete..."
while true; do
  STATUS=$(curl -s \
    -H "X-Build-Token: $ACCESS_TOKEN" \
    "$CONTROLLER_URL/api/builds/$BUILD_ID/status" \
    | jq -r '.status')

  echo "  Status: $STATUS"

  if [ "$STATUS" == "completed" ]; then
    echo "Build succeeded!"
    break
  elif [ "$STATUS" == "failed" ]; then
    echo "Build failed!"
    curl -s \
      -H "X-Build-Token: $ACCESS_TOKEN" \
      "$CONTROLLER_URL/api/builds/$BUILD_ID/logs" \
      | jq -r '.logs[] | select(.level == "error") | .message'
    exit 1
  fi

  sleep 5
done

# Download result
echo "Downloading result..."
curl -H "X-Build-Token: $ACCESS_TOKEN" \
  "$CONTROLLER_URL/api/builds/$BUILD_ID/download" \
  -o "build-$BUILD_ID.ipa"

echo "Build downloaded: build-$BUILD_ID.ipa"
```

---

## Scenario 2: Worker Lifecycle (Complete Flow)

**Use Case:** Worker process running on macOS machine.

### Step 1: Register Worker

```bash
WORKER_ID="worker-$(uname -n)-$(date +%s)"

curl -X POST http://localhost:4000/api/workers/register \
  -H "X-API-Key: dev-key-12345" \
  -H "Content-Type: application/json" \
  -d "{
    \"id\": \"$WORKER_ID\",
    \"name\": \"MacBook Pro ($(whoami))\",
    \"capabilities\": {
      \"platform\": \"darwin\",
      \"arch\": \"$(uname -m)\",
      \"xcode_version\": \"$(xcodebuild -version | head -n1 | awk '{print $2}')\"
    }
  }"
```

**Response:**
```json
{
  "id": "worker-MacBookPro-1706450400",
  "status": "registered",
  "message": "Worker registered successfully"
}
```

---

### Step 2: Poll for Jobs

Poll every second:

```bash
while true; do
  RESPONSE=$(curl -s \
    -H "X-API-Key: dev-key-12345" \
    "http://localhost:4000/api/workers/poll?worker_id=$WORKER_ID")

  JOB_ID=$(echo "$RESPONSE" | jq -r '.job.id // empty')

  if [ -n "$JOB_ID" ]; then
    echo "Received job: $JOB_ID"
    PLATFORM=$(echo "$RESPONSE" | jq -r '.job.platform')
    SOURCE_URL=$(echo "$RESPONSE" | jq -r '.job.source_url')
    CERTS_URL=$(echo "$RESPONSE" | jq -r '.job.certs_url')

    # Process job (see Step 3)
    process_build "$JOB_ID" "$PLATFORM" "$SOURCE_URL" "$CERTS_URL"
  fi

  sleep 1
done
```

---

### Step 3: Download Source

```bash
curl -H "X-Worker-Id: $WORKER_ID" \
  "http://localhost:4000$SOURCE_URL" \
  -o source.zip
```

---

### Step 4: Download Certificates (if iOS)

```bash
if [ "$PLATFORM" == "ios" ] && [ "$CERTS_URL" != "null" ]; then
  # Option A: Download as ZIP
  curl -H "X-Worker-Id: $WORKER_ID" \
    "http://localhost:4000$CERTS_URL" \
    -o certs.zip

  # Option B: Get as JSON for VM injection
  curl -H "X-Worker-Id: $WORKER_ID" \
       -H "X-Build-Id: $JOB_ID" \
    "http://localhost:4000/api/builds/$JOB_ID/certs-secure"
fi
```

**Response (certs-secure):**
```json
{
  "p12": "MIIKZAIBAzCCCh4GCSqGSIb3...",
  "p12Password": "mypassword",
  "keychainPassword": "rAnD0m24ByteP@ssw0rd",
  "provisioningProfiles": [
    "MIIOzAYJKoZIhvcNAQcCoII..."
  ]
}
```

---

### Step 5: Send Heartbeats During Build

In a background process:

```bash
while true; do
  curl -s -X POST \
    "http://localhost:4000/api/builds/$JOB_ID/heartbeat?worker_id=$WORKER_ID" \
    -H "Content-Type: application/json" \
    -d '{"progress": 50}' > /dev/null

  sleep 30
done &

HEARTBEAT_PID=$!
```

---

### Step 6: Stream Logs

```bash
# Single log
curl -X POST "http://localhost:4000/api/builds/$JOB_ID/logs" \
  -H "X-Worker-Id: $WORKER_ID" \
  -H "Content-Type: application/json" \
  -d '{"level": "info", "message": "Starting Xcode build..."}'

# Batch logs
curl -X POST "http://localhost:4000/api/builds/$JOB_ID/logs" \
  -H "X-Worker-Id: $WORKER_ID" \
  -H "Content-Type: application/json" \
  -d '{
    "logs": [
      {"level": "info", "message": "Downloading dependencies..."},
      {"level": "info", "message": "Building workspace..."},
      {"level": "info", "message": "Archiving..."}
    ]
  }'
```

---

### Step 7: Send Telemetry

```bash
curl -X POST "http://localhost:4000/api/builds/$JOB_ID/telemetry" \
  -H "X-Worker-Id: $WORKER_ID" \
  -H "X-Build-Id: $JOB_ID" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"heartbeat\",
    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"data\": {
      \"stage\": \"building\",
      \"metrics\": {
        \"cpu_percent\": $(top -l 1 | grep "CPU usage" | awk '{print $3}' | tr -d '%'),
        \"memory_mb\": 2048,
        \"disk_percent\": 15
      },
      \"heartbeat_count\": 12
    }
  }"
```

---

### Step 8: Upload Result

**Success:**

```bash
# Stop heartbeat
kill $HEARTBEAT_PID

curl -X POST http://localhost:4000/api/workers/upload \
  -H "X-API-Key: dev-key-12345" \
  -F "build_id=$JOB_ID" \
  -F "worker_id=$WORKER_ID" \
  -F "success=true" \
  -F "result=@app.ipa"
```

**Failure:**

```bash
# Stop heartbeat
kill $HEARTBEAT_PID

curl -X POST http://localhost:4000/api/workers/upload \
  -H "X-API-Key: dev-key-12345" \
  -F "build_id=$JOB_ID" \
  -F "worker_id=$WORKER_ID" \
  -F "success=false" \
  -F "error_message=Xcode build failed: Code signing identity not found"
```

---

### Complete Worker Script

```bash
#!/bin/bash
set -e

API_KEY="dev-key-12345"
CONTROLLER_URL="http://localhost:4000"
WORKER_ID="worker-$(uname -n)-$(date +%s)"

# Register
echo "Registering worker: $WORKER_ID"
curl -X POST "$CONTROLLER_URL/api/workers/register" \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"id\": \"$WORKER_ID\",
    \"name\": \"MacBook Pro ($(whoami))\",
    \"capabilities\": {\"platform\": \"darwin\"}
  }"

echo "Worker registered. Polling for jobs..."

# Poll loop
while true; do
  RESPONSE=$(curl -s -H "X-API-Key: $API_KEY" \
    "$CONTROLLER_URL/api/workers/poll?worker_id=$WORKER_ID")

  JOB_ID=$(echo "$RESPONSE" | jq -r '.job.id // empty')

  if [ -n "$JOB_ID" ]; then
    echo "Processing build: $JOB_ID"

    PLATFORM=$(echo "$RESPONSE" | jq -r '.job.platform')
    SOURCE_URL=$(echo "$RESPONSE" | jq -r '.job.source_url')

    # Download source
    curl -H "X-Worker-Id: $WORKER_ID" \
      "$CONTROLLER_URL$SOURCE_URL" -o source.zip

    # Start heartbeat
    (while true; do
      curl -s -X POST \
        "$CONTROLLER_URL/api/builds/$JOB_ID/heartbeat?worker_id=$WORKER_ID" \
        -H "Content-Type: application/json" \
        -d '{}' > /dev/null
      sleep 30
    done) &
    HEARTBEAT_PID=$!

    # Build (simplified)
    if ./build.sh "$PLATFORM" source.zip app.$([[ "$PLATFORM" == "ios" ]] && echo "ipa" || echo "apk"); then
      # Upload success
      kill $HEARTBEAT_PID
      curl -X POST "$CONTROLLER_URL/api/workers/upload" \
        -H "X-API-Key: $API_KEY" \
        -F "build_id=$JOB_ID" \
        -F "worker_id=$WORKER_ID" \
        -F "success=true" \
        -F "result=@app.$([[ "$PLATFORM" == "ios" ]] && echo "ipa" || echo "apk")"
    else
      # Upload failure
      kill $HEARTBEAT_PID
      curl -X POST "$CONTROLLER_URL/api/workers/upload" \
        -H "X-API-Key: $API_KEY" \
        -F "build_id=$JOB_ID" \
        -F "worker_id=$WORKER_ID" \
        -F "success=false" \
        -F "error_message=Build script failed"
    fi

    # Cleanup
    rm -f source.zip app.ipa app.apk
  fi

  sleep 1
done
```

---

## Scenario 3: Build Retry After Failure

**Use Case:** Build failed due to transient error, retry with same source.

### Check Original Build Status

```bash
curl -H "X-Build-Token: xEj8kP3nR5mT..." \
  http://localhost:4000/api/builds/V1bN8xK9rLmQ/status
```

**Response:**
```json
{
  "id": "V1bN8xK9rLmQ",
  "status": "failed",
  "error_message": "Build timeout - worker stopped responding"
}
```

---

### Retry Build

```bash
curl -X POST http://localhost:4000/api/builds/V1bN8xK9rLmQ/retry \
  -H "X-Build-Token: xEj8kP3nR5mT..."
```

**Response:**
```json
{
  "id": "nEw8uIk3rQpM",
  "status": "pending",
  "submitted_at": 1706450500000,
  "access_token": "yFk9lQ4oS6nU...",
  "original_build_id": "V1bN8xK9rLmQ"
}
```

**New build created with:**
- Same source archive
- Same certificates
- New build ID
- New access token

---

### Monitor Retry

```bash
# Use new access token
curl -H "X-Build-Token: yFk9lQ4oS6nU..." \
  http://localhost:4000/api/builds/nEw8uIk3rQpM/status
```

---

## Scenario 4: Monitoring Active Builds

**Use Case:** Dashboard showing all in-progress builds.

```bash
curl -H "X-API-Key: dev-key-12345" \
  http://localhost:4000/api/builds/active
```

**Response:**
```json
{
  "builds": [
    {
      "id": "V1bN8xK9rLmQ",
      "status": "building",
      "platform": "ios",
      "worker_id": "worker-abc",
      "started_at": 1706450460000
    },
    {
      "id": "nEw8uIk3rQpM",
      "status": "assigned",
      "platform": "android",
      "worker_id": "worker-xyz",
      "started_at": 1706450480000
    }
  ]
}
```

---

### Parse and Display

```bash
curl -s -H "X-API-Key: dev-key-12345" \
  http://localhost:4000/api/builds/active \
  | jq -r '.builds[] | "\(.id) - \(.platform) - \(.status) - Worker: \(.worker_id)"'
```

**Output:**
```
V1bN8xK9rLmQ - ios - building - Worker: worker-abc
nEw8uIk3rQpM - android - assigned - Worker: worker-xyz
```

---

## Scenario 5: Health Check for Load Balancers

**Use Case:** Kubernetes liveness/readiness probe.

### Simple Health Check

```bash
curl http://localhost:4000/health
```

**Response:**
```json
{
  "status": "ok",
  "queue": {
    "pending": 3,
    "active": 2
  },
  "storage": {
    "totalBytes": 1073741824,
    "freeBytes": 536870912
  }
}
```

---

### Kubernetes Probe Configuration

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: controller
    image: expo-controller:latest
    ports:
    - containerPort: 4000
    livenessProbe:
      httpGet:
        path: /health
        port: 4000
      initialDelaySeconds: 10
      periodSeconds: 30
    readinessProbe:
      httpGet:
        path: /health
        port: 4000
      initialDelaySeconds: 5
      periodSeconds: 10
```

---

### Health Check Script

```bash
#!/bin/bash

CONTROLLER_URL="http://localhost:4000"

STATUS=$(curl -s "$CONTROLLER_URL/health" | jq -r '.status')

if [ "$STATUS" == "ok" ]; then
  echo "Controller healthy"
  exit 0
else
  echo "Controller unhealthy"
  exit 1
fi
```

---

## Scenario 6: CI/CD Integration (GitHub Actions)

**Use Case:** Automated iOS build on every release tag.

### GitHub Actions Workflow

```yaml
name: Build iOS App

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
    - name: Checkout code
      uses: actions/checkout@v3

    - name: Package source
      run: tar -czf app.tar.gz .

    - name: Submit build
      id: submit
      run: |
        RESPONSE=$(curl -X POST ${{ secrets.CONTROLLER_URL }}/api/builds/submit \
          -H "X-API-Key: ${{ secrets.CONTROLLER_API_KEY }}" \
          -F "platform=ios" \
          -F "source=@app.tar.gz" \
          -F "certs=@certs.zip")

        BUILD_ID=$(echo "$RESPONSE" | jq -r '.id')
        ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')

        echo "build_id=$BUILD_ID" >> $GITHUB_OUTPUT
        echo "access_token=$ACCESS_TOKEN" >> $GITHUB_OUTPUT

    - name: Wait for build
      run: |
        while true; do
          STATUS=$(curl -s \
            -H "X-Build-Token: ${{ steps.submit.outputs.access_token }}" \
            ${{ secrets.CONTROLLER_URL }}/api/builds/${{ steps.submit.outputs.build_id }}/status \
            | jq -r '.status')

          echo "Build status: $STATUS"

          if [ "$STATUS" == "completed" ]; then
            break
          elif [ "$STATUS" == "failed" ]; then
            echo "Build failed!"
            exit 1
          fi

          sleep 10
        done

    - name: Download IPA
      run: |
        curl -H "X-Build-Token: ${{ steps.submit.outputs.access_token }}" \
          ${{ secrets.CONTROLLER_URL }}/api/builds/${{ steps.submit.outputs.build_id }}/download \
          -o app.ipa

    - name: Upload to Release
      uses: actions/upload-release-asset@v1
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      with:
        upload_url: ${{ github.event.release.upload_url }}
        asset_path: ./app.ipa
        asset_name: app.ipa
        asset_content_type: application/octet-stream
```

---

## Scenario 7: Landing Page Stats Integration

**Use Case:** Display real-time network statistics on marketing website.

### Fetch Stats

```javascript
async function fetchNetworkStats() {
  const response = await fetch('http://localhost:4000/api/stats');
  const stats = await response.json();
  return stats;
}

// Example response:
// {
//   "nodesOnline": 127,
//   "buildsQueued": 83,
//   "activeBuilds": 24,
//   "buildsToday": 8492,
//   "totalBuilds": 80123456,
//   "totalBuildTimeMs": 24037036800000,
//   "totalCpuCycles": 9614814720
// }
```

---

### React Component

```jsx
import { useState, useEffect } from 'react';

export function NetworkStats() {
  const [stats, setStats] = useState(null);

  useEffect(() => {
    async function loadStats() {
      const response = await fetch('http://localhost:4000/api/stats');
      const data = await response.json();
      setStats(data);
    }

    loadStats();
    const interval = setInterval(loadStats, 10000); // Refresh every 10s

    return () => clearInterval(interval);
  }, []);

  if (!stats) return <div>Loading...</div>;

  return (
    <div className="stats-grid">
      <div className="stat">
        <div className="stat-value">{stats.nodesOnline.toLocaleString()}</div>
        <div className="stat-label">Nodes Online</div>
      </div>

      <div className="stat">
        <div className="stat-value">{stats.buildsQueued.toLocaleString()}</div>
        <div className="stat-label">Builds Queued</div>
      </div>

      <div className="stat">
        <div className="stat-value">{stats.activeBuilds.toLocaleString()}</div>
        <div className="stat-label">Active Builds</div>
      </div>

      <div className="stat">
        <div className="stat-value">{stats.buildsToday.toLocaleString()}</div>
        <div className="stat-label">Builds Today</div>
      </div>

      <div className="stat">
        <div className="stat-value">{(stats.totalBuilds / 1_000_000).toFixed(1)}M</div>
        <div className="stat-label">Total Builds</div>
      </div>
    </div>
  );
}
```

---

### Plain JavaScript

```html
<!DOCTYPE html>
<html>
<head>
  <title>Network Stats</title>
</head>
<body>
  <div id="stats"></div>

  <script>
    async function updateStats() {
      const response = await fetch('http://localhost:4000/api/stats');
      const stats = await response.json();

      document.getElementById('stats').innerHTML = `
        <h2>Network Statistics</h2>
        <p>Nodes Online: ${stats.nodesOnline.toLocaleString()}</p>
        <p>Builds Queued: ${stats.buildsQueued.toLocaleString()}</p>
        <p>Active Builds: ${stats.activeBuilds.toLocaleString()}</p>
        <p>Builds Today: ${stats.buildsToday.toLocaleString()}</p>
        <p>Total Builds: ${(stats.totalBuilds / 1_000_000).toFixed(1)}M</p>
      `;
    }

    updateStats();
    setInterval(updateStats, 10000); // Update every 10 seconds
  </script>
</body>
</html>
```

---

## Tips and Best Practices

### Error Handling

Always check HTTP status codes and handle errors gracefully:

```bash
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -H "X-API-Key: dev-key-12345" \
  http://localhost:4000/api/builds/V1bN8xK9rLmQ/status)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" != "200" ]; then
  echo "Error: HTTP $HTTP_CODE"
  echo "$BODY" | jq -r '.error'
  exit 1
fi
```

---

### Logging

Include timestamps and context in all log messages:

```bash
log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1"
}

log "Submitting build..."
log "Build ID: $BUILD_ID"
log "Status: $STATUS"
```

---

### Retry Logic

Implement exponential backoff for network failures:

```bash
retry_with_backoff() {
  local max_attempts=5
  local timeout=1
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    if "$@"; then
      return 0
    fi

    echo "Attempt $attempt failed. Retrying in ${timeout}s..."
    sleep $timeout
    attempt=$((attempt + 1))
    timeout=$((timeout * 2))
  done

  return 1
}

retry_with_backoff curl -H "X-API-Key: dev-key-12345" \
  http://localhost:4000/api/builds/active
```

---

### Security

Never log or expose API keys or access tokens:

```bash
# BAD
echo "Using API key: $API_KEY"

# GOOD
echo "Using API key: ${API_KEY:0:8}..."
```

Store credentials in environment variables:

```bash
export CONTROLLER_API_KEY="dev-key-12345"
export CONTROLLER_URL="http://localhost:4000"

curl -H "X-API-Key: $CONTROLLER_API_KEY" \
  "$CONTROLLER_URL/api/builds"
```

---

## Next Steps

- See [API.md](./API.md) for complete endpoint reference
- See [ERRORS.md](./ERRORS.md) for detailed error handling guide
- See [../../docs/INDEX.md](../../docs/INDEX.md) for architecture documentation

---

*Last updated: 2024-01-28*
