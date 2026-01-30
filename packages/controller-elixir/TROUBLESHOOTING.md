# Troubleshooting Guide

Common errors, debugging techniques, and solutions for Elixir controller issues.

---

## Quick Diagnosis

### Health Check

```bash
# Check if server is running
curl http://localhost:4000/health

# Check stats endpoint
curl http://localhost:4000/api/stats

# Check database connectivity
psql -U expo -d expo_controller_dev -c "SELECT count(*) FROM builds;"
```

### Service Status

```bash
# Check if service is running
sudo systemctl status expo-controller

# View recent logs
sudo journalctl -u expo-controller -n 100

# Follow logs live
sudo journalctl -u expo-controller -f
```

---

## Common Errors

### 1. Port Already in Use

**Error**:
```
(Plug.Cowboy.HTTPError) could not start Cowboy on port 4000
** (MatchError) no match of right hand side value: {:error, :eaddrinuse}
```

**Cause**: Another process using port 4000

**Solution**:
```bash
# Find process using port 4000
lsof -ti:4000

# Kill process
kill -9 $(lsof -ti:4000)

# Or change port in config
# config/dev.exs
config :expo_controller, ExpoControllerWeb.Endpoint,
  http: [port: 4001]
```

---

### 2. Database Connection Failed

**Error**:
```
(Postgrex.Error) connection not available and request was dropped from queue after 5000ms
```

**Cause**: PostgreSQL not running or wrong credentials

**Diagnosis**:
```bash
# Check PostgreSQL status
docker compose ps  # If using Docker
# or
sudo systemctl status postgresql

# Test connection manually
psql -U expo -d expo_controller_dev -h localhost
```

**Solutions**:

**A. PostgreSQL not running**:
```bash
# Start Docker PostgreSQL
docker compose up -d

# Or start native PostgreSQL
sudo systemctl start postgresql
```

**B. Wrong credentials**:
```bash
# Check config/dev.secret.exs
config :expo_controller, ExpoController.Repo,
  username: "expo",
  password: "expo_dev",  # Must match PostgreSQL user
  hostname: "localhost",
  database: "expo_controller_dev"
```

**C. Database doesn't exist**:
```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate
```

---

### 3. Migration Failed

**Error**:
```
(Postgrex.Error) ERROR 42P01 (undefined_table) relation "builds" does not exist
```

**Cause**: Migrations not run or incomplete

**Solution**:
```bash
# Check migration status
mix ecto.migrations

# Run pending migrations
mix ecto.migrate

# If corrupted, reset database
mix ecto.drop
mix ecto.create
mix ecto.migrate
```

---

### 4. Module Not Found

**Error**:
```
(UndefinedFunctionError) function ExpoController.Builds.create_build/1 is undefined
```

**Cause**: Code not compiled or wrong module name

**Solution**:
```bash
# Clean and recompile
mix clean
mix deps.compile
mix compile

# Verify module exists
iex -S mix
> ExpoController.Builds.__info__(:functions)
```

---

### 5. GenServer Timeout

**Error**:
```
(exit) exited in: GenServer.call(ExpoController.Orchestration.QueueManager, {:enqueue, "build-123"}, 5000)
** (EXIT) time out
```

**Cause**: GenServer overloaded or deadlocked

**Diagnosis**:
```elixir
# In IEx
Process.whereis(ExpoController.Orchestration.QueueManager)
# Returns: #PID<0.234.0> (if running) or nil (if crashed)

# Check process info
pid = Process.whereis(ExpoController.Orchestration.QueueManager)
Process.info(pid, :message_queue_len)
# High message queue = overloaded
```

**Solutions**:

**A. Restart GenServer**:
```elixir
# In IEx
Supervisor.terminate_child(ExpoController.Supervisor, ExpoController.Orchestration.QueueManager)
Supervisor.restart_child(ExpoController.Supervisor, ExpoController.Orchestration.QueueManager)
```

**B. Increase timeout**:
```elixir
# In code
GenServer.call(QueueManager, {:enqueue, build_id}, 10_000)  # 10 seconds
```

**C. Debug deadlock**:
```elixir
# Check what GenServer is waiting for
:sys.get_state(ExpoController.Orchestration.QueueManager)
```

---

### 6. File Upload Fails

**Error**:
```
(File.Error) could not write to file "/storage/builds/abc123/source.zip": no such file or directory
```

**Cause**: Storage directory doesn't exist or no permissions

