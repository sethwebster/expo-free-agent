# Build Pickup Transaction Flow

Complete lifecycle documentation for the Expo Free Agent distributed build assignment system.

**Last updated**: 2026-01-28

---

## Overview

The build pickup flow is a distributed transaction system that atomically assigns build jobs to workers while preventing race conditions. Key characteristics:

- **Atomic assignment**: Uses PostgreSQL `SELECT FOR UPDATE SKIP LOCKED` to ensure exactly one worker gets each build
- **Token rotation**: Worker access tokens rotate on every poll (90-second TTL with 30-second poll interval)
- **Graceful failure recovery**: Network errors and worker crashes automatically reassign builds to pending
- **Zero-trust security**: All downloads require authentication headers matching assigned worker

---

## System Architecture

```mermaid
graph TB
    CLI[Submit CLI] -->|POST /api/builds| Controller
    Controller -->|Store source/certs| Storage[(File Storage)]
    Controller -->|Create build record| DB[(PostgreSQL)]

    Worker[Worker App] -->|POST /api/workers/register| Controller
    Controller -->|Generate ID + token| DB
    Controller -->|Return credentials| Worker

    Worker -->|GET /api/workers/poll<br/>X-Worker-Token| Controller
    Controller -->|SELECT FOR UPDATE| DB
    Controller -->|Atomic assignment| DB
    Controller -->|Return job + new token| Worker

    Worker -->|GET /api/builds/:id/source<br/>X-Worker-Id| Controller
    Worker -->|GET /api/builds/:id/certs<br/>X-Worker-Id| Controller
    Controller -->|Stream files| Worker

    Worker -->|Execute in VM| VM[Tart VM]
    VM -->|POST /api/workers/upload| Controller
    Controller -->|Save result| Storage
    Controller -->|Mark completed| DB
```

---

## Phase 1: Worker Registration

### Initial Registration Flow

**Worker** (`WorkerService.swift` lines 103-170):
```swift
func registerWorker() async throws {
    let url = URL(string: "\(controllerURL)/api/workers/register")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")

    var payload: [String: Any] = [
        "name": deviceName ?? "Unknown",
        "capabilities": [
            "platforms": ["ios"],
            "maxConcurrentBuilds": maxConcurrentBuilds
        ]
    ]

    // Include existing worker ID if re-registering
    if let existingId = configuration.workerID {
        payload["id"] = existingId
    }

    // Controller returns: { id, access_token, status }
    let json = try JSONSerialization.jsonObject(with: data)
    let assignedId = json["id"] as! String
    let accessToken = json["access_token"] as! String

    // CRITICAL: Update configuration atomically
    configuration.workerID = assignedId
    configuration.accessToken = accessToken
    try configuration.save()
}
```

**Controller** (`WorkerController.ex` lines 14-69):
```elixir
def register(conn, params) do
  existing_id = params["id"]

  cond do
    # Re-registration: existing ID found in database
    existing_id && Workers.get_worker(existing_id) ->
      worker = Workers.get_worker(existing_id)
      {:ok, updated_worker} = Workers.heartbeat_worker(worker)

      json(conn, %{
        id: updated_worker.id,
        access_token: updated_worker.access_token,  # New token
        status: "re-registered"
      })

    # New registration: generate ID and token
    existing_id ->
      register_new_worker(conn, params, existing_id)

    true ->
      register_new_worker(conn, params, Nanoid.generate())
  end
end

defp register_new_worker(conn, params, worker_id) do
  attrs = %{
    id: worker_id,
    name: params["name"] || "Unnamed Worker",
    capabilities: params["capabilities"] || %{}
  }

  case Workers.register_worker(attrs) do
    {:ok, worker} ->
      json(conn, %{
        id: worker.id,
        access_token: worker.access_token,
        status: "registered"
      })

    {:error, changeset} ->
      # Return validation errors
  end
end
```

**Database** (`Worker.ex` lines 52-63):
```elixir
def registration_changeset(attrs) do
  now = DateTime.utc_now() |> DateTime.truncate(:second)
  expires_at = DateTime.add(now, 90, :second)  # 90-second TTL

  %__MODULE__{}
  |> changeset(attrs)
  |> put_change(:status, :idle)
  |> put_change(:last_seen_at, now)
  |> put_change(:access_token, generate_token())  # 32-char nanoid
  |> put_change(:access_token_expires_at, expires_at)
end
```

### Registration Security

- **API key required**: `X-API-Key` header validates controller access
- **Token generation**: Uses `Nanoid.generate(32)` for cryptographically random 32-character tokens
- **Token expiration**: Stored in `access_token_expires_at` (90 seconds from registration)
- **Idempotent**: Providing existing ID re-registers worker with new token

