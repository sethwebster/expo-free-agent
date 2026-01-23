import { Request, Response, NextFunction } from 'express';
import type { ControllerConfig } from '../domain/Config.js';

/**
 * Authentication middleware for API endpoints
 *
 * Security model:
 * - Shared API key (passed in X-API-Key header)
 * - Designed for localhost-only trusted network
 * - NOT production-ready (needs per-worker keys, rate limiting, HTTPS, etc.)
 *
 * Usage:
 *   router.use(requireApiKey(config));
 */
export function requireApiKey(config: ControllerConfig) {
  return (req: Request, res: Response, next: NextFunction) => {
    const providedKey = req.headers['x-api-key'];

    if (!providedKey) {
      return res.status(401).json({
        error: 'Missing X-API-Key header',
      });
    }

    if (providedKey !== config.apiKey) {
      return res.status(403).json({
        error: 'Invalid API key',
      });
    }

    next();
  };
}

/**
 * Worker verification middleware
 * Validates that worker_id in request matches assigned worker for build
 *
 * Usage:
 *   router.get('/builds/:id/source', requireWorkerAccess(db), (req, res) => {...})
 */
export function requireWorkerAccess(db: any) {
  return (req: Request, res: Response, next: NextFunction) => {
    const workerId = req.headers['x-worker-id'] as string;
    const buildId = req.params.id;

    if (!workerId) {
      return res.status(401).json({
        error: 'Missing X-Worker-Id header',
      });
    }

    const build = db.getBuild(buildId);
    if (!build) {
      return res.status(404).json({
        error: 'Build not found',
      });
    }

    // Allow access if:
    // 1. Worker is assigned to this build, OR
    // 2. Build is pending (worker is about to be assigned)
    if (build.worker_id && build.worker_id !== workerId) {
      return res.status(403).json({
        error: 'Worker not authorized for this build',
      });
    }

    // Attach build to request for convenience
    (req as any).build = build;
    next();
  };
}
