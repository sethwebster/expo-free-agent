import { FastifyRequest, FastifyReply } from 'fastify';
import type { ControllerConfig } from '../domain/Config.js';
import type { DatabaseService } from '../db/Database.js';

/**
 * Authentication hook for API endpoints
 *
 * Security model:
 * - Shared API key (passed in X-API-Key header)
 * - Designed for localhost-only trusted network
 * - NOT production-ready (needs per-worker keys, rate limiting, HTTPS, etc.)
 *
 * Usage:
 *   fastify.addHook('onRequest', requireApiKey(config));
 */
export function requireApiKey(config: ControllerConfig) {
  return async (request: FastifyRequest, reply: FastifyReply) => {
    const providedKey = request.headers['x-api-key'];

    if (!providedKey) {
      return reply.status(401).send({
        error: 'Missing X-API-Key header',
      });
    }

    if (providedKey !== config.apiKey) {
      return reply.status(403).send({
        error: 'Invalid API key',
      });
    }
  };
}

/**
 * Worker verification hook
 * Validates that worker_id in request matches assigned worker for build
 *
 * Usage:
 *   fastify.addHook('preHandler', requireWorkerAccess(db));
 */
export function requireWorkerAccess(db: DatabaseService) {
  return async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
    const workerId = request.headers['x-worker-id'] as string;
    const buildId = request.params.id;

    if (!workerId) {
      return reply.status(401).send({
        error: 'Missing X-Worker-Id header',
      });
    }

    const build = db.getBuild(buildId);
    if (!build) {
      return reply.status(404).send({
        error: 'Build not found',
      });
    }

    // Allow access if:
    // 1. Worker is assigned to this build, OR
    // 2. Build is pending (worker is about to be assigned)
    if (build.worker_id && build.worker_id !== workerId) {
      return reply.status(403).send({
        error: 'Worker not authorized for this build',
      });
    }

    // Attach build to request for convenience
    (request as any).build = build;
  };
}