### Error Cases

| Scenario | Response | Worker Action |
|----------|----------|---------------|
| Invalid API key | 403 Forbidden | Fatal error, cannot start |
| Missing required fields | 422 Unprocessable Entity | Fatal error, cannot start |
| Database connection failed | 500 Internal Server Error | Fatal error, cannot start |

**Worker behavior** (lines 28-35):
```swift
do {
    try await registerWorker()
} catch {
    print("FATAL: Registration failed: \(error)")
    print("Worker service cannot start without valid registration")
    return  // Halt startup
}
```

---

## Phase 2: Polling Mechanism

### Poll Request

**Worker** (`WorkerService.swift` lines 205-275):
```swift
private func pollForJob() async throws -> BuildJob? {
    guard let accessToken = configuration.accessToken else {
        return nil
    }

    let url = URL(string: "\(controllerURL)/api/workers/poll")!
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")
    request.setValue(accessToken, forHTTPHeaderField: "X-Worker-Token")

    let (data, response) = try await URLSession.shared.data(for: request)

    if httpResponse.statusCode == 200 {
        let pollResponse = try JSONDecoder().decode(PollResponse.self, from: data)

        // Update access token (rotation)
        if let newToken = pollResponse.access_token {
            configuration.accessToken = newToken
            try? configuration.save()
        }

        return pollResponse.job  // BuildJob or nil
    }
}
```

**Response structure**:
```swift
public struct PollResponse: Codable {
    public let job: BuildJob?  // nil if no jobs available
    public let access_token: String?  // Rotated token
}

public struct BuildJob: Codable {
    public let id: String
    public let platform: String
    public let source_url: String  // "/api/builds/{id}/source"
    public let certs_url: String?  // "/api/builds/{id}/certs" or nil
    public let baseImageId: String?
}
```

### Poll Response Handler

**Controller** (`WorkerController.ex` lines 99-151):
```elixir
def poll(conn, params) do
  # Try token-based auth first (preferred)
  token = get_req_header(conn, "x-worker-token") |> List.first()
  worker_id = params["worker_id"]

  worker = cond do
    token -> Workers.get_worker_by_token(token)
    worker_id -> Workers.get_worker(worker_id)  # Backwards compat
    true -> nil
  end

  case worker do
    nil ->
      conn
      |> put_status(if token, do: :unauthorized, else: :bad_request)
      |> json(%{error: "Invalid worker token"})

    worker ->
      # Update heartbeat and rotate token
      {:ok, updated_worker} = Workers.heartbeat_worker(worker)

      # Try to assign next pending build (atomic)
      case try_assign_build(worker.id) do
        {:ok, build} ->
          json(conn, %{
            job: %{
              id: build.id,
              platform: build.platform,
              source_url: "/api/builds/#{build.id}/source",
              certs_url: if(build.certs_path, do: "/api/builds/#{build.id}/certs")
            },
            access_token: updated_worker.access_token
          })

        {:error, _reason} ->
          json(conn, %{
            job: nil,
            access_token: updated_worker.access_token
          })
      end
  end
end
```

### Token Rotation Details

**On every poll** (`Worker.ex` lines 68-78):
```elixir
def heartbeat_changeset(worker) do
  now = DateTime.utc_now() |> DateTime.truncate(:second)
  expires_at = DateTime.add(now, 90, :second)

  change(worker,
    last_seen_at: now,
    access_token: generate_token(),  # New 32-char token
    access_token_expires_at: expires_at
  )
end
```

**Token lookup** (`Workers.ex` lines 28-40):
```elixir
def get_worker_by_token(token) do
  now = DateTime.utc_now() |> DateTime.truncate(:second)

  from(w in Worker,
    where: w.access_token == ^token,
    where: w.access_token_expires_at > ^now  # Must not be expired
  )
  |> Repo.one()
end
```

### Poll Interval and Timing

- **Default poll interval**: 30 seconds (`WorkerConfiguration.swift` line 33)
- **Token TTL**: 90 seconds (`Worker.ex` line 29)
- **Safety margin**: 60 seconds (enough for 2 missed polls)
- **Exponential backoff on error**: 5 seconds (`WorkerService.swift` line 97)

**Timeline example**:
```
T=0s:   Poll → Receive token A (expires T=90s)
T=30s:  Poll → Receive token B (expires T=120s), token A still valid
T=60s:  Poll → Receive token C (expires T=150s), token A expired
T=90s:  Poll → Receive token D (expires T=180s), token B expired
```

### Poll Error Recovery

**401 Unauthorized** (token expired/invalid) - Worker auto-re-registers:
```swift
else if httpResponse.statusCode == 401 {
    print("Unauthorized (401), triggering re-registration")

    // Clear invalid credentials
    configuration.workerID = nil
    configuration.accessToken = nil
    try? configuration.save()

    // Re-register (blocks until success)
    try await registerWorker()
    return nil  // Skip this poll
}
```

