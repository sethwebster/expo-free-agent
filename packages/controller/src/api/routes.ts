import express, { Router, Request, Response } from 'express';
import multer from 'multer';
import { nanoid } from 'nanoid';
import { Readable } from 'stream';
import type { DatabaseService } from '../db/Database.js';
import type { JobQueue } from '../services/JobQueue.js';
import type { FileStorage } from '../services/FileStorage.js';
import type { ControllerConfig } from '../domain/Config.js';
import { requireApiKey, requireWorkerAccess } from '../middleware/auth.js';

/**
 * Helper to convert buffer to stream
 */
function bufferToStream(buffer: Buffer): Readable {
  return Readable.from(buffer);
}

/**
 * Helper to pipe stream with error handling
 */
function pipeStreamSafely(stream: Readable, res: Response, errorMessage: string) {
  stream.on('error', (err) => {
    console.error(`Stream error: ${errorMessage}:`, err);
    if (!res.headersSent) {
      res.status(500).json({ error: errorMessage });
    }
  });
  stream.pipe(res);
}

export function createApiRoutes(
  db: DatabaseService,
  queue: JobQueue,
  storage: FileStorage,
  config: ControllerConfig
): Router {
  const router = Router();

  // Configure multer with size limits
  const uploadSource = multer({
    storage: multer.memoryStorage(),
    limits: {
      fileSize: config.maxSourceFileSize,
      files: 1,
    },
  });

  const uploadCerts = multer({
    storage: multer.memoryStorage(),
    limits: {
      fileSize: config.maxCertsFileSize,
      files: 1,
    },
  });

  const uploadResult = multer({
    storage: multer.memoryStorage(),
    limits: {
      fileSize: config.maxResultFileSize,
      files: 1,
    },
  });

  const uploadBuildSubmission = multer({
    storage: multer.memoryStorage(),
    limits: {
      fileSize: config.maxSourceFileSize, // Use larger limit for source
      files: 2, // source + certs
    },
  });

  // Apply API key authentication to all routes
  router.use(requireApiKey(config));

  /**
   * POST /api/builds/submit
   * Submit new build job
   */
  router.post(
    '/builds/submit',
    uploadBuildSubmission.fields([
      { name: 'source', maxCount: 1 },
      { name: 'certs', maxCount: 1 },
    ]),
    async (req: Request, res: Response) => {
      try {
        const files = req.files as { [fieldname: string]: Express.Multer.File[] };
        const { platform } = req.body;

        if (!files?.source?.[0]) {
          return res.status(400).json({ error: 'Source file required' });
        }

        if (!platform || !['ios', 'android'].includes(platform)) {
          return res.status(400).json({ error: 'Valid platform required (ios|android)' });
        }

        const buildId = nanoid();
        const timestamp = Date.now();

        // Save source zip
        const sourceStream = bufferToStream(files.source[0].buffer);
        const sourcePath = await storage.saveBuildSource(buildId, sourceStream);

        // Save certs if provided
        let certsPath: string | null = null;
        if (files.certs?.[0]) {
          const certsStream = bufferToStream(files.certs[0].buffer);
          certsPath = await storage.saveBuildCerts(buildId, certsStream);
        }

        // Create build record
        db.createBuild({
          id: buildId,
          status: 'pending',
          platform: platform as 'ios' | 'android',
          source_path: sourcePath,
          certs_path: certsPath,
          submitted_at: timestamp,
        });

        // Add to queue
        const build = db.getBuild(buildId)!;
        queue.enqueue(build);

        // Log
        db.addBuildLog({
          build_id: buildId,
          timestamp,
          level: 'info',
          message: 'Build submitted',
        });

        res.json({
          id: buildId,
          status: 'pending',
          submitted_at: timestamp,
        });
      } catch (err) {
        console.error('Build submission error:', err);
        res.status(500).json({ error: 'Build submission failed' });
      }
    }
  );

  /**
   * GET /api/builds/:id/status
   * Get build status
   */
  router.get('/builds/:id/status', (req: Request, res: Response) => {
    const build = db.getBuild(req.params.id);

    if (!build) {
      return res.status(404).json({ error: 'Build not found' });
    }

    res.json({
      id: build.id,
      status: build.status,
      platform: build.platform,
      worker_id: build.worker_id,
      submitted_at: build.submitted_at,
      started_at: build.started_at,
      completed_at: build.completed_at,
      error_message: build.error_message,
    });
  });

  /**
   * GET /api/builds/:id/download
   * Download build result
   */
  router.get('/builds/:id/download', (req: Request, res: Response) => {
    const build = db.getBuild(req.params.id);

    if (!build) {
      return res.status(404).json({ error: 'Build not found' });
    }

    if (build.status !== 'completed') {
      return res.status(400).json({ error: 'Build not completed' });
    }

    if (!build.result_path) {
      return res.status(404).json({ error: 'Build result not found' });
    }

    const extension = build.platform === 'ios' ? 'ipa' : 'apk';
    const filename = `${build.id}.${extension}`;

    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.setHeader('Content-Type', 'application/octet-stream');

    try {
      const stream = storage.createReadStream(build.result_path);
      pipeStreamSafely(stream, res, 'Failed to read build result');
    } catch (err) {
      console.error('File read error:', err);
      res.status(500).json({ error: 'Failed to read build result' });
    }
  });

  /**
   * GET /api/builds/:id/logs
   * Get build logs
   */
  router.get('/builds/:id/logs', (req: Request, res: Response) => {
    const build = db.getBuild(req.params.id);

    if (!build) {
      return res.status(404).json({ error: 'Build not found' });
    }

    const logs = db.getBuildLogs(req.params.id);

    res.json({
      build_id: req.params.id,
      logs: logs.map(log => ({
        timestamp: log.timestamp,
        level: log.level,
        message: log.message,
      })),
    });
  });

  /**
   * POST /api/workers/register
   * Register new worker
   */
  router.post('/workers/register', express.json(), (req: Request, res: Response) => {
    try {
      const { name, capabilities } = req.body;

      if (!name || !capabilities) {
        return res.status(400).json({ error: 'Name and capabilities required' });
      }

      const workerId = nanoid();
      const timestamp = Date.now();

      db.registerWorker({
        id: workerId,
        name,
        status: 'idle',
        capabilities: JSON.stringify(capabilities),
        registered_at: timestamp,
        last_seen_at: timestamp,
      });

      res.json({
        id: workerId,
        status: 'registered',
      });
    } catch (err) {
      console.error('Worker registration error:', err);
      res.status(500).json({ error: 'Worker registration failed' });
    }
  });

  /**
   * GET /workers/poll
   * Worker polls for available jobs
   * NOTE: Path is /workers/poll (not /api/workers/poll) because router is mounted at /api
   */
  router.get('/workers/poll', (req: Request, res: Response) => {
    try {
      const { worker_id } = req.query;

      if (!worker_id || typeof worker_id !== 'string') {
        return res.status(400).json({ error: 'worker_id required' });
      }

      const worker = db.getWorker(worker_id);
      if (!worker) {
        return res.status(404).json({ error: 'Worker not found' });
      }

      // Update last seen (but don't change status - worker may be building)
      const timestamp = Date.now();
      const currentWorker = db.getWorker(worker_id);
      if (currentWorker) {
        // Only update last_seen_at, preserve current status
        db.updateWorkerStatus(worker_id, currentWorker.status, timestamp);
      }

      // Check if worker already has active job
      if (queue.isWorkerBusy(worker_id)) {
        const activeBuild = queue.getWorkerBuild(worker_id);
        return res.json({
          job: {
            id: activeBuild!.id,
            platform: activeBuild!.platform,
            source_url: `/api/builds/${activeBuild!.id}/source`,
            certs_url: activeBuild!.certs_path
              ? `/api/builds/${activeBuild!.id}/certs`
              : null,
          },
        });
      }

      // Assign next pending build
      const build = queue.assignToWorker(worker);

      if (!build) {
        return res.json({ job: null }); // No jobs available
      }

      // ATOMIC: Assign build to worker in database with transaction
      // This prevents race condition where two workers claim same build
      const assigned = db.assignBuildToWorker(build.id, worker_id, timestamp);

      if (!assigned) {
        // Build was already assigned by another worker, try again
        return res.json({ job: null });
      }

      // Log
      db.addBuildLog({
        build_id: build.id,
        timestamp: Date.now(),
        level: 'info',
        message: `Assigned to worker ${worker.name}`,
      });

      res.json({
        job: {
          id: build.id,
          platform: build.platform,
          source_url: `/api/builds/${build.id}/source`,
          certs_url: build.certs_path ? `/api/builds/${build.id}/certs` : null,
        },
      });
    } catch (err) {
      console.error('Worker poll error:', err);
      res.status(500).json({ error: 'Poll failed' });
    }
  });

  /**
   * GET /builds/:id/source
   * Download build source (for workers)
   * SECURITY: Requires X-Worker-Id header matching assigned worker
   */
  router.get('/builds/:id/source', requireWorkerAccess(db), (req: Request, res: Response) => {
    const build = (req as any).build; // Attached by requireWorkerAccess middleware

    res.setHeader('Content-Disposition', `attachment; filename="${build.id}.zip"`);
    res.setHeader('Content-Type', 'application/zip');

    try {
      const stream = storage.createReadStream(build.source_path);
      pipeStreamSafely(stream, res, 'Failed to read source file');
    } catch (err) {
      console.error('File read error:', err);
      res.status(500).json({ error: 'Failed to read source file' });
    }
  });

  /**
   * GET /builds/:id/certs
   * Download build certs (for workers)
   * SECURITY: Requires X-Worker-Id header matching assigned worker
   */
  router.get('/builds/:id/certs', requireWorkerAccess(db), (req: Request, res: Response) => {
    const build = (req as any).build; // Attached by requireWorkerAccess middleware

    if (!build.certs_path) {
      return res.status(404).json({ error: 'Certs not found' });
    }

    res.setHeader('Content-Disposition', `attachment; filename="${build.id}-certs.zip"`);
    res.setHeader('Content-Type', 'application/zip');

    try {
      const stream = storage.createReadStream(build.certs_path);
      pipeStreamSafely(stream, res, 'Failed to read certs file');
    } catch (err) {
      console.error('File read error:', err);
      res.status(500).json({ error: 'Failed to read certs file' });
    }
  });

  /**
   * POST /api/workers/upload
   * Worker uploads build result
   */
  router.post(
    '/workers/upload',
    uploadResult.single('result'),
    async (req: Request, res: Response) => {
      try {
        const { build_id, worker_id, success, error_message } = req.body;
        const file = req.file;

        if (!build_id || !worker_id) {
          return res.status(400).json({ error: 'build_id and worker_id required' });
        }

        const build = db.getBuild(build_id);
        if (!build) {
          return res.status(404).json({ error: 'Build not found' });
        }

        const worker = db.getWorker(worker_id);
        if (!worker) {
          return res.status(404).json({ error: 'Worker not found' });
        }

        const timestamp = Date.now();

        if (success === 'true' && file) {
          // Save result
          const extension = build.platform === 'ios' ? 'ipa' : 'apk';
          const resultStream = bufferToStream(file.buffer);
          const resultPath = await storage.saveBuildResult(build_id, resultStream, extension);

          // Update build
          db.updateBuildStatus(build_id, 'completed', {
            result_path: resultPath,
            completed_at: timestamp,
          });

          // Update worker
          db.incrementWorkerBuilds(worker_id, true);
          db.updateWorkerStatus(worker_id, 'idle', timestamp);

          // Complete in queue
          queue.complete(build_id);

          // Log
          db.addBuildLog({
            build_id,
            timestamp,
            level: 'info',
            message: 'Build completed successfully',
          });

          res.json({ status: 'success' });
        } else {
          // Build failed
          db.updateBuildStatus(build_id, 'failed', {
            error_message: error_message || 'Build failed',
            completed_at: timestamp,
          });

          // Update worker
          db.incrementWorkerBuilds(worker_id, false);
          db.updateWorkerStatus(worker_id, 'idle', timestamp);

          // Fail in queue (don't requeue for now)
          queue.fail(build_id, false);

          // Log
          db.addBuildLog({
            build_id,
            timestamp,
            level: 'error',
            message: error_message || 'Build failed',
          });

          res.json({ status: 'failed' });
        }
      } catch (err) {
        console.error('Upload error:', err);
        res.status(500).json({ error: 'Upload failed' });
      }
    }
  );

  return router;
}
