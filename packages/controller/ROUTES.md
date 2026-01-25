# API Route Taxonomy

Clean, modular Fastify plugin architecture for the Expo Free Agent Controller API.

## Structure

```
src/api/
├── index.ts              # Main API plugin (registers all sub-routes)
├── builds/
│   └── index.ts         # Build lifecycle routes
├── workers/
│   └── index.ts         # Worker management routes
└── diagnostics/
    └── index.ts         # Worker health monitoring routes
```

## Routes

### Builds (`/api/builds`)

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| POST | `/submit` | Submit new build job | API Key |
| GET | `/` | List all builds | API Key |
| GET | `/active` | List currently running builds | API Key |
| GET | `/:id/status` | Get build status | API Key |
| GET | `/:id/logs` | Get build logs | API Key |
| GET | `/:id/download` | Download build result (IPA/APK) | API Key |
| GET | `/:id/source` | Download source zip | API Key + Worker ID |
| GET | `/:id/certs` | Download certs zip | API Key + Worker ID |
| POST | `/:id/heartbeat` | Worker heartbeat (proves alive) | API Key |
| POST | `/:id/cancel` | Cancel running/stuck build | API Key |

### Workers (`/api/workers`)

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| POST | `/register` | Register new worker | API Key |
| GET | `/poll` | Poll for available jobs | API Key |
| POST | `/upload` | Upload build result | API Key |
| GET | `/:id/stats` | Get worker statistics | API Key |

### Diagnostics (`/api/diagnostics`)

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| POST | `/report` | Submit diagnostic report | API Key |
| GET | `/:worker_id` | Get worker diagnostic history | API Key |
| GET | `/:worker_id/latest` | Get latest diagnostic | API Key |

## Authentication

All routes require `X-API-Key` header matching `config.apiKey`.

Worker-specific routes (source/certs downloads) additionally require `X-Worker-Id` header matching the assigned worker.

## Plugin Architecture

Each resource is a Fastify plugin:

```typescript
// api/builds/index.ts
export const buildsRoutes: FastifyPluginAsync<BuildsPluginOptions> = async (
  fastify,
  { db, queue, storage, config }
) => {
  fastify.post('/submit', async (request, reply) => {
    // Handler logic
  });
  // More routes...
};
```

Registered in `api/index.ts`:

```typescript
await fastify.register(buildsRoutes, {
  prefix: '/builds',
  db, queue, storage, config
});
```

## File Uploads

Uses `@fastify/multipart` for streaming multipart uploads:

- `/builds/submit` - Accepts `source` (required) and `certs` (optional) files
- `/workers/upload` - Accepts `result` file (IPA/APK)

Size limits enforced from config:
- `maxSourceFileSize`
- `maxCertsFileSize`
- `maxResultFileSize`

## Type Safety

Full TypeScript types for all routes:

```typescript
interface BuildParams {
  id: string;
}

fastify.get<{ Params: BuildParams }>('/:id/status', async (request, reply) => {
  const buildId = request.params.id; // Typed!
});
```
