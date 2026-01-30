# Testing Guide

Comprehensive testing strategy for Elixir controller covering unit, integration, concurrency, and load tests.

---

## Testing Philosophy

**Critical Invariants**:
1. **No double assignment**: One build assigned to exactly one worker
2. **Atomic state transitions**: Build/worker state always consistent
3. **Fault tolerance**: Crashes don't corrupt data
4. **API compatibility**: Responses match TypeScript exactly

**Test Coverage Goals**:
- Unit tests: 80%+ coverage
- Integration tests: All critical paths
- Concurrency tests: Race conditions caught
- Load tests: Performance validated

---

## Running Tests

### Quick Start

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run specific file
mix test test/expo_controller/builds_test.exs

# Run specific test
mix test test/expo_controller/builds_test.exs:42

# Run with detailed output
mix test --trace

# Run previously failed tests
mix test --failed
```

### Test Database

Tests use separate database: `expo_controller_test`

**Reset test DB**:
```bash
MIX_ENV=test mix ecto.reset
```

**Automatic cleanup**:
- Ecto Sandbox wraps each test in transaction
- Rollback after test completes
- No test pollution between runs

---

## Test Categories

### Unit Tests

**Purpose**: Test individual functions in isolation

**Location**: `test/expo_controller/`

**Example** (`test/expo_controller/builds_test.exs`):
```elixir
defmodule ExpoController.BuildsTest do
  use ExpoController.DataCase

  alias ExpoController.Builds

  describe "create_build/1" do
    test "creates build with valid attributes" do
      attrs = %{
        platform: "ios",
        status: :pending,
        source_path: "/storage/source.zip"
      }

      assert {:ok, build} = Builds.create_build(attrs)
      assert build.platform == "ios"
      assert build.status == :pending
    end

    test "returns error with invalid attributes" do
      attrs = %{platform: "invalid"}

      assert {:error, changeset} = Builds.create_build(attrs)
      assert %{platform: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "assign_to_worker/2" do
    test "assigns pending build to idle worker" do
      build = build_fixture(status: :pending)
      worker = worker_fixture(status: :idle)

      assert {:ok, assigned_build} = Builds.assign_to_worker(build, worker.id)
      assert assigned_build.status == :assigned
      assert assigned_build.worker_id == worker.id
    end

    test "fails when worker is busy" do
      build = build_fixture(status: :pending)
      worker = worker_fixture(status: :building)

      assert {:error, :worker_busy} = Builds.assign_to_worker(build, worker.id)
    end

    test "fails when worker is offline" do
      build = build_fixture(status: :pending)
      worker = worker_fixture(status: :offline)

      assert {:error, :worker_offline} = Builds.assign_to_worker(build, worker.id)
    end
  end
end
```

---

### Integration Tests

**Purpose**: Test full request/response flow through API

**Location**: `test/expo_controller_web/controllers/`

**Example** (`test/expo_controller_web/controllers/build_controller_test.exs`):
```elixir
defmodule ExpoControllerWeb.BuildControllerTest do
  use ExpoControllerWeb.ConnCase

  describe "POST /api/builds/submit" do
    test "creates build and returns success", %{conn: conn} do
      upload = %Plug.Upload{
        path: "test/fixtures/source.zip",
        filename: "source.zip"
      }

      conn = conn
        |> put_req_header("x-api-key", api_key())
        |> post("/api/builds/submit", %{
          "platform" => "ios",
          "source" => upload
        })

      assert %{
        "id" => id,
        "status" => "pending",
        "platform" => "ios"
      } = json_response(conn, 201)

      # Verify build in database
      build = Builds.get_build(id)
      assert build.status == :pending
    end

    test "rejects request without API key", %{conn: conn} do
      conn = post(conn, "/api/builds/submit", %{"platform" => "ios"})

      assert %{"error" => "Unauthorized"} = json_response(conn, 401)
    end
  end

  describe "GET /api/workers/poll" do
    test "returns build when available", %{conn: conn} do
      build = build_fixture(status: :pending)
      worker = worker_fixture(status: :idle)

      conn = conn
        |> put_req_header("x-worker-id", worker.id)
        |> get("/api/workers/poll")

      assert %{
        "build" => %{
          "id" => build_id,
          "platform" => "ios"
        }
      } = json_response(conn, 200)

      assert build_id == build.id

      # Verify build assigned
      updated_build = Builds.get_build(build.id)
      assert updated_build.status == :assigned
      assert updated_build.worker_id == worker.id
    end

    test "returns null when no builds available", %{conn: conn} do
      worker = worker_fixture(status: :idle)

      conn = conn
        |> put_req_header("x-worker-id", worker.id)
        |> get("/api/workers/poll")

      assert %{"build" => nil} = json_response(conn, 200)
    end
  end
end
```

---

### Concurrency Tests

**Purpose**: Verify race condition prevention

**Critical Test: Concurrent Assignment**

```elixir
defmodule ExpoController.ConcurrencyTest do
  use ExpoController.DataCase

  alias ExpoController.{Builds, Workers}
  alias ExpoController.Orchestration.QueueManager

  @tag :concurrent
  test "prevents double assignment under concurrent load" do
    # Create 1 pending build
    build = build_fixture(status: :pending)

    # Enqueue in QueueManager
    QueueManager.enqueue(build.id)

    # Create 10 workers
    workers = Enum.map(1..10, fn i ->
      worker_fixture(name: "worker-#{i}", status: :idle)
    end)

    # All 10 workers poll simultaneously
    tasks = Enum.map(workers, fn worker ->
      Task.async(fn ->
        QueueManager.next_for_worker(worker.id)
      end)
    end)

    # Collect results
    results = Task.await_many(tasks)

    # Exactly 1 success
    successful = Enum.count(results, fn
      {:ok, %{id: _}} -> true
      _ -> false
    end)

    assert successful == 1, "Expected exactly 1 successful assignment, got #{successful}"

    # 9 failures (no build available)
    failed = Enum.count(results, fn
      {:ok, nil} -> true
      {:error, _} -> true
      _ -> false
    end)

    assert failed == 9, "Expected 9 failures, got #{failed}"

    # Verify database state
    updated_build = Builds.get_build(build.id)
    assert updated_build.status == :assigned
    assert updated_build.worker_id in Enum.map(workers, & &1.id)

    # Verify exactly 1 worker is building
    building_workers = Workers.list_workers(%{status: :building})
    assert length(building_workers) == 1
  end

  @tag :concurrent
  test "handles 100 concurrent build submissions" do
    # 100 clients submit builds simultaneously
    tasks = Enum.map(1..100, fn i ->
      Task.async(fn ->
        Builds.create_build(%{
          platform: "ios",
          source_path: "/storage/build-#{i}/source.zip"
        })
      end)
    end)

    results = Task.await_many(tasks, timeout: 10_000)

    # All submissions succeed
    successful = Enum.count(results, &match?({:ok, _}, &1))
    assert successful == 100

    # All builds in database
    builds = Builds.list_builds()
    assert length(builds) == 100
  end

  @tag :concurrent
  test "prevents queue corruption under concurrent enqueue" do
    # Multiple processes enqueue simultaneously
    tasks = Enum.map(1..50, fn i ->
      Task.async(fn ->
        build = build_fixture(status: :pending)
        QueueManager.enqueue(build.id)
        build.id
      end)
    end)

    build_ids = Task.await_many(tasks)

    # Check queue state
    stats = QueueManager.stats()
    assert stats.pending == 50

    # Verify all builds can be assigned
    workers = Enum.map(1..50, fn i ->
      worker_fixture(name: "worker-#{i}")
    end)

    assigned_count = Enum.reduce(workers, 0, fn worker, acc ->
      case QueueManager.next_for_worker(worker.id) do
        {:ok, %{id: _}} -> acc + 1
        {:ok, nil} -> acc
      end
    end)

    assert assigned_count == 50
  end
end
```

**Run concurrency tests**:
```bash
mix test --only concurrent
```

---

### Load Tests

**Purpose**: Validate performance under realistic load

**Tools**:
- `mix run` scripts
- `k6` (HTTP load testing)
- `wrk` (HTTP benchmarking)

**Load Test Script** (`test/load/assignment_load.exs`):
```elixir
# test/load/assignment_load.exs
alias ExpoController.{Builds, Workers}
alias ExpoController.Orchestration.QueueManager

# Create 1000 pending builds
builds = Enum.map(1..1000, fn i ->
  {:ok, build} = Builds.create_build(%{
    platform: "ios",
    source_path: "/storage/build-#{i}/source.zip"
  })

  QueueManager.enqueue(build.id)
  build
end)

# Create 100 workers
workers = Enum.map(1..100, fn i ->
  {:ok, worker} = Workers.create_worker(%{
    name: "worker-#{i}",
    platform: "macos",
    status: :idle
  })
  worker
end)

IO.puts("Created #{length(builds)} builds and #{length(workers)} workers")

# Measure time to assign all builds
start_time = System.monotonic_time(:millisecond)

tasks = Enum.map(workers, fn worker ->
  Task.async(fn ->
    # Each worker keeps polling until no builds left
    poll_until_empty(worker.id)
  end)
end)

Task.await_many(tasks, timeout: 60_000)

end_time = System.monotonic_time(:millisecond)
duration = end_time - start_time

IO.puts("Assigned 1000 builds in #{duration}ms")
IO.puts("Throughput: #{1000 / (duration / 1000)} builds/second")
```

**Run load test**:
```bash
MIX_ENV=test mix run test/load/assignment_load.exs
```

**HTTP Load Test** (k6):
```javascript
// test/load/http_load.js
import http from 'k6/http';
import { check } from 'k6';

export let options = {
  vus: 50,  // 50 virtual users
  duration: '30s',
};

export default function() {
  // Poll for builds
  let res = http.get('http://localhost:4000/api/workers/poll', {
    headers: { 'X-Worker-Id': 'worker-1' }
  });

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 100ms': (r) => r.timings.duration < 100,
  });
}
```

**Run HTTP load test**:
```bash
k6 run test/load/http_load.js
```

---

### Property-Based Tests

**Purpose**: Test invariants with randomized inputs

**Library**: StreamData (included with Elixir)

**Example**:
```elixir
defmodule ExpoController.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  alias ExpoController.Builds

  property "build status transitions are valid" do
    check all status <- member_of([:pending, :assigned, :building, :completed, :failed]),
              platform <- member_of(["ios", "android"]) do

      {:ok, build} = Builds.create_build(%{
        platform: platform,
        status: status
      })

      assert build.status in [:pending, :assigned, :building, :completed, :failed, :cancelled]
    end
  end

  property "heartbeat always updates timestamp" do
    check all build <- build_generator() do
      {:ok, updated} = Builds.record_heartbeat(build.id)

      assert DateTime.compare(updated.last_heartbeat_at, build.last_heartbeat_at) == :gt
    end
  end

  defp build_generator do
    gen all platform <- member_of(["ios", "android"]) do
      {:ok, build} = Builds.create_build(%{platform: platform})
      build
    end
  end
