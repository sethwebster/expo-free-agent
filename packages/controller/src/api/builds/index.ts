import { FastifyPluginAsync, FastifyRequest, FastifyReply } from 'fastify';
import { nanoid } from 'nanoid';
import crypto from 'crypto';
import type { DatabaseService } from '../../db/Database.js';
import type { JobQueue } from '../../services/JobQueue.js';
import type { FileStorage } from '../../services/FileStorage.js';
import { unzipCerts } from '../../services/FileStorage.js';
import type { ControllerConfig } from '../../domain/Config.js';
import { requireWorkerAccess, requireBuildAccess } from '../../middleware/auth.js';

interface BuildsPluginOptions {
  db: DatabaseService;
  queue: JobQueue;
  storage: FileStorage;
  config: ControllerConfig;
}

interface BuildParams {
  id: string;
}

interface WorkerQuery {
  worker_id?: string;
}

interface HeartbeatBody {
  progress?: number;
}

export const buildsRoutes: FastifyPluginAsync<BuildsPluginOptions> = async (
  fastify,
  { db, queue, storage, config }
) => {
  /**
   * POST /builds/submit
   * Submit new build job
   */
  fastify.post('/submit', async (request, reply) => {
    try {
      if (!request.isMultipart()) {
        return reply.status(400).send({ error: 'Content must be multipart/form-data' });
      }

      const parts = request.parts();
      let sourceBuffer: Buffer | null = null;
      let certsBuffer: Buffer | null = null;
      let platform: string | null = null;

      for await (const part of parts) {
        if (part.type === 'file') {
          if (part.fieldname === 'source') {
            const chunks: Buffer[] = [];
            for await (const chunk of part.file) {
              chunks.push(chunk);
            }
            sourceBuffer = Buffer.concat(chunks);

            if (sourceBuffer.length > config.maxSourceFileSize) {
              return reply.status(413).send({ error: 'Source file too large' });
            }
          } else if (part.fieldname === 'certs') {
            const chunks: Buffer[] = [];
            for await (const chunk of part.file) {
              chunks.push(chunk);
            }
            certsBuffer = Buffer.concat(chunks);

            if (certsBuffer.length > config.maxCertsFileSize) {
              return reply.status(413).send({ error: 'Certs file too large' });
            }
          }
        } else {
          if (part.fieldname === 'platform') {
            platform = part.value as string;
          }
        }
      }

      if (!sourceBuffer) {
        return reply.status(400).send({ error: 'Source file required' });
      }

      if (!platform || !['ios', 'android'].includes(platform)) {
        return reply.status(400).send({ error: 'Valid platform required (ios|android)' });
      }

      const buildId = nanoid();
      const timestamp = Date.now();

      // Save source zip
      const sourcePath = await storage.saveBuildSource(
        buildId,
        require('stream').Readable.from(sourceBuffer)
      );

      // Save certs if provided
      let certsPath: string | null = null;
      if (certsBuffer) {
        certsPath = await storage.saveBuildCerts(
          buildId,
          require('stream').Readable.from(certsBuffer)
        );
      }

      // Generate unique access token for this build
      const accessToken = crypto.randomBytes(32).toString('base64url');

      // Create build record
      db.createBuild({
        id: buildId,
        status: 'pending',
        platform: platform as 'ios' | 'android',
        source_path: sourcePath,
        certs_path: certsPath,
        submitted_at: timestamp,
        access_token: accessToken,
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

      return reply.send({
        id: buildId,
        status: 'pending',
        submitted_at: timestamp,
        access_token: accessToken,
      });
    } catch (err) {
      fastify.log.error('Build submission error:', err);
      return reply.status(500).send({ error: 'Build submission failed' });
    }
  });

  /**
   * GET /builds
   * List all builds
   */
  fastify.get('/', async (request, reply) => {
    const allBuilds = db.getAllBuilds();

    const builds = allBuilds.map((b) => ({
      id: b.id,
      status: b.status,
      createdAt: new Date(b.submitted_at).toISOString(),
      completedAt: b.completed_at ? new Date(b.completed_at).toISOString() : undefined,
    }));

    return reply.send(builds);
  });

  /**
   * GET /builds/active
   * List currently running builds
   */
  fastify.get('/active', async (request, reply) => {
    const activeBuilds = db
      .getAllBuilds()
      .filter((b) => b.status === 'assigned' || b.status === 'building');

    const builds = activeBuilds.map((b) => ({
      id: b.id,
      status: b.status,
      platform: b.platform,
      worker_id: b.worker_id,
      started_at: b.started_at,
    }));

    return reply.send({ builds });
  });

  /**
   * GET /builds/:id/status
   * Get build status
   * Requires: X-API-Key (admin) OR X-Build-Token (build submitter)
   */
  fastify.get<{ Params: BuildParams }>(
    '/:id/status',
    {
      preHandler: requireBuildAccess(config, db),
    },
    async (request, reply) => {
      const build = db.getBuild(request.params.id);

      if (!build) {
        return reply.status(404).send({ error: 'Build not found' });
      }

      return reply.send({
        id: build.id,
        status: build.status,
        platform: build.platform,
        worker_id: build.worker_id,
        submitted_at: build.submitted_at,
        started_at: build.started_at,
        completed_at: build.completed_at,
        error_message: build.error_message,
      });
    }
  );

  /**
   * GET /builds/:id/logs
   * Get build logs
   * Requires: X-API-Key (admin) OR X-Build-Token (build submitter)
   */
  fastify.get<{ Params: BuildParams }>(
    '/:id/logs',
    {
      preHandler: requireBuildAccess(config, db),
    },
    async (request, reply) => {
      const build = db.getBuild(request.params.id);

      if (!build) {
        return reply.status(404).send({ error: 'Build not found' });
      }

      const logs = db.getBuildLogs(request.params.id);

      return reply.send({
        build_id: request.params.id,
        logs: logs.map((log) => ({
          timestamp: log.timestamp,
          level: log.level,
          message: log.message,
        })),
      });
    }
  );

  /**
   * GET /builds/:id/download
   * Download build result
   * Requires: X-API-Key (admin) OR X-Build-Token (build submitter)
   */
  fastify.get<{ Params: BuildParams }>(
    '/:id/download',
    {
      preHandler: requireBuildAccess(config, db),
    },
    async (request, reply) => {
      const build = db.getBuild(request.params.id);

      if (!build) {
        return reply.status(404).send({ error: 'Build not found' });
      }

      if (build.status !== 'completed') {
        return reply.status(400).send({ error: 'Build not completed' });
      }

      if (!build.result_path) {
        return reply.status(404).send({ error: 'Build result not found' });
      }

      const extension = build.platform === 'ios' ? 'ipa' : 'apk';
      const filename = `${build.id}.${extension}`;

      try {
        const stream = storage.createReadStream(build.result_path);

        return reply
          .header('Content-Disposition', `attachment; filename="${filename}"`)
          .header('Content-Type', 'application/octet-stream')
          .send(stream);
      } catch (err) {
        fastify.log.error('File read error:', err);
        return reply.status(500).send({ error: 'Failed to read build result' });
      }
    }
  );

  /**
   * GET /builds/:id/source
   * Download build source (for workers)
   * SECURITY: Requires X-Worker-Id header matching assigned worker
   */
  fastify.get<{ Params: BuildParams }>(
    '/:id/source',
    {
      preHandler: requireWorkerAccess(db),
    },
    async (request, reply) => {
      const build = (request as any).build;

      try {
        const stream = storage.createReadStream(build.source_path);

        return reply
          .header('Content-Disposition', `attachment; filename="${build.id}.zip"`)
          .header('Content-Type', 'application/zip')
          .send(stream);
      } catch (err) {
        fastify.log.error('File read error:', err);
        return reply.status(500).send({ error: 'Failed to read source file' });
      }
    }
  );

  /**
   * GET /builds/:id/certs
   * Download build certs (for workers)
   * SECURITY: Requires X-Worker-Id header matching assigned worker
   */
  fastify.get<{ Params: BuildParams }>(
    '/:id/certs',
    {
      preHandler: requireWorkerAccess(db),
    },
    async (request, reply) => {
      const build = (request as any).build;

      if (!build.certs_path) {
        return reply.status(404).send({ error: 'Certs not found' });
      }

      try {
        const stream = storage.createReadStream(build.certs_path);

        return reply
          .header('Content-Disposition', `attachment; filename="${build.id}-certs.zip"`)
          .header('Content-Type', 'application/zip')
          .send(stream);
      } catch (err) {
        fastify.log.error('File read error:', err);
        return reply.status(500).send({ error: 'Failed to read certs file' });
      }
    }
  );

  /**
   * GET /builds/:id/certs-secure
   * Get build certs in secure JSON format for VM bootstrap
   * SECURITY: Requires X-Worker-Id and X-Build-Id headers
   * Returns: { p12: base64, p12Password: string, keychainPassword: random, provisioningProfiles: [base64...] }
   */
  fastify.get<{ Params: BuildParams }>(
    '/:id/certs-secure',
    {
      preHandler: requireWorkerAccess(db, true),
    },
    async (request, reply) => {
      const build = (request as any).build;

      if (!build.certs_path) {
        return reply.status(404).send({ error: 'Certs not found' });
      }

      try {
        // Generate random keychain password (24 bytes = 32 chars base64)
        const keychainPassword = crypto.randomBytes(24).toString('base64');

        // Read and unzip certs
        const certsBuffer = storage.readBuildCerts(build.certs_path);
        const { p12, password, profiles } = unzipCerts(certsBuffer);

        return reply.send({
          p12: p12.toString('base64'),
          p12Password: password,
          keychainPassword,
          provisioningProfiles: profiles.map((p) => p.toString('base64')),
        });
      } catch (err) {
        fastify.log.error('Failed to read/unzip certs:', err);
        return reply.status(500).send({ error: 'Failed to process certs file' });
      }
    }
  );

  /**
   * POST /builds/:id/heartbeat
   * Worker sends heartbeat during build to prove it's alive
   */
  fastify.post<{
    Params: BuildParams;
    Querystring: WorkerQuery;
    Body: HeartbeatBody;
  }>('/:id/heartbeat', async (request, reply) => {
    try {
      const { worker_id } = request.query;
      const { progress } = request.body;

      if (!worker_id) {
        return reply.status(400).send({ error: 'worker_id required' });
      }

      const build = db.getBuild(request.params.id);
      if (!build) {
        return reply.status(404).send({ error: 'Build not found' });
      }

      // Verify worker owns this build
      if (build.worker_id !== worker_id) {
        return reply.status(403).send({ error: 'Build not assigned to this worker' });
      }

      // Update heartbeat timestamp
      const timestamp = Date.now();
      db.run('UPDATE builds SET last_heartbeat_at = ? WHERE id = ?', [
        timestamp,
        request.params.id,
      ]);

      // Optionally log progress
      if (progress !== undefined) {
        db.addBuildLog({
          build_id: request.params.id,
          timestamp,
          level: 'info',
          message: `Build progress: ${progress}%`,
        });
      }

      return reply.send({ status: 'ok', timestamp });
    } catch (err) {
      fastify.log.error('Heartbeat error:', err);
      return reply.status(500).send({ error: 'Heartbeat failed' });
    }
  });

  /**
   * POST /builds/:id/telemetry
   * Receive detailed telemetry from VM monitor (CPU, memory, build stage, etc.)
   */
  fastify.post<{
    Params: BuildParams;
    Body: {
      type: string;
      timestamp: string;
      data: any;
    };
  }>(
    '/:id/telemetry',
    { preHandler: requireWorkerAccess(db, true) },
    async (request, reply) => {
      try {
        const { type, timestamp, data } = request.body;
        const buildId = request.params.id;

        // Log telemetry event
        const logLevel = type === 'monitor_started' ? 'info' : 'debug';
        const message = formatTelemetryMessage(type, data);

        db.addBuildLog({
          build_id: buildId,
          timestamp: Date.now(),
          level: logLevel,
          message,
        });

        // Update last heartbeat
        db.run('UPDATE builds SET last_heartbeat_at = ? WHERE id = ?', [
          Date.now(),
          buildId,
        ]);

        return reply.send({ status: 'ok' });
      } catch (err) {
        fastify.log.error('Telemetry error:', err);
        return reply.status(500).send({ error: 'Telemetry failed' });
      }
    }
  );

  /**
   * POST /builds/:id/cancel
   * Cancel a stuck or running build
   */
  fastify.post<{ Params: BuildParams }>('/:id/cancel', async (request, reply) => {
    try {
      const build = db.getBuild(request.params.id);

      if (!build) {
        return reply.status(404).send({ error: 'Build not found' });
      }

      if (build.status === 'completed' || build.status === 'failed') {
        return reply.status(400).send({ error: 'Build already finished' });
      }

      const timestamp = Date.now();

      // Update build status
      db.updateBuildStatus(request.params.id, 'failed', {
        error_message: 'Build cancelled by user',
        completed_at: timestamp,
      });

      // If assigned to worker, mark worker as idle
      if (build.worker_id) {
        const worker = db.getWorker(build.worker_id);
        if (worker) {
          db.updateWorkerStatus(build.worker_id, 'idle', timestamp);
        }
      }

      // Remove from queue
      queue.fail(request.params.id, false);

      // Log
      db.addBuildLog({
        build_id: request.params.id,
        timestamp,
        level: 'info',
        message: 'Build cancelled',
      });

      return reply.send({ status: 'cancelled' });
    } catch (err) {
      fastify.log.error('Cancel error:', err);
      return reply.status(500).send({ error: 'Cancel failed' });
    }
  });
};

/**
 * Format telemetry data into human-readable log message
 */
function formatTelemetryMessage(type: string, data: any): string {
  switch (type) {
    case 'monitor_started':
      return '[VM] Monitor started';

    case 'heartbeat':
      const { stage, metrics, heartbeat_count } = data;
      const cpu = metrics?.cpu_percent || 0;
      const mem = metrics?.memory_mb || 0;
      const disk = metrics?.disk_percent || 0;

      return `[VM] Stage: ${stage} | CPU: ${cpu.toFixed(1)}% | Mem: ${mem}MB | Disk: ${disk}% | Beat: ${heartbeat_count}`;

    default:
      return `[VM] ${type}: ${JSON.stringify(data)}`;
  }
}