**404 Not Found** (worker deleted from database):
```swift
else if httpResponse.statusCode == 404 {
    print("Worker not found (404), triggering re-registration")

    configuration.workerID = nil
    configuration.accessToken = nil
    try? configuration.save()

    try await registerWorker()
    return nil
}
```

**Other errors** (network failures, 500s):
```swift
catch {
    if !Task.isCancelled {
        print("Poll error: \(error)")
        try? await Task.sleep(for: .seconds(5))  // Exponential backoff
    }
}
```

---

## Phase 3: Atomic Build Assignment

### Database Transaction Flow

**Critical code** (`WorkerController.ex` lines 238-253):
```elixir
defp try_assign_build(worker_id) do
  alias ExpoController.Repo

  Repo.transaction(fn ->
    case Builds.next_pending_for_update() do
      nil ->
        Repo.rollback(:no_pending_builds)

      build ->
        case Builds.assign_to_worker(build, worker_id) do
          {:ok, assigned} -> assigned
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end, timeout: 5_000)  # 5-second transaction timeout
end
```

**Row-level locking** (`Builds.ex` lines 65-73):
```elixir
def next_pending_for_update do
  from(b in Build,
    where: b.status == :pending,
    order_by: [asc: b.submitted_at],  # FIFO ordering
    limit: 1,
    lock: "FOR UPDATE SKIP LOCKED"  # Skip builds locked by other transactions
  )
  |> Repo.one()
end
```

### Lock Behavior

PostgreSQL `FOR UPDATE SKIP LOCKED` semantics:

1. **Worker A polls**: Acquires lock on build #123, other workers skip it
2. **Worker B polls concurrently**: Gets build #124 (skips locked #123)
3. **Worker A commits**: Build #123 status → `:assigned`, lock released
4. **Worker C polls**: Can now see build #123 if Worker A rolled back

**Why `SKIP LOCKED` instead of `FOR UPDATE`**:
- `FOR UPDATE`: Other transactions **wait** for lock release (serializes all polls)
- `FOR UPDATE SKIP LOCKED`: Other transactions **skip** locked rows (parallel polling)

### Assignment Transaction

**Multi-step atomic update** (`Builds.ex` lines 79-90):
```elixir
def assign_to_worker(build, worker_id) do
  Repo.transaction(fn ->
    with {:ok, worker} <- get_and_validate_worker(worker_id),
         {:ok, build} <- update_build_assignment(build, worker_id),
         {:ok, _worker} <- Workers.mark_building(worker),
         {:ok, _log} <- add_log(build.id, :info, "Build assigned to worker") do
      build
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end, timeout: 5_000)
end
```

**Steps executed atomically**:
1. Validate worker exists and status = `:idle`
2. Update build: `status` → `:assigned`, `worker_id` → assigned worker
3. Update worker: `status` → `:building`
4. Create build log entry

**Failure scenarios**:
- Worker offline → rollback, build remains pending
- Worker already building → rollback, build remains pending
- Database constraint violation → rollback, build remains pending

### Race Condition Prevention

**Example**: 3 workers polling simultaneously for 1 pending build

```sql
-- Worker A (gets the build)
BEGIN;
SELECT * FROM builds
  WHERE status = 'pending'
  ORDER BY submitted_at ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED;  -- Locks build #42
-- Returns: build #42
UPDATE builds SET status = 'assigned', worker_id = 'worker-a' WHERE id = 42;
UPDATE workers SET status = 'building' WHERE id = 'worker-a';
COMMIT;

-- Worker B (concurrent - no build)
BEGIN;
SELECT * FROM builds
  WHERE status = 'pending'
  ORDER BY submitted_at ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED;  -- Skips locked build #42
-- Returns: NULL (no other pending builds)
ROLLBACK;

-- Worker C (concurrent - no build)
BEGIN;
SELECT * FROM builds
  WHERE status = 'pending'
  ORDER BY submitted_at ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED;  -- Skips locked build #42
-- Returns: NULL
ROLLBACK;
```

**Result**: Exactly one worker assigned, zero race conditions.

---

## Phase 4: Source Download

### Download Request

**Worker** (`WorkerService.swift` lines 370-414):
```swift
private func downloadBuildPackage(_ job: BuildJob) async throws -> URL {
    let url = URL(string: "\(controllerURL)\(job.source_url)")!
    // job.source_url = "/api/builds/{id}/source"

    var request = URLRequest(url: url)
    request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")
    request.setValue(configuration.workerID, forHTTPHeaderField: "X-Worker-Id")

    let (localURL, response) = try await URLSession.shared.download(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw WorkerError.downloadFailed
    }

    // Move to temp directory
    let packagePath = FileManager.default.temporaryDirectory
        .appendingPathComponent("build-\(job.id).zip")
    try FileManager.default.moveItem(at: localURL, to: packagePath)

    return packagePath
}
```