end
```

---

## Test Helpers

### Fixtures

**Location**: `test/support/fixtures/builds_fixtures.ex`

```elixir
defmodule ExpoController.BuildsFixtures do
  alias ExpoController.{Builds, Workers, Repo}

  def build_fixture(attrs \\ %{}) do
    {:ok, build} =
      attrs
      |> Enum.into(%{
        platform: "ios",
        status: :pending,
        source_path: "/storage/test/source.zip"
      })
      |> Builds.create_build()

    build
  end

  def worker_fixture(attrs \\ %{}) do
    {:ok, worker} =
      attrs
      |> Enum.into(%{
        name: "test-worker",
        platform: "macos",
        status: :idle
      })
      |> Workers.create_worker()

    worker
  end
end
```

### ConnCase

**Location**: `test/support/conn_case.ex`

**Provides**:
- Authenticated conn
- API key helpers
- JSON response helpers

```elixir
defmodule ExpoControllerWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import ExpoControllerWeb.ConnCase

      alias ExpoControllerWeb.Router.Helpers, as: Routes

      @endpoint ExpoControllerWeb.Endpoint
    end
  end

  setup tags do
    ExpoController.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def api_key do
    Application.get_env(:expo_controller, :api_key)
  end

  def with_api_key(conn) do
    Plug.Conn.put_req_header(conn, "x-api-key", api_key())
  end
