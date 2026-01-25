import { FastifyPluginAsync, FastifyRequest, FastifyReply } from 'fastify';
import { nanoid } from 'nanoid';
import type { DatabaseService } from '../../db/Database.js';
import type { JobQueue } from '../../services/JobQueue.js';
import type { FileStorage } from '../../services/FileStorage.js';
import type { ControllerConfig } from '../../domain/Config.js';

interface WorkersPluginOptions {
  db: DatabaseService;
  queue: JobQueue;
  storage: FileStorage;
  config: ControllerConfig;
}

interface WorkerParams {
  id: string;
}

interface PollQuery {
  worker_id?: string;
}

interface RegisterBody {
  name: string;
  capabilities: any;
}

interface UploadBody {
  build_id: string;
  worker_id: string;
  success: string;
  error_message?: string;
}

export const workersRoutes: FastifyPluginAsync<WorkersPluginOptions> = async (
  fastify,
  { db, queue, storage, config }
) => {
  /**
   * POST /workers/register
   * Register new worker
   */
  fastify.post<{ Body: RegisterBody }>('/register', async (request, reply) => {
    try {
      const { name, capabilities } = request.body;

      if (!name || !capabilities) {
        return reply.status(400).send({ error: 'Name and capabilities required' });
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

      return reply.send({
        id: workerId,
        status: 'registered',
      });
    } catch (err) {
      fastify.log.error('Worker registration error:', err);
      return reply.status(500).send({ error: 'Worker registration failed' });
    }
  });

  /**
   * GET /workers/poll
   * Worker polls for available jobs
   */
  fastify.get<{ Querystring: PollQuery }>('/poll', async (request, reply) => {
    try {
      const { worker_id } = request.query;

      if (!worker_id) {
        return reply.status(400).send({ error: 'worker_id required' });
      }

      const worker = db.getWorker(worker_id);
      if (!worker) {
        return reply.status(404).send({ error: 'Worker not found' });
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
        return reply.send({
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
        return reply.send({ job: null }); // No jobs available
      }

      // ATOMIC: Assign build to worker in database with transaction
      // This prevents race condition where two workers claim same build
      const assigned = db.assignBuildToWorker(build.id, worker_id, timestamp);

      if (!assigned) {
        // Build was already assigned by another worker, try again
        return reply.send({ job: null });
      }

      // Log
      db.addBuildLog({
        build_id: build.id,
        timestamp: Date.now(),
        level: 'info',
        message: `Assigned to worker ${worker.name}`,
      });

      return reply.send({
        job: {
          id: build.id,
          platform: build.platform,
          source_url: `/api/builds/${build.id}/source`,
          certs_url: build.certs_path ? `/api/builds/${build.id}/certs` : null,
        },
      });
    } catch (err) {
      fastify.log.error('Worker poll error:', err);
      return reply.status(500).send({ error: 'Poll failed' });
    }
  });

  /**
   * POST /workers/upload
   * Worker uploads build result
   */
  fastify.post('/upload', async (request, reply) => {
    try {
      if (!request.isMultipart()) {
        return reply.status(400).send({ error: 'Content must be multipart/form-data' });
      }

      const parts = request.parts();
      let resultBuffer: Buffer | null = null;
      let build_id: string | null = null;
      let worker_id: string | null = null;
      let success: string | null = null;
      let error_message: string | undefined = undefined;

      for await (const part of parts) {
        if (part.type === 'file') {
          if (part.fieldname === 'result') {
            const chunks: Buffer[] = [];
            for await (const chunk of part.file) {
              chunks.push(chunk);
            }
            resultBuffer = Buffer.concat(chunks);

            if (resultBuffer.length > config.maxResultFileSize) {
              return reply.status(413).send({ error: 'Result file too large' });
            }
          }
        } else {
          if (part.fieldname === 'build_id') {
            build_id = part.value as string;
          } else if (part.fieldname === 'worker_id') {
            worker_id = part.value as string;
          } else if (part.fieldname === 'success') {
            success = part.value as string;
          } else if (part.fieldname === 'error_message') {
            error_message = part.value as string;
          }
        }
      }

      if (!build_id || !worker_id) {
        return reply.status(400).send({ error: 'build_id and worker_id required' });
      }

      const build = db.getBuild(build_id);
      if (!build) {
        return reply.status(404).send({ error: 'Build not found' });
      }

      const worker = db.getWorker(worker_id);
      if (!worker) {
        return reply.status(404).send({ error: 'Worker not found' });
      }

      const timestamp = Date.now();

      if (success === 'true' && resultBuffer) {
        // Save result
        const extension = build.platform === 'ios' ? 'ipa' : 'apk';
        const resultStream = require('stream').Readable.from(resultBuffer);
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

        return reply.send({ status: 'success' });
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

        return reply.send({ status: 'failed' });
      }
    } catch (err) {
      fastify.log.error('Upload error:', err);
      return reply.status(500).send({ error: 'Upload failed' });
    }
  });

  /**
   * GET /workers/:id/stats
   * Get worker statistics
   */
  fastify.get<{ Params: WorkerParams }>('/:id/stats', async (request, reply) => {
    try {
      const worker = db.getWorker(request.params.id);

      if (!worker) {
        return reply.status(404).send({ error: 'Worker not found' });
      }

      const totalBuilds = worker.builds_completed + worker.builds_failed;
      const uptime = Date.now() - worker.registered_at;

      // Format uptime as human-readable string
      const uptimeSeconds = Math.floor(uptime / 1000);
      const uptimeMinutes = Math.floor(uptimeSeconds / 60);
      const uptimeHours = Math.floor(uptimeMinutes / 60);
      const uptimeDays = Math.floor(uptimeHours / 24);

      let uptimeStr: string;
      if (uptimeDays > 0) {
        uptimeStr = `${uptimeDays}d ${uptimeHours % 24}h`;
      } else if (uptimeHours > 0) {
        uptimeStr = `${uptimeHours}h ${uptimeMinutes % 60}m`;
      } else if (uptimeMinutes > 0) {
        uptimeStr = `${uptimeMinutes}m ${uptimeSeconds % 60}s`;
      } else {
        uptimeStr = `${uptimeSeconds}s`;
      }

      return reply.send({
        totalBuilds,
        successfulBuilds: worker.builds_completed,
        failedBuilds: worker.builds_failed,
        workerName: worker.name,
        status: worker.status,
        uptime: uptimeStr,
      });
    } catch (err) {
      fastify.log.error('Stats error:', err);
      return reply.status(500).send({ error: 'Failed to fetch stats' });
    }
  });
};