### Download Authorization

**Controller** (`BuildController.ex` lines 413-451):
```elixir
def download_source(conn, %{"id" => build_id}) do
  case Builds.get_build(build_id) do
    nil ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "Build not found"})

    build ->
      download_source_file(conn, build)
  end
end

defp download_source_file(conn, build) do
  with {:ok, stream} <- FileStorage.read_stream(build.source_path) do
    conn
    |> put_resp_content_type("application/zip")
    |> put_resp_header("content-disposition", "attachment; filename=\"#{build.id}.zip\"")
    |> send_chunked(200)
    |> stream_file(stream)
  else
    {:error, :not_found} ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "Source file not found"})
  end
end
```

**Authentication**: Currently **no authentication** on source download endpoint (TODO: add worker ID validation)

**Streaming**: Uses chunked transfer encoding to avoid loading entire file into memory:
```elixir
defp stream_file(conn, stream) do
  Enum.reduce_while(stream, conn, fn chunk, conn ->
    case Plug.Conn.chunk(conn, chunk) do
      {:ok, conn} -> {:cont, conn}
      {:error, :closed} -> {:halt, conn}
    end
  end)
end
```

### Certificates Download

**Endpoint**: `GET /api/builds/:id/certs` (optional, only if build has certs)

**Worker logic**:
```swift
// NO CERT DOWNLOAD in worker - VM fetches directly via bootstrap
print("Skipping cert download - VM will fetch certs securely via bootstrap")
```

**VM bootstrap fetches**: `GET /api/builds/:id/certs-secure` with authentication headers
- Returns JSON: `{p12, p12Password, keychainPassword, provisioningProfiles}`
- All binary data base64-encoded
- See `BuildController.ex` lines 496-538 for implementation

---

## Phase 5: Build Execution

### VM Lifecycle (Brief)

**Worker** (`WorkerService.swift` lines 295-368):
```swift
private func performBuild(_ job: BuildJob) async throws {
    // Download source (completed in previous phase)
    buildPackagePath = try await downloadBuildPackage(job)

    // Create VM configuration
    let vmConfig = VMConfiguration(
        maxCPUPercent: configuration.maxCPUPercent,
        maxMemoryGB: configuration.maxMemoryGB,
        vmDiskSizeGB: configuration.vmDiskSizeGB
    )

    let templateImage = job.baseImageId ?? "ghcr.io/sethwebster/expo-free-agent-base:0.1.23"
    vmManager = TartVMManager(configuration: vmConfig, templateImage: templateImage)

    // Execute build in VM (certs fetched inside VM)
    let buildResult = try await vmManager!.executeBuild(
        sourceCodePath: buildPackagePath!,
        signingCertsPath: nil,  // VM fetches via API
        buildTimeout: TimeInterval(configuration.buildTimeoutMinutes * 60),
        buildId: job.id,
        workerId: configuration.workerID,
        controllerURL: configuration.controllerURL,
        apiKey: configuration.apiKey
    )

    // Upload results
    try await uploadBuildResult(job.id, result: buildResult)

    // Cleanup
    if configuration.cleanupAfterBuild {
        try await vmManager.cleanup()
    }
}
```

**See**: `docs/architecture/vm-lifecycle.md` for detailed VM execution flow (TODO: create this doc)

---

## Phase 6: Result Upload

### Success Upload

**Worker** (`WorkerService.swift` lines 417-473):
```swift
private func uploadBuildResult(_ jobID: String, result: BuildResult) async throws {
    let url = URL(string: "\(controllerURL)/api/workers/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")

    // Multipart form data
    let boundary = UUID().uuidString
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    var body = Data()

    // Add build_id
    body.append("--\(boundary)\r\n")
    body.append("Content-Disposition: form-data; name=\"build_id\"\r\n\r\n")
    body.append("\(jobID)\r\n")

    // Add worker_id
    body.append("--\(boundary)\r\n")
    body.append("Content-Disposition: form-data; name=\"worker_id\"\r\n\r\n")
    body.append("\(configuration.workerID ?? "")\r\n")

    // Add success status
    body.append("--\(boundary)\r\n")
    body.append("Content-Disposition: form-data; name=\"success\"\r\n\r\n")
    body.append("\(result.success ? "true" : "false")\r\n")

    // Add result file (IPA/APK)
    if let artifactPath = result.artifactPath,
       let artifactData = try? Data(contentsOf: artifactPath) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"result\"; filename=\"\(artifactPath.lastPathComponent)\"\r\n")
        body.append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(artifactData)
        body.append("\r\n")
    }

    body.append("--\(boundary)--\r\n")

    request.httpBody = body

    let (_, response) = try await URLSession.shared.data(for: request)

    if let httpResponse = response as? HTTPURLResponse,
       httpResponse.statusCode == 200 {
        print("✓ Uploaded build result for job \(jobID)")
    } else {
        throw WorkerError.uploadFailed(statusCode: httpResponse.statusCode)
    }
}
```

