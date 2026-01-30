# Development Guide

Local setup, testing, debugging for Elixir controller development.

---

## Prerequisites

### Required Software

**Elixir & OTP**:
```bash
# macOS (via Homebrew)
brew install elixir

# Verify versions
elixir --version  # Should be 1.18+
erl -version      # Should be OTP 28+
```

**PostgreSQL**:
```bash
# macOS (via Homebrew)
brew install postgresql@16
brew services start postgresql@16

# OR use Docker (recommended)
# See docker-compose.yml in this directory
```

**Node.js** (for integration testing with CLI/worker):
```bash
# Required for running TypeScript tests
brew install node@20
```

---

## Initial Setup

### 1. Install Dependencies

```bash
cd packages/controller_elixir

# Fetch Elixir dependencies
mix deps.get

# Compile dependencies
mix deps.compile
```

### 2. Start PostgreSQL

**Option A: Docker (Recommended)**:
```bash
# Start PostgreSQL in background
docker compose up -d

# Verify running
docker compose ps
```

**Option B: Native PostgreSQL**:
```bash
# Start PostgreSQL service
brew services start postgresql@16

# Create user (if doesn't exist)
createuser -s expo
psql -c "ALTER USER expo WITH PASSWORD 'expo_dev';"
```

### 3. Configure Environment

Create `config/dev.secret.exs`:

```elixir
import Config

# API key for authentication
config :expo_controller,
  api_key: "dev-api-key-minimum-32-characters-long",
  storage_root: "./storage"

# Database configuration
config :expo_controller, ExpoController.Repo,
  username: "expo",
  password: "expo_dev",
  hostname: "localhost",
  database: "expo_controller_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Optional: Adjust log level
config :logger, level: :debug
```

**⚠️ Security**: Never commit `dev.secret.exs` (already in `.gitignore`).

### 4. Create and Migrate Database

```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Verify migrations ran
mix ecto.migrations
```

**Output**:
```
Status    Migration ID    Migration Name
--------------------------------------------------
  up      20260127024523  create_workers
  up      20260127024524  create_builds
  up      20260127024525  create_build_logs
```

---

## Running the Server

### Development Server

**Standard mode**:
```bash
mix phx.server
```

**Interactive mode** (with IEx shell):
```bash
iex -S mix phx.server
```

**Server starts at**: `http://localhost:4000`

**Endpoints**:
- Dashboard: `http://localhost:4000/`
- API: `http://localhost:4000/api/builds`
- Stats: `http://localhost:4000/api/stats`
- LiveDashboard: `http://localhost:4000/dev/dashboard` (dev only)

### Verify Server Running

```bash
# Health check (once implemented)
curl http://localhost:4000/health

# Get stats (no auth required)
curl http://localhost:4000/api/stats

# List builds (requires API key)
curl -H "X-API-Key: dev-api-key-minimum-32-characters-long" \
  http://localhost:4000/api/builds
```

---

## Running Tests

### All Tests

```bash
# Run full test suite
mix test

# Run with coverage report
mix test --cover

# Run tests and show detailed output
mix test --trace
```

### Specific Tests

```bash
# Run single test file
mix test test/expo_controller/builds_test.exs

# Run specific test by line number
mix test test/expo_controller/builds_test.exs:42

# Run tests matching pattern
mix test --only concurrent

# Run previously failed tests only
mix test --failed
```

### Continuous Testing

```bash
# Auto-run tests on file changes (requires mix_test_watch)
mix test.watch
```

### Test Database

Tests use `expo_controller_test` database (separate from dev).

**Reset test database**:
```bash
MIX_ENV=test mix ecto.reset
```

---

## Database Operations

### Migrations

**Create new migration**:
```bash
mix ecto.gen.migration add_field_to_builds
```

**Run pending migrations**:
```bash
mix ecto.migrate
```

**Rollback last migration**:
```bash
mix ecto.rollback
```

**Rollback to specific version**:
```bash
mix ecto.rollback --to 20260127024523
```

**Check migration status**:
```bash
mix ecto.migrations
```

### Database Reset