**Solution**:
```bash
# Create storage directory
mkdir -p ./storage/builds

# Set permissions
chmod 755 ./storage
chmod 755 ./storage/builds

# Or in production
sudo mkdir -p /var/lib/expo-controller/storage
sudo chown expo-controller:expo-controller /var/lib/expo-controller/storage
```

---

### 7. Test Database Errors

**Error**:
```
(Postgrex.Error) ERROR 3D000 (invalid_catalog_name) database "expo_controller_test" does not exist
```

**Cause**: Test database not created

**Solution**:
```bash
# Create test database
MIX_ENV=test mix ecto.create

# Run test migrations
MIX_ENV=test mix ecto.migrate

# Or reset (drops and recreates)
MIX_ENV=test mix ecto.reset
```

---

### 8. Compilation Errors

**Error**:
```
** (CompileError) lib/expo_controller/builds.ex:42: undefined function get_build/1
```

**Cause**: Typo or missing function definition

**Solution**:
```bash
# Check file for typos
# Ensure function is defined:

def get_build(id) do
  # ...
end

# Recompile
mix compile
```

---

### 9. API Authentication Fails

**Error** (HTTP):
```json
{
  "error": "Unauthorized"
}
```

**Cause**: Missing or invalid API key

**Diagnosis**:
```bash
# Check API key in config
grep api_key config/dev.secret.exs

# Test with correct key
curl -H "X-API-Key: dev-api-key-minimum-32-characters-long" \
  http://localhost:4000/api/builds
```

**Solution**:

**A. Set API key in config**:
```elixir
# config/dev.secret.exs
config :expo_controller,
  api_key: "dev-api-key-minimum-32-characters-long"
```

**B. Restart server** (config changes require restart):
```bash
# Stop server (Ctrl+C twice)
# Restart
mix phx.server
```

**C. Use correct header**:
```bash
# Correct
curl -H "X-API-Key: your-key" http://localhost:4000/api/builds

# Wrong (case-sensitive)
curl -H "x-api-key: your-key" http://localhost:4000/api/builds
```

---

### 10. Concurrent Assignment Race Condition

**Symptom**: Two workers assigned same build

**Diagnosis**:
```elixir
# Check for double assignment
build_id = "abc123"
build = Builds.get_build(build_id)

# Query worker assignments
workers = Workers.list_workers(%{build_id: build_id})
length(workers)  # Should be 0 or 1, never > 1
```

**Root Cause**: Missing transaction or lock

**Solution**:
```elixir
# Ensure assignment uses transaction
def assign_to_worker(build, worker_id) do
  Repo.transaction(fn ->
    # Lock build row
    build = from(b in Build,
      where: b.id == ^build.id,
      lock: "FOR UPDATE SKIP LOCKED"
    ) |> Repo.one()

    # Update assignment
    # ...
  end)
end
```

---

### 11. Heartbeat False Positives

**Symptom**: Builds marked as failed even though worker is running

**Diagnosis**:
```bash
# Check last heartbeat time
build_id="abc123"
psql -U expo -d expo_controller_dev -c \
  "SELECT id, status, last_heartbeat_at FROM builds WHERE id='$build_id';"
```

**Root Causes**:

**A. Worker not sending heartbeats**:
```swift
// Worker should send heartbeat every 30 seconds
func sendHeartbeat() {
    let url = URL(string: "\(controllerURL)/api/builds/\(buildId)/heartbeat")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    // ...
}

// Schedule periodic heartbeat
Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
    sendHeartbeat()
}
```

**B. Timeout too aggressive**:
```elixir
# Increase timeout in HeartbeatMonitor
# config/prod.exs
config :expo_controller, :heartbeat_monitor,
  build_timeout: 600  # 10 minutes instead of 5
```

**C. Clock skew**:
```bash
# Ensure server clocks synchronized
sudo timedatectl status

# Enable NTP
sudo timedatectl set-ntp true
```

---

### 12. Queue Not Processing

**Symptom**: Builds stuck in pending status

**Diagnosis**:
```elixir
# In IEx
ExpoController.Orchestration.QueueManager.stats()
# Returns: %{pending: 10}

# Check if builds actually pending in DB
ExpoController.Builds.pending_count()
# Returns: 10

# Verify QueueManager alive
Process.whereis(ExpoController.Orchestration.QueueManager)
# Returns: #PID<0.234.0> or nil if crashed
```

**Solutions**:

**A. QueueManager crashed**:
```bash
# Check logs
sudo journalctl -u expo-controller | grep QueueManager

# Restart GenServer
# In IEx
Supervisor.restart_child(ExpoController.Supervisor, ExpoController.Orchestration.QueueManager)
```

**B. Queue out of sync with DB**:
```elixir
# In IEx
# Manually restore queue
pending_builds = ExpoController.Builds.list_builds(%{status: :pending})
Enum.each(pending_builds, fn build ->
  ExpoController.Orchestration.QueueManager.enqueue(build.id)
end)
```

**C. No workers available**:
```elixir
# Check active workers
ExpoController.Workers.list_workers(%{status: :idle})
# Returns: [] (no idle workers)

# Wait for workers to register or finish current builds
```

---

### 13. Out of Memory

**Error**:
```
eheap_alloc: Cannot allocate 1234567890 bytes of memory (of type "heap")
```

**Cause**: Memory leak or large file uploads

**Diagnosis**:
```bash
# Check BEAM memory
# In IEx
:erlang.memory()
# Returns: [total: 12345678, processes: ..., atom: ..., binary: ...]

# Check individual process memory
Process.list()
|> Enum.map(fn pid -> {pid, :erlang.process_info(pid, :memory)} end)
|> Enum.sort_by(fn {_pid, {:memory, mem}} -> mem end, :desc)
|> Enum.take(10)
```

**Solutions**:

**A. Force garbage collection**:
```elixir
# GC all processes
for pid <- Process.list(), do: :erlang.garbage_collect(pid)
```

**B. Increase BEAM memory limit**:
```bash
# Set max heap size (in words, 1 word = 8 bytes)
ELIXIR_ERL_OPTIONS="+hms 1048576"  # 8GB heap
```

**C. Fix file upload streaming** (ensure not buffering entire file):
```elixir
# Use File.copy instead of reading into memory
File.copy(upload.path, dest_path)
```

---

### 14. Database Transaction Deadlock

**Error**:
```
(Postgrex.Error) ERROR 40P01 (deadlock_detected) deadlock detected
DETAIL: Process 1234 waits for ShareLock on transaction 5678
```

**Cause**: Multiple transactions waiting on each other

**Diagnosis**:
```sql
-- Check locks
SELECT * FROM pg_locks WHERE NOT granted;

-- Check blocking queries
SELECT pid, usename, pg_blocking_pids(pid) AS blocked_by, query AS blocked_query
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;
```

**Solutions**:

**A. Kill blocking transaction**:
```sql
SELECT pg_terminate_backend(1234);  -- PID from above query
```

**B. Retry transaction** (Ecto does this automatically):
```elixir
Repo.transaction(fn ->
  # ...
end, timeout: 10_000)
```

**C. Ensure lock order consistency**:
```elixir
# Always lock tables in same order
# Good: Always lock builds before workers
Repo.transaction(fn ->
  build = Repo.get(Build, id, lock: "FOR UPDATE")
  worker = Repo.get(Worker, worker_id, lock: "FOR UPDATE")
end)

# Bad: Inconsistent order causes deadlocks
```

---

### 15. LiveView Not Updating

**Symptom**: Dashboard shows stale data

**Diagnosis**:
```elixir
# Check PubSub broadcasting
Phoenix.PubSub.broadcast(ExpoController.PubSub, "builds", {:test, "hello"})

# In LiveView mount/1, verify subscription
def mount(_params, _session, socket) do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(ExpoController.PubSub, "builds")
  end
  # ...
end
```

**Solutions**:

**A. Verify WebSocket connection**:
```javascript
// Browser console
// Check for WebSocket connection
// Network tab -> WS filter
```

**B. Check PubSub process**:
```elixir
# In IEx
Process.whereis(ExpoController.PubSub)
# Should return PID
```

**C. Manually trigger broadcast**:
```elixir
# Test if LiveView receives updates
Phoenix.PubSub.broadcast(
  ExpoController.PubSub,
  "builds",
  {"queue:updated", %{pending_count: 42}}
)
```

---

## Debugging Techniques

### Interactive Shell (IEx)

**Start with running server**:
```bash
iex -S mix phx.server
```

**Useful commands**:
```elixir
# Reload code without restarting
recompile()

# List all processes
Process.list()

# Get process state
:sys.get_state(ExpoController.Orchestration.QueueManager)

# Trace function calls
:dbg.tracer()
:dbg.p(:all, :c)
:dbg.tpl(ExpoController.Builds, :assign_to_worker, :x)

# Stop tracing
:dbg.stop()
```