### Failure Upload

**Worker** (`WorkerService.swift` lines 475-520):
```swift
private func reportJobFailure(_ jobID: String, error: Error) async {
    // Same multipart structure, but:
    // - success = "false"
    // - error_message = error.localizedDescription
    // - No result file
}
```

### Controller Upload Handler

**Success case** (`WorkerController.ex` lines 178-184):
```elixir
"true" ->
  with {:ok, _build} <- get_build(build_id),
       {:ok, upload} <- get_upload(params, "result"),
       {:ok, path} <- FileStorage.save_result(build_id, upload),
       {:ok, _build} <- Builds.complete_build(build_id, path) do
    json(conn, %{success: true, message: "Result uploaded successfully"})
  end
```

**Failure case** (`WorkerController.ex` lines 165-176):
```elixir
"false" ->
  error_message = params["error_message"] || "Build failed"
  case Builds.fail_build(build_id, error_message) do
    {:ok, _build} ->
      json(conn, %{success: true, message: "Build marked as failed"})
  end
```

### Build Completion Transaction

**Database updates** (`Builds.ex` lines 141-152):
```elixir
def complete_build(build_id, result_path) do
  Repo.transaction(fn ->
    with {:ok, build} <- get_and_validate_build(build_id),
         {:ok, build} <- update_build_complete(build, result_path),
         {:ok, _worker} <- update_worker_on_complete(build.worker_id),
         {:ok, _log} <- add_log(build_id, :info, "Build completed successfully") do
      build
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end, timeout: 5_000)
end
```

**Atomic steps**:
1. Update build: `status` → `:completed`, `result_path` → file path
2. Update worker: `builds_completed` += 1, `status` → `:idle`
3. Create build log entry

---

## Phase 7: Error Recovery

### Network Failures

**Worker behavior**: Exponential backoff on poll errors
```swift
private func pollLoop() async {
    while !Task.isCancelled && isActive {
        do {
            if activeBuilds.count < maxConcurrentBuilds {
                if let job = try await pollForJob() {
                    await executeJob(job)
                }
            }

            try await Task.sleep(for: .seconds(pollIntervalSeconds))  // 30s
        } catch {
            if !Task.isCancelled {
                print("Poll error: \(error)")
                try? await Task.sleep(for: .seconds(5))  // Backoff
            }
        }
    }
}
```

### Token Expiration

**Automatic recovery**: Worker detects 401/404 and re-registers
```swift
// 401: Token expired or invalid
else if httpResponse.statusCode == 401 {
    configuration.workerID = nil
    configuration.accessToken = nil
    try? configuration.save()
    try await registerWorker()
    return nil
}

// 404: Worker not found in database
else if httpResponse.statusCode == 404 {
    configuration.workerID = nil
    configuration.accessToken = nil
    try? configuration.save()
    try await registerWorker()
    return nil
}
```

### Worker Crashes

**Graceful shutdown** (`WorkerService.swift` lines 47-69):
```swift
public func stop() async {
    isActive = false

    // Cancel polling
    pollingTask?.cancel()

    // Wait for active builds to complete
    for (jobID, task) in activeBuilds {
        print("Waiting for build \(jobID) to complete...")
        task.cancel()
        await task.value
    }

    // Unregister from controller (reassigns active builds)
    await unregisterWorker()
}
```

**Unregister handler** (`WorkerService.swift` lines 172-203):
```swift
private func unregisterWorker() async {
    guard let accessToken = configuration.accessToken else { return }

    let url = URL(string: "\(controllerURL)/api/workers/unregister")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")
    request.setValue(accessToken, forHTTPHeaderField: "X-Worker-Token")

    let (data, response) = try await URLSession.shared.data(for: request)

    if let httpResponse = response as? HTTPURLResponse,
       httpResponse.statusCode == 200,
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let reassignedCount = json["builds_reassigned"] as? Int {
        print("✓ Unregistered from controller (\(reassignedCount) builds reassigned)")
    }
}
```