end
```

---

## CI/CD Testing

### GitHub Actions

**File**: `.github/workflows/elixir.yml`

```yaml
name: Elixir CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: expo
          POSTGRES_PASSWORD: expo_test
          POSTGRES_DB: expo_controller_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v3

      - name: Setup Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '28'

      - name: Install dependencies
        run: mix deps.get
        working-directory: packages/controller_elixir

      - name: Compile
        run: mix compile --warnings-as-errors
        working-directory: packages/controller_elixir

      - name: Run tests
        run: mix test --cover
        working-directory: packages/controller_elixir
        env:
          MIX_ENV: test
          DATABASE_URL: postgresql://expo:expo_test@localhost/expo_controller_test
```

---

## Test Coverage

### Generate Coverage Report

```bash
# Run tests with coverage
mix test --cover

# View summary
cat cover/excoveralls.html

# Generate detailed HTML report (requires excoveralls)
mix coveralls.html
open cover/excoveralls.html
```

### Coverage Goals

| Module | Target | Current |
|--------|--------|---------|
| Builds Context | 90% | 85% |
| Workers Context | 90% | 80% |
| Controllers | 80% | 75% |
| GenServers | 90% | 90% |
| File Storage | 80% | 70% |
| Authentication | 100% | 100% |

---

## Compatibility Testing

### Test Against TypeScript API

**Goal**: Ensure identical behavior

**Approach**:
1. Run TypeScript controller
2. Run Elixir controller
3. Execute same test suite against both
4. Compare responses

**Test Script**:
```bash
#!/bin/bash

