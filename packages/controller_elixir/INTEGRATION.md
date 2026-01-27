# Elixir Controller Integration

## Landing Page Integration

The Elixir controller provides a public statistics endpoint that the landing page consumes.

### Development Setup

1. **Start PostgreSQL**:
   ```bash
   docker compose up -d
   ```

2. **Run database migrations**:
   ```bash
   mix ecto.migrate
   ```

3. **Start the Elixir controller** (port 4000):
   ```bash
   mix phx.server
   ```

4. **In another terminal, start the landing page** (port 5173):
   ```bash
   cd ../landing-page
   bun dev
   ```

The landing page Vite dev server is configured to proxy `/api/*` and `/public/*` requests to `http://localhost:4000`.

### Public Endpoints

#### GET /public/stats
Returns real-time system statistics for the landing page.

**Response**:
```json
{
  "nodesOnline": 5,
  "buildsQueued": 12,
  "activeBuilds": 3,
  "buildsToday": 84,
  "totalBuilds": 1247
}
```

**Field Descriptions**:
- `nodesOnline`: Workers currently connected (idle + building)
- `buildsQueued`: Builds waiting in queue (pending status)
- `activeBuilds`: Builds currently being processed (building status)
- `buildsToday`: Total builds completed or failed today
- `totalBuilds`: All-time total builds in the system

**Usage**:
```bash
curl http://localhost:4000/public/stats
```

#### GET /api/stats
Legacy alias for `/public/stats`. Maintained for backwards compatibility.

### Production Deployment

The landing page fetches stats from:
- **Development**: Proxied to `http://localhost:4000` via Vite
- **Production**: Direct fetch to controller URL (set via `VITE_CONTROLLER_URL` env var)

Set `VITE_CONTROLLER_URL` before building the landing page:
```bash
VITE_CONTROLLER_URL=https://controller.example.com bun run build
```

### Real-Time Dashboard

The Elixir controller also provides a LiveView dashboard at the root path.

**Access**:
- Open `http://localhost:4000/` in your browser
- Real-time updates via Phoenix Channels and PubSub
- Shows build queue, worker status, recent builds, and active workers

**Features**:
- Live statistics updates every 5 seconds
- PubSub broadcasts for instant updates on queue/assignment changes
- Color-coded build statuses
- Worker performance metrics (builds completed/failed)
- Relative timestamps for activity

### API Authentication

The public stats endpoint **does not require authentication**. All other API endpoints require the `X-API-Key` header:

```bash
curl -H "X-API-Key: your-api-key" http://localhost:4000/api/builds
```

Configure the API key in `config/runtime.exs` or via environment variable:
```bash
export CONTROLLER_API_KEY="your-secure-api-key"
```