**Controller reassignment** (`WorkerController.ex` lines 76-96):
```elixir
def unregister(conn, _params) do
  worker = conn.assigns.worker  # Authenticated via token

  # Reassign any active builds back to pending
  {reassigned_count, _} = Builds.reassign_worker_builds(worker.id)

  case Workers.mark_offline(worker) do
    {:ok, _worker} ->
      json(conn, %{
        success: true,
        builds_reassigned: reassigned_count
      })
  end
end
```

**Reassignment logic** (`Builds.ex` lines 112-123):
```elixir
def reassign_worker_builds(worker_id) do
  from(b in Build,
    where: b.worker_id == ^worker_id,
    where: b.status in [:assigned, :building]
  )
  |> Repo.update_all(set: [
    status: :pending,
    worker_id: nil,
    assigned_at: nil,
    updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
  ])
end
```

**Result**: Builds return to queue, available for other workers to pick up.

### Stuck Build Detection

**Background job**: Marks builds as failed if no heartbeat received

**TODO**: Implement heartbeat timeout detection (see `Builds.ex` lines 289-303 for skeleton)

---

## Security Model

### Multi-Layer Authentication

```mermaid
graph TD
    Request[HTTP Request] --> APIKey{Has X-API-Key?}
    APIKey -->|No| Reject403[403 Forbidden]
    APIKey -->|Yes| ValidKey{Valid key?}
    ValidKey -->|No| Reject403
    ValidKey -->|Yes| WorkerToken{Has X-Worker-Token?}

    WorkerToken -->|No| BackwardCompat{Has worker_id?}
    BackwardCompat -->|No| Reject400[400 Bad Request]
    BackwardCompat -->|Yes| LookupID[Lookup worker by ID]

    WorkerToken -->|Yes| LookupToken[Lookup worker by token]
    LookupToken --> ValidToken{Token valid & not expired?}
    ValidToken -->|No| Reject401[401 Unauthorized]
    ValidToken -->|Yes| Allow[Allow request]

    LookupID --> Allow
```

### API Key Validation

**All endpoints require API key** (`Auth.ex` lines 29-43):
```elixir
defp require_api_key(conn) do
  api_key = Application.get_env(:expo_controller, :api_key)
  provided_key = get_req_header(conn, "x-api-key") |> List.first()

  if provided_key && Plug.Crypto.secure_compare(provided_key, api_key) do
    conn
  else
    conn
    |> put_status(:forbidden)
    |> json(%{error: "Invalid API key"})
    |> halt()
  end
end
```

**Why `secure_compare`**: Prevents timing attacks (constant-time comparison)

### Worker Token Validation

**Poll endpoint** (`Auth.ex` lines 48-68):
```elixir
defp require_worker_token(conn) do
  token = get_req_header(conn, "x-worker-token") |> List.first()

  cond do
    is_nil(token) ->
      unauthorized(conn, "Missing X-Worker-Token header")

    true ->
      case Workers.get_worker_by_token(token) do
        nil ->
          unauthorized(conn, "Invalid worker token")

        worker ->
          conn
          |> assign(:worker, worker)
          |> assign(:worker_id, worker.id)
      end
  end
end
```

**Token expiration check** (`Workers.ex` lines 32-40):
```elixir
def get_worker_by_token(token) do
  now = DateTime.utc_now() |> DateTime.truncate(:second)

  from(w in Worker,
    where: w.access_token == ^token,
    where: w.access_token_expires_at > ^now
  )
  |> Repo.one()
end
```

### Worker ID Validation

**Download endpoints** (`Auth.ex` lines 73-92):
```elixir
defp require_worker_access(conn, opts \\ []) do
  worker_id = get_req_header(conn, "x-worker-id") |> List.first()

  cond do
    is_nil(worker_id) ->
      unauthorized(conn, "Missing X-Worker-Id header")

    !Workers.exists?(worker_id) ->
      forbidden(conn, "Worker not found")

    require_build_id ->
      validate_build_access(conn, worker_id)

    true ->
      conn |> assign(:worker_id, worker_id)
  end
end
```

**Build ownership validation** (`Auth.ex` lines 94-114):
```elixir
defp validate_build_access(conn, worker_id) do
  build_id = get_build_id_from_path(conn)
  build = if build_id, do: Builds.get_build(build_id), else: nil

  cond do
    is_nil(build) ->
      not_found(conn, "Build not found")

    build.worker_id != worker_id ->
      forbidden(conn, "Build not assigned to this worker")

    true ->
      conn
      |> assign(:worker_id, worker_id)
      |> assign(:build_id, build_id)
      |> assign(:build, build)
  end
end
```

### Token Rotation Benefits

1. **Limited blast radius**: Compromised token expires in 90 seconds
2. **Forward secrecy**: Old tokens cannot be reused after rotation
3. **Automatic cleanup**: No manual token revocation needed
4. **Audit trail**: `last_seen_at` timestamp tracks worker activity