### Remote Console (Production)

**Connect to running release**:
```bash
/opt/expo-controller/bin/expo_controller remote
```

**Attach to running node**:
```bash
/opt/expo-controller/bin/expo_controller attach
```

**Detach**: `Ctrl+D`

### Logging

**Increase log verbosity** (`config/dev.exs`):
```elixir
config :logger, level: :debug

# Show all database queries
config :expo_controller, ExpoController.Repo,
  log: :debug
```

**Add debug statements**:
```elixir
require Logger

def assign_to_worker(build, worker_id) do
  Logger.debug("Assigning build #{build.id} to worker #{worker_id}")
  # ...
end
```

### Breakpoints (IEx.pry)

**Add breakpoint in code**:
```elixir
def assign_to_worker(build, worker_id) do
  require IEx
  IEx.pry()  # Execution stops here

  Repo.transaction(fn ->
    # ...
  end)
end
```

**Run with IEx**:
```bash
iex -S mix phx.server
# When breakpoint hits, interactive shell opens
# Inspect variables, step through code
```

### Database Queries

**Explain query plans**:
```elixir
import Ecto.Query

query = from b in Build,
  where: b.status == :pending,
  order_by: [asc: b.submitted_at]

Repo.explain(:all, query)
# Shows PostgreSQL query plan
```

**Check slow queries** (PostgreSQL):
```sql
-- Enable slow query logging
ALTER DATABASE expo_controller_prod SET log_min_duration_statement = 1000;

-- View slow queries
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

### Process Monitoring

**Observer (GUI)**:
```elixir
# In IEx (requires X11 forwarding)
:observer.start()

# Shows:
# - Process tree
# - Memory usage
# - ETS tables
# - System info
```

**Recon (Production-Safe)**:
```elixir
# In remote console
:recon.proc_count(:memory, 10)  # Top 10 memory consumers
:recon.proc_count(:reductions, 10)  # Top 10 CPU consumers

# Process info
:recon.info(pid)
```

---

## Performance Issues

### Slow Build Assignment

**Symptom**: Poll requests take > 1 second

**Diagnosis**:
```bash
# Time a poll request
time curl -H "X-Worker-Id: worker-1" http://localhost:4000/api/workers/poll
```

**Solutions**:

**A. Add database index**:
```elixir
# migration
create index(:builds, [:status, :submitted_at])
```

**B. Optimize query**:
```elixir
# Before
builds = Repo.all(from b in Build, where: b.status == :pending)
build = List.first(builds)

# After
build = Repo.one(from b in Build,
  where: b.status == :pending,
  order_by: [asc: b.submitted_at],
  limit: 1
)
```

**C. Cache pending count**:
```elixir
# In QueueManager state
%{queue: [...], cached_count: 42}
```

### High Database Connection Count

**Symptom**: `connection not available` errors

**Diagnosis**:
```sql
SELECT count(*) FROM pg_stat_activity WHERE datname = 'expo_controller_dev';
```

**Solution**:
```elixir
# Increase pool size
# config/dev.exs
config :expo_controller, ExpoController.Repo,
  pool_size: 20  # Increase from 10
```

---

## Getting Help

### Log Collection

```bash
# Collect logs for bug report
sudo journalctl -u expo-controller --since "1 hour ago" > expo-controller.log

# Include database logs
sudo tail -n 1000 /var/log/postgresql/postgresql-*.log > postgres.log

# Include system info
uname -a > system-info.txt
mix --version >> system-info.txt
psql --version >> system-info.txt
```

### Bug Report Template

```markdown
### Environment
- Elixir version: 1.18.0
- OTP version: 28.0
- PostgreSQL version: 16.1
- OS: Ubuntu 22.04

### Expected Behavior
Builds should be assigned to idle workers

### Actual Behavior
Builds stuck in pending status

### Steps to Reproduce
1. Start controller
2. Submit build
3. Worker polls
4. No assignment happens

### Logs
[Attach logs here]

### Database State
[Attach query results: SELECT * FROM builds WHERE status = 'pending']
```

---

## Resources

- [Elixir Debugging Guide](https://elixir-lang.org/getting-started/debugging.html)
- [Phoenix Troubleshooting](https://hexdocs.pm/phoenix/up_and_running.html#content)
- [PostgreSQL Error Codes](https://www.postgresql.org/docs/current/errcodes-appendix.html)
- [Recon Library](https://ferd.github.io/recon/)
