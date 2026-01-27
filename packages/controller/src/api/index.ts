import { FastifyPluginAsync } from 'fastify';
import multipart from '@fastify/multipart';
import type { DatabaseService } from '../db/Database.js';
import type { JobQueue } from '../services/JobQueue.js';
import type { FileStorage } from '../services/FileStorage.js';
import type { ControllerConfig } from '../domain/Config.js';
import { requireApiKey } from '../middleware/auth.js';
import { buildsRoutes } from './builds/index.js';
import { workersRoutes } from './workers/index.js';
import { diagnosticsRoutes } from './diagnostics/index.js';
import { statsRoutes } from './stats/index.js';

export interface ApiPluginOptions {
  db: DatabaseService;
  queue: JobQueue;
  storage: FileStorage;
  config: ControllerConfig;
}

/**
 * API Routes Plugin
 *
 * Route Taxonomy:
 *
 * /api
 *   /builds
 *     POST   /submit          - Submit new build
 *     GET    /                - List all builds
 *     GET    /active          - List active builds
 *     GET    /:id/status      - Get build status
 *     GET    /:id/logs        - Get build logs
 *     GET    /:id/download    - Download result
 *     GET    /:id/source      - Download source (workers only)
 *     GET    /:id/certs       - Download certs (workers only)
 *     GET    /:id/certs-secure - Get certs JSON for VM bootstrap (workers only, requires X-Build-Id)
 *     POST   /:id/heartbeat   - Send heartbeat
 *     POST   /:id/cancel      - Cancel build
 *
 *   /workers
 *     POST   /register        - Register worker
 *     GET    /poll            - Poll for jobs
 *     POST   /upload          - Upload result
 *     GET    /:id/stats       - Get worker stats
 *
 *   /diagnostics
 *     POST   /report          - Submit diagnostic report
 *     GET    /:worker_id      - Get worker diagnostics
 *     GET    /:worker_id/latest - Get latest diagnostic
 *
 *   /stats
 *     GET    /                - Get network stats (public, no auth)
 */
export const registerApiRoutes: FastifyPluginAsync<ApiPluginOptions> = async (
  fastify,
  options
) => {
  const { db, queue, storage, config } = options;

  // Register multipart for file uploads
  await fastify.register(multipart, {
    limits: {
      fileSize: Math.max(
        config.maxSourceFileSize,
        config.maxCertsFileSize,
        config.maxResultFileSize
      ),
    },
  });

  // Apply API key authentication to all routes
  fastify.addHook('onRequest', requireApiKey(config));

  // Register route modules
  await fastify.register(buildsRoutes, {
    prefix: '/builds',
    db,
    queue,
    storage,
    config,
  });

  await fastify.register(workersRoutes, {
    prefix: '/workers',
    db,
    queue,
    storage,
    config,
  });

  await fastify.register(diagnosticsRoutes, {
    prefix: '/diagnostics',
    db,
    config,
  });
};