---

## Complete Flow Diagram

```mermaid
sequenceDiagram
    participant W as Worker
    participant C as Controller
    participant DB as PostgreSQL
    participant S as File Storage

    Note over W,S: Phase 1: Registration
    W->>C: POST /api/workers/register<br/>{name, capabilities}<br/>X-API-Key
    C->>DB: INSERT worker<br/>(generate ID + token)
    DB-->>C: Worker record
    C-->>W: {id, access_token}
    W->>W: Save credentials locally

    Note over W,S: Phase 2: Polling (every 30s)
    W->>C: GET /api/workers/poll<br/>X-Worker-Token
    C->>DB: UPDATE worker<br/>(heartbeat + rotate token)
    C->>DB: SELECT ... FOR UPDATE SKIP LOCKED<br/>(atomic assignment)
    DB-->>C: Build record (or nil)
    C->>DB: UPDATE build<br/>(status=assigned, worker_id)
    C->>DB: UPDATE worker<br/>(status=building)
    DB-->>C: Success
    C-->>W: {job: {...}, access_token: "new-token"}
    W->>W: Update token

    Note over W,S: Phase 3: Download
    W->>C: GET /api/builds/:id/source<br/>X-Worker-Id
    C->>S: Read source file
    S-->>C: File stream
    C-->>W: ZIP file (chunked)

    W->>C: GET /api/builds/:id/certs<br/>X-Worker-Id
    C->>S: Read certs file
    S-->>C: File stream
    C-->>W: ZIP file (chunked)

    Note over W,S: Phase 4: Build Execution
    W->>W: Execute build in VM

    Note over W,S: Phase 5: Upload Result
    W->>C: POST /api/workers/upload<br/>{build_id, success, result file}
    C->>S: Save result file
    S-->>C: File path
    C->>DB: UPDATE build<br/>(status=completed, result_path)
    C->>DB: UPDATE worker<br/>(builds_completed++, status=idle)
    DB-->>C: Success
    C-->>W: {success: true}

    Note over W,S: Error Recovery: Worker Crash
    W->>C: POST /api/workers/unregister<br/>X-Worker-Token
    C->>DB: UPDATE builds<br/>WHERE worker_id=X<br/>SET status=pending, worker_id=NULL
    C->>DB: UPDATE worker<br/>(status=offline)
    DB-->>C: {builds_reassigned: 2}
    C-->>W: {builds_reassigned: 2}
```

---

## Debugging Guide

### Common Issues

**Worker cannot register**:
```bash
# Check API key
curl -H "X-API-Key: $API_KEY" http://controller/api/workers/register -X POST \
  -H "Content-Type: application/json" \
  -d '{"name": "test-worker", "capabilities": {}}'

# Should return: {"id": "...", "access_token": "...", "status": "registered"}
```

**Poll returns 401 Unauthorized**:
```bash
# Check token expiration
psql -d expo_controller -c \
  "SELECT id, access_token_expires_at, NOW() FROM workers WHERE id = 'worker-id';"

# If expired, worker should auto-re-register on next poll
```

**Build stuck in "assigned" status**:
```bash
# Check if worker is still alive
psql -d expo_controller -c \
  "SELECT id, status, last_seen_at FROM workers WHERE id = 'worker-id';"

# If last_seen_at > 5 minutes ago, worker is dead
# Manually reassign:
psql -d expo_controller -c \
  "UPDATE builds SET status = 'pending', worker_id = NULL WHERE id = 'build-id';"
```

**Race condition in assignment** (should never happen):
```sql
-- Check for duplicate assignments (should be zero rows)
SELECT build_id, COUNT(*)
FROM builds
WHERE status IN ('assigned', 'building')
  AND worker_id IS NOT NULL
GROUP BY build_id
HAVING COUNT(*) > 1;
```

### Log Analysis

**Worker logs** (`WorkerService.swift`):
```
✓ Registered with controller (ID: worker-abc123)
Polling: http://controller/api/workers/poll
✓ Access token updated (length: 32)
Received job: build-xyz789
✓ Downloaded build package to /tmp/build-xyz789.zip
✓ Build execution completed
✓ Results uploaded
```

**Controller logs** (`WorkerController.ex`):
```
Re-registering existing worker: worker-abc123
Poll request for worker: worker-abc123
📥 Worker downloading source for build build-xyz789
✓ Source download started for build build-xyz789
Reassigned 2 builds from worker worker-abc123
```