**Development**:
```bash
# Drop, create, and migrate
mix ecto.reset
```

**Test**:
```bash
MIX_ENV=test mix ecto.reset
```

### Seeds

**Create seed data** (`priv/repo/seeds.exs`):
```elixir
alias ExpoController.{Repo, Builds, Workers}

# Create test workers
{:ok, worker1} = Workers.create_worker(%{
  name: "dev-worker-1",
  platform: "macos",
  status: :idle
})

# Create test builds
{:ok, build1} = Builds.create_build(%{
  platform: "ios",
  status: :pending,
  source_path: "/storage/test/source.zip"
})
```

**Run seeds**:
```bash
mix run priv/repo/seeds.exs
```

---

## Debugging

### IEx Shell

**Start with server running**:
```bash
iex -S mix phx.server
```

**Useful IEx commands**:
```elixir
# List all builds
ExpoController.Builds.list_builds()

# Get specific build
ExpoController.Builds.get_build("build-id")

# Create test build
{:ok, build} = ExpoController.Builds.create_build(%{
  platform: "ios",
  status: :pending
})

# Check queue state
ExpoController.Orchestration.QueueManager.stats()

# Reload code without restarting server
recompile()

# Inspect process state
:sys.get_state(ExpoController.Orchestration.QueueManager)
```

### Debug Logging

**Enable debug logs** (`config/dev.exs`):
```elixir
config :logger, level: :debug
```

**Add debug statements**:
```elixir
require Logger
Logger.debug("Build #{build.id} assigned to worker #{worker_id}")
```

**Filter logs by module**:
```elixir
config :logger, :console,
  metadata: [:module, :function, :line]
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
```

When breakpoint hits, IEx opens interactive shell.

### Database Queries

**Enable query logging** (`config/dev.exs`):
```elixir
config :expo_controller, ExpoController.Repo,
  log: :debug  # Shows all SQL queries
```

**Inspect queries in IEx**:
```elixir
import Ecto.Query

# See generated SQL
query = from b in Build, where: b.status == :pending
Repo.to_sql(:all, query)
```

---

## Code Formatting

**Format all files**:
```bash
mix format
```

**Check formatting** (CI):
```bash
mix format --check-formatted
```

**Format config** (`.formatter.exs`):
```elixir
[
  import_deps: [:ecto, :phoenix],
  inputs: ["*.{ex,exs}", "{config,lib,test}/**/*.{ex,exs}"],
  subdirectories: ["priv/*/migrations"]
]
```

---

## Linting and Quality

### Credo (Static Analysis)

**Run Credo**:
```bash
mix credo

# Strict mode
mix credo --strict

# Only warnings
mix credo --all --format=flycheck
```

### Dialyzer (Type Checking)

**Build PLT** (first time only):
```bash
mix dialyzer --plt
```

**Run type checking**:
```bash
mix dialyzer
```

---

## Common Development Tasks

### Adding a New Endpoint

1. **Add route** (`lib/expo_controller_web/router.ex`):
```elixir
scope "/api", ExpoControllerWeb do
  pipe_through :api

  get "/builds/:id/metadata", BuildController, :metadata
end
```

2. **Add controller action** (`lib/expo_controller_web/controllers/build_controller.ex`):
```elixir
def metadata(conn, %{"id" => id}) do
  case Builds.get_build(id) do
    nil ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "Build not found"})

    build ->
      conn
      |> json(%{
        platform: build.platform,
        submitted_at: build.submitted_at
      })
  end
end
```

3. **Add test** (`test/expo_controller_web/controllers/build_controller_test.exs`):
```elixir
test "GET /api/builds/:id/metadata returns metadata", %{conn: conn} do
  build = build_fixture()

  conn = get(conn, ~p"/api/builds/#{build.id}/metadata")

  assert %{
    "platform" => "ios",
    "submitted_at" => _
  } = json_response(conn, 200)
end
```

### Adding a Database Field

1. **Create migration**:
```bash
mix ecto.gen.migration add_priority_to_builds
```

