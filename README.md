# Expo Free Agent

Distributed build mesh for Expo apps. Workers run on user Macs (background idle CPU) to build apps in isolated VMs.

## Architecture

This is a self-hosted distributed build system with three components:

1. **Central Controller** (Node.js/Bun) - Job queue, worker registry, file storage, web UI
2. **Free Agent App** (macOS/Swift) - Worker agent that builds apps in VMs
3. **Submit CLI** (Node.js) - Client for submitting builds

See [ARCHITECTURE.md](./docs/architecture/architecture.md) for full design and prototype plan.

## Project Structure

```
expo-free-agent/
├── packages/
│   ├── controller/        # Central controller server (✅ IMPLEMENTED)
│   ├── landing-page/      # Marketing landing page (✅ IMPLEMENTED)
│   ├── worker-installer/  # Worker installation CLI (✅ IMPLEMENTED)
│   └── free-agent/       # macOS worker app (✅ IMPLEMENTED)
├── cli/                   # Build submission CLI (✅ IMPLEMENTED)
├── docs/                  # All documentation
├── CLAUDE.md             # Agent rules and requirements
└── README.md
```

## Status - Week 1: Controller Implementation

✅ **Completed:**

- Monorepo structure with Bun workspace
- Express REST API server
- SQLite database (builds, workers, build_logs)
- In-memory FIFO job queue
- Local filesystem storage
- All API endpoints per ARCHITECTURE.md
- Web UI for monitoring builds/workers
- Round-robin worker assignment
- Health checks and logging

**All Week 1 tasks completed.**

## Worker Installation

Install the Free Agent worker app on macOS to start earning build credits:

```bash
npx @sethwebster/expo-free-agent-worker@latest
```

Or start earning credits in one command:

```bash
npx @sethwebster/expo-free-agent start
```

**⚠️ Critical**: The worker uses native macOS tools (`tar`, `ditto`) to preserve code signatures during installation. See [GATEKEEPER.md](./docs/operations/gatekeeper.md) for technical details about notarization handling.

## Quick Start

### Smoketest (30 seconds)

Verify everything works:

```bash
./smoketest.sh
```

Or run full E2E test (5 minutes):

```bash
./test-e2e.sh
```

See **[SMOKETEST.md](./docs/testing/smoketest.md)** for detailed testing options.

### Install Dependencies

```bash
bun install
```

### Start Controller

```bash
# Set API key (required)
export CONTROLLER_API_KEY="your-secure-key-min-16-chars"

# Start with defaults (port 3000)
bun controller

# Custom port
bun controller -- --port 8080
```

### Access Web UI

Open http://localhost:3000 to see dashboard with builds and workers.

### Test API

```bash
# Health check
curl http://localhost:3000/health

# Register worker (simulate)
curl -X POST http://localhost:3000/api/workers/register \
  -H "Content-Type: application/json" \
  -d '{"name": "test-mac", "capabilities": {"platforms": ["ios"], "xcode_version": "15.0"}}'

# Run full test suite
./test-api.sh
```

## API Endpoints

### Builds

- `POST /api/builds/submit` - Submit new build
- `GET /api/builds/:id/status` - Check build status
- `GET /api/builds/:id/download` - Download IPA/APK
- `GET /api/builds/:id/logs` - Get build logs
- `GET /api/builds/:id/source` - Download source (workers only)
- `GET /api/builds/:id/certs` - Download certs (workers only)

### Workers

- `POST /api/workers/register` - Register new worker
- `GET /api/workers/poll?worker_id=<id>` - Poll for jobs
- `POST /api/workers/upload` - Upload build result

### Monitoring

- `GET /` - Web UI dashboard
- `GET /health` - Health check with stats

See [packages/controller/README.md](./packages/controller/README.md) for detailed API docs.

## Testing

Comprehensive test suite covering controller, CLI, and end-to-end flows.

```bash
# Run all tests
bun run test:all

# Run specific test suites
bun run test:controller    # Controller integration tests
bun run test:cli          # CLI integration tests
bun run test:e2e          # End-to-end bash script

# Run from packages
cd packages/controller && bun test
cd cli && bun test

# Start mock worker for testing
bun test/mock-worker.ts --help
```

**Test Coverage:**
- ✅ Authentication (API key validation)
- ✅ Build submission/download
- ✅ Worker registration/polling
- ✅ File upload/download with auth
- ✅ Error handling
- ✅ Queue persistence across restarts

See **[TESTING.md](./docs/testing/testing.md)** for comprehensive testing documentation.

## Development

### Controller

```bash
# Start with auto-reload
bun controller:dev
```

### Landing Page

Static marketing site built with Vite + React 19 + Tailwind CSS v4.

**Development:**
```bash
bun run landing-page:dev  # http://localhost:5173
```

**Build:**
```bash
bun run landing-page:build  # Output to packages/landing-page/dist
```

**Preview:**
```bash
bun run landing-page:preview  # Preview production build
```

**Deploy to Cloudflare Pages:**

Option 1 - Dashboard:
1. Go to Cloudflare Dashboard → Pages
2. Connect GitHub repo
3. Configure:
   - Build command: `cd packages/landing-page && bun run build`
   - Build output: `packages/landing-page/dist`
   - Framework preset: None

Option 2 - Wrangler CLI:
```bash
cd packages/landing-page
bun run build
npx wrangler pages deploy dist --project-name=expo-free-agent
```

Configuration: See `packages/landing-page/wrangler.toml`

## Next Steps (Week 2+)

1. **Submit CLI** - Build submission tool
2. **Free Agent App** - macOS worker with VM execution
3. **Integration Testing** - End-to-end build flow
4. **VM Setup** - macOS VM image with Xcode

## Technical Stack

- **Runtime:** Bun
- **Server:** Express.js
- **Database:** SQLite (bun:sqlite)
- **Storage:** Local filesystem
- **Queue:** In-memory (EventEmitter)
- **Templates:** EJS

## Documentation

Complete documentation is organized in the `docs/` directory:

- **[Documentation Index](./docs/INDEX.md)** - Central navigation for all docs
- [Getting Started](./docs/getting-started/) - Setup and quickstart guides
- [Architecture](./docs/architecture/) - System design and decisions
- [Operations](./docs/operations/) - Deployment and release procedures
- [Testing](./docs/testing/) - Testing documentation

## Design Principles (from AGENTS.md)

- No hard borders in UI
- DDD architecture (repositories/use cases)
- Production-quality from day 1
- Less code over more code
- Mobile-first design

## Storage Layout

```
data/
└── controller.db         # SQLite database

storage/
├── builds/              # Source code zips
├── certs/              # Signing certificates
└── results/            # Build outputs (IPA/APK)
```

## Important Notes

### Security & Distribution

- **Gatekeeper Fix**: v0.1.15+ uses native `tar` and `ditto` to preserve code signatures. Never manipulate quarantine attributes on notarized apps. See [GATEKEEPER.md](./docs/operations/gatekeeper.md) for details.
- **Worker Distribution**: macOS app is code-signed with Developer ID and notarized by Apple. Distributed via npm as `.tar.gz`.

### System Requirements

- This is a prototype for self-hosting
- No authentication yet (add before production)
- No encryption (trust local network)
- Local filesystem only (no S3)
- In-memory queue (lost on restart)

## License

MIT
