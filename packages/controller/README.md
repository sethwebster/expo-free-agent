# Expo Free Agent Controller

Central controller server for the Expo Free Agent distributed build system.

## Features

- REST API for build submission and worker management
- SQLite database for persistence
- In-memory job queue with FIFO scheduling
- Local filesystem storage for build artifacts
- Web UI for monitoring builds and workers
- Round-robin worker assignment

## Installation

```bash
bun install
```

## Usage

### Start Controller

```bash
# From project root
bun controller

# Or with custom options
bun controller -- --port 8080 --db ./custom/path.db --storage ./custom/storage

# From controller package
cd packages/controller
bun start
```

### CLI Options

- `--port, -p` - Port to listen on (default: 3000)
- `--db` - Database file path (default: ./data/controller.db)
- `--storage` - Storage directory path (default: ./storage)
- `--help, -h` - Show help message

## API Endpoints

### Builds

- `POST /api/builds/submit` - Submit new build
  - Multipart form: `source` (zip), `certs` (zip, optional), `platform` (ios|android)
  - Returns: `{ id, status, submitted_at }`

- `GET /api/builds/:id/status` - Get build status
  - Returns: Build details with status, timestamps, worker info

- `GET /api/builds/:id/download` - Download build result (IPA/APK)
  - Available when status is `completed`

- `GET /api/builds/:id/logs` - Get build logs
  - Returns: Array of log entries

- `GET /api/builds/:id/source` - Download build source (workers only)

- `GET /api/builds/:id/certs` - Download build certs (workers only)

### Workers

- `POST /api/workers/register` - Register new worker
  - Body: `{ name, capabilities: { platforms: [...], xcode_version, ... } }`
  - Returns: `{ id, status }`

- `GET /api/workers/poll?worker_id=<id>` - Poll for available jobs
  - Returns: `{ job: { id, platform, source_url, certs_url } }` or `{ job: null }`

- `POST /api/workers/upload` - Upload build result
  - Multipart form: `result` (file), `build_id`, `worker_id`, `success` (true|false), `error_message` (optional)
  - Returns: `{ status }`

### Monitoring

- `GET /` - Web UI dashboard
- `GET /health` - Health check with queue stats

## Architecture

### Database Schema

- `workers` - Registered workers with capabilities and stats
- `builds` - Build jobs with status, platform, file paths
- `build_logs` - Timestamped log entries for each build

### Services

- `DatabaseService` - SQLite database wrapper with typed queries
- `JobQueue` - In-memory FIFO queue with worker assignment
- `FileStorage` - Local filesystem storage for artifacts

### Build Flow

1. User submits build via `/api/builds/submit`
2. Controller stores source/certs, creates DB record, enqueues job
3. Worker polls via `/api/workers/poll`, gets assigned job
4. Worker downloads source/certs, builds in VM
5. Worker uploads result via `/api/workers/upload`
6. User downloads artifact via `/api/builds/:id/download`

## Development

```bash
# Start with auto-reload
bun controller:dev

# Build for distribution
bun --cwd packages/controller build
```

## File Structure

```
packages/controller/
├── src/
│   ├── api/
│   │   └── routes.ts          # REST API endpoints
│   ├── db/
│   │   ├── schema.sql         # SQLite schema
│   │   └── Database.ts        # Database service
│   ├── services/
│   │   ├── JobQueue.ts        # In-memory job queue
│   │   └── FileStorage.ts    # Local file storage
│   ├── views/
│   │   └── index.ejs          # Web UI template
│   ├── server.ts              # Express server
│   └── cli.ts                 # CLI entry point
├── package.json
└── README.md
```

## Storage Layout

```
storage/
├── builds/           # Source code zips
│   └── <build-id>.zip
├── certs/           # Signing certificates
│   └── <build-id>.zip
└── results/         # Build outputs
    └── <build-id>.{ipa|apk}
```

## Database Location

Default: `./data/controller.db`

## Notes

- This is an MVP implementation for prototyping
- No authentication/authorization (add before production)
- No encryption (trust local network for prototype)
- No distributed storage (local filesystem only)
- No persistent queue (in-memory, lost on restart)