2. **Edit migration** (`priv/repo/migrations/*.exs`):
```elixir
defmodule ExpoController.Repo.Migrations.AddPriorityToBuilds do
  use Ecto.Migration

  def change do
    alter table(:builds) do
      add :priority, :integer, default: 0, null: false
    end

    create index(:builds, [:priority])
  end
end
```

3. **Update schema** (`lib/expo_controller/builds/build.ex`):
```elixir
schema "builds" do
  field :priority, :integer, default: 0
  # ...
end

def changeset(build, attrs) do
  build
  |> cast(attrs, [:priority, ...])
  |> validate_number(:priority, greater_than_or_equal_to: 0)
end
```

4. **Run migration**:
```bash
mix ecto.migrate
```

---

## Performance Profiling

### Query Performance

**Enable query timing** (`config/dev.exs`):
```elixir
config :expo_controller, ExpoController.Repo,
  log: :debug,
  pool_size: 10
```

**Analyze slow queries**:
```elixir
import Ecto.Query

query = from b in Build,
  join: w in assoc(b, :worker),
  where: b.status == :building

Repo.explain(:all, query)
```

### Memory Profiling

**In IEx**:
```elixir
# Check process memory
:erlang.process_info(self(), :memory)

# Garbage collect
:erlang.garbage_collect()

# Total system memory
:erlang.memory()
```

### CPU Profiling

**Using `:fprof`**:
```elixir
:fprof.trace([:start])
# Run code to profile
ExpoController.Builds.list_builds()
:fprof.trace([:stop])
:fprof.profile()
:fprof.analyse()
```

---

## Troubleshooting

### Port Already in Use

**Error**: `(Plug.Cowboy.HTTPError) could not start Cowboy on port 4000`

**Solution**:
```bash
# Find process on port 4000
lsof -ti:4000

# Kill process
kill -9 $(lsof -ti:4000)

# OR change port in config/dev.exs
config :expo_controller, ExpoControllerWeb.Endpoint,
  http: [port: 4001]
```

### Database Connection Failed

**Error**: `(Postgrex.Error) connection not available`

**Solution**:
```bash
# Check PostgreSQL running
docker compose ps

# Restart PostgreSQL
docker compose restart

# Verify credentials in config/dev.secret.exs
```

### Migration Failed

**Error**: `(Postgrex.Error) column "field" does not exist`

**Solution**:
```bash
# Check migration status
mix ecto.migrations

# Rollback and re-run
mix ecto.rollback
mix ecto.migrate

# If corrupted, reset
mix ecto.reset
```

### Compilation Errors

**Error**: `** (CompileError) undefined function`

**Solution**:
```bash
# Clean build artifacts
mix clean

# Recompile dependencies
mix deps.compile --force

# Recompile project
mix compile
```

---

## Git Hooks

**Pre-commit hook** (`.git/hooks/pre-commit`):
```bash
#!/bin/sh
cd packages/controller_elixir

# Format code
mix format --check-formatted || {
  echo "Code not formatted. Run: mix format"
  exit 1
}

# Run tests
mix test || {
  echo "Tests failed"
  exit 1
}
```

Make executable:
```bash
chmod +x .git/hooks/pre-commit
```

---

## IDE Setup

### VS Code

**Install extensions**:
- ElixirLS (language server)
- Phoenix Framework (snippets)

**Settings** (`.vscode/settings.json`):
```json
{
  "elixirLS.projectDir": "packages/controller_elixir",
  "elixirLS.mixEnv": "dev",
  "editor.formatOnSave": true
}
```

### Emacs

```elisp
;; alchemist-mode
(use-package alchemist
  :ensure t
  :hook (elixir-mode . alchemist-mode))
```

### Vim

```vim
" vim-elixir
Plug 'elixir-editors/vim-elixir'
```

---

## Resources

- [Elixir Getting Started](https://elixir-lang.org/getting-started/introduction.html)
- [Phoenix Guides](https://hexdocs.pm/phoenix/overview.html)
- [Ecto Documentation](https://hexdocs.pm/ecto/)
- [ExUnit Documentation](https://hexdocs.pm/ex_unit/)
- [Architecture Documentation](./ARCHITECTURE.md)
- [Testing Guide](./TESTING.md)