# Start TypeScript controller
cd packages/controller
bun run start &
TS_PID=$!

# Wait for startup
sleep 2

# Run tests
CONTROLLER_URL=http://localhost:3000 bun test:integration > ts_results.txt

# Stop TypeScript
kill $TS_PID

# Start Elixir controller
cd ../controller_elixir
mix phx.server &
EX_PID=$!

# Wait for startup
sleep 2

# Run same tests
CONTROLLER_URL=http://localhost:4000 bun test:integration > ex_results.txt

# Stop Elixir
kill $EX_PID

# Compare results
diff ts_results.txt ex_results.txt
```

---

## Performance Benchmarks

### Benchmark Script

```elixir
# test/benchmarks/assignment_bench.exs
Benchee.run(%{
  "assign_build" => fn {build, worker} ->
    Builds.assign_to_worker(build, worker.id)
  end
}, before_scenario: fn _ ->
  build = build_fixture(status: :pending)
  worker = worker_fixture(status: :idle)
  {build, worker}
end)
```

**Run benchmark**:
```bash
mix run test/benchmarks/assignment_bench.exs
```

**Target**:
- p50: < 10ms
- p95: < 50ms
- p99: < 100ms

---

## Debugging Failed Tests

### Verbose Output

```bash
# Show detailed test output
mix test --trace

# Show IO.puts in tests
mix test --trace

# Stop on first failure
mix test --max-failures 1
```

### IEx in Tests

```elixir
test "assigns build" do
  build = build_fixture()
  worker = worker_fixture()

  require IEx
  IEx.pry()  # Breakpoint

  Builds.assign_to_worker(build, worker.id)
end
```

**Run with IEx**:
```bash
iex -S mix test --trace
```

### Database Inspection

```elixir
test "creates build" do
  {:ok, build} = Builds.create_build(%{platform: "ios"})

  # Query database directly
  result = Repo.one(from b in Build, where: b.id == ^build.id)

  assert result.platform == "ios"
end
```

---

## Test Maintenance

### Update Fixtures

When schema changes:
1. Update `builds_fixtures.ex`
2. Update factory functions
3. Re-run tests

### Deprecate Tests

Mark obsolete tests:
```elixir
@tag :skip
test "old behavior no longer supported" do
  # ...
end
```

### Tag Organization

```elixir
@tag :unit
test "unit test" do
  # ...
end

@tag :integration
test "integration test" do
  # ...
end

@tag :concurrent
test "concurrency test" do
  # ...
end

@tag :slow
test "slow test" do
  # ...
end
```

**Run specific tags**:
```bash
mix test --only unit
mix test --exclude slow
```

---

## Resources

- [ExUnit Documentation](https://hexdocs.pm/ex_unit/)
- [Ecto Test Patterns](https://hexdocs.pm/ecto/testing-with-ecto.html)
- [Phoenix Testing Guide](https://hexdocs.pm/phoenix/testing.html)
- [Property-Based Testing](https://hexdocs.pm/stream_data/)
- [Benchee Documentation](https://hexdocs.pm/benchee/)