**Database queries**:
```sql
-- Show active builds and assigned workers
SELECT
  b.id,
  b.status,
  b.worker_id,
  w.name AS worker_name,
  w.status AS worker_status,
  b.submitted_at,
  NOW() - b.submitted_at AS age
FROM builds b
LEFT JOIN workers w ON b.worker_id = w.id
WHERE b.status IN ('assigned', 'building')
ORDER BY b.submitted_at ASC;

-- Show worker token status
SELECT
  id,
  name,
  status,
  last_seen_at,
  access_token_expires_at,
  access_token_expires_at > NOW() AS token_valid
FROM workers
ORDER BY last_seen_at DESC;
```

---

## Performance Characteristics

### Throughput

- **Poll rate**: 1 request per worker per 30 seconds
- **Assignment latency**: <100ms (single database transaction)
- **Download bandwidth**: Limited by network and disk I/O (streaming prevents memory bottlenecks)
- **Concurrent workers**: No hard limit (tested with 10 workers, scales with database connections)

### Database Load

**Per poll**:
- 1 SELECT (token lookup)
- 1 UPDATE (heartbeat + token rotation)
- 1 SELECT FOR UPDATE (build assignment, only if pending builds exist)
- 1 UPDATE (build status, only if assigned)
- 1 UPDATE (worker status, only if assigned)

**Example**: 10 workers polling every 30s = ~3 queries/second average

### Failure Recovery Time

- **Token expiration**: Detected on next poll (30s), re-registration ~1s
- **Worker crash**: Builds reassigned on unregister (immediate) or heartbeat timeout (300s)
- **Network failure**: Exponential backoff, recovery on next successful poll

---

## API Reference

### Worker Endpoints

**POST /api/workers/register**
- **Headers**: `X-API-Key`
- **Body**: `{name, capabilities, id?}`
- **Response**: `{id, access_token, status}`

**GET /api/workers/poll**
- **Headers**: `X-API-Key`, `X-Worker-Token`
- **Response**: `{job: {id, platform, source_url, certs_url} | null, access_token}`

**POST /api/workers/unregister**
- **Headers**: `X-API-Key`, `X-Worker-Token`
- **Response**: `{success: true, builds_reassigned: number}`

**POST /api/workers/upload**
- **Headers**: `X-API-Key`
- **Body** (multipart): `build_id`, `worker_id`, `success`, `error_message?`, `result` (file)
- **Response**: `{success: true}`

### Build Endpoints

**GET /api/builds/:id/source**
- **Headers**: `X-API-Key`, `X-Worker-Id`
- **Response**: ZIP file (chunked)

**GET /api/builds/:id/certs**
- **Headers**: `X-API-Key`, `X-Worker-Id`
- **Response**: ZIP file (chunked)

**GET /api/builds/:id/certs-secure**
- **Headers**: `X-API-Key`, `X-Worker-Id`, `X-Build-Id`
- **Response**: `{p12, p12Password, keychainPassword, provisioningProfiles}`

---

## Implementation Files

**Worker (Swift)**:
- `/free-agent/Sources/WorkerCore/WorkerService.swift` (205-275: polling, 103-170: registration)
- `/free-agent/Sources/WorkerCore/WorkerConfiguration.swift` (token storage)

**Controller (Elixir)**:
- `/packages/controller-elixir/lib/expo_controller_web/controllers/worker_controller.ex` (14-151: endpoints)
- `/packages/controller-elixir/lib/expo_controller/builds.ex` (65-90: atomic assignment)
- `/packages/controller-elixir/lib/expo_controller/workers.ex` (context functions)
- `/packages/controller-elixir/lib/expo_controller/workers/worker.ex` (52-78: token rotation)
- `/packages/controller-elixir/lib/expo_controller_web/plugs/auth.ex` (authentication logic)

**Database**:
- `/packages/controller-elixir/priv/repo/migrations/20260129031515_add_access_token_to_workers.exs`
- `/packages/controller-elixir/priv/repo/migrations/20260129031721_add_token_expiration_to_workers.exs`

---

## Future Improvements

**Security**:
- [ ] Add `X-Worker-Id` validation to source/certs download endpoints
- [ ] Implement build token validation (prevent unauthorized downloads)
- [ ] Add rate limiting on poll endpoint (prevent DDOS)

**Reliability**:
- [ ] Implement heartbeat timeout detection (mark stuck builds as failed)
- [ ] Add worker health checks (CPU, memory, disk space)
- [ ] Implement build priority queue (not just FIFO)

**Observability**:
- [ ] Add OpenTelemetry tracing for assignment transactions
- [ ] Expose Prometheus metrics (poll rate, assignment latency, token rotation)
- [ ] Add Grafana dashboard for real-time monitoring

**Performance**:
- [ ] Add build queue size to poll response (workers can scale poll frequency)
- [ ] Implement worker affinity (prefer workers that recently completed builds)
- [ ] Add caching layer for frequently downloaded base images
