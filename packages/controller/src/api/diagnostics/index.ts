import { FastifyPluginAsync } from 'fastify';
import type { DatabaseService } from '../../db/Database.js';
import type { ControllerConfig } from '../../domain/Config.js';

interface DiagnosticsPluginOptions {
  db: DatabaseService;
  config: ControllerConfig;
}

interface WorkerParams {
  worker_id: string;
}

interface LimitQuery {
  limit?: string;
}

interface DiagnosticReportBody {
  worker_id: string;
  status: 'healthy' | 'warning' | 'critical';
  duration_ms: number;
  auto_fixed?: boolean;
  checks: any[];
}

export const diagnosticsRoutes: FastifyPluginAsync<DiagnosticsPluginOptions> = async (
  fastify,
  { db, config }
) => {
  /**
   * POST /diagnostics/report
   * Receive diagnostic report from worker
   */
  fastify.post<{ Body: DiagnosticReportBody }>('/report', async (request, reply) => {
    try {
      const { worker_id, status, duration_ms, auto_fixed, checks } = request.body;

      // Validate required fields
      if (!worker_id || !status || duration_ms === undefined || !checks) {
        return reply.status(400).send({
          error: 'Missing required fields: worker_id, status, duration_ms, checks',
        });
      }

      // Validate status
      if (!['healthy', 'warning', 'critical'].includes(status)) {
        return reply.status(400).send({
          error: 'Invalid status. Must be: healthy, warning, or critical',
        });
      }

      // Validate worker exists
      const worker = db.getWorker(worker_id);
      if (!worker) {
        return reply.status(404).send({ error: 'Worker not found' });
      }

      // Validate checks is an array
      if (!Array.isArray(checks)) {
        return reply.status(400).send({ error: 'checks must be an array' });
      }

      // Save report
      const id = db.saveDiagnosticReport({
        worker_id,
        status,
        run_at: Date.now(),
        duration_ms,
        auto_fixed: auto_fixed ? 1 : 0,
        checks: JSON.stringify(checks),
      });

      return reply.send({ id, status: 'stored' });
    } catch (err) {
      fastify.log.error('Error saving diagnostic report:', err);
      return reply.status(500).send({ error: 'Failed to save diagnostic report' });
    }
  });

  /**
   * GET /diagnostics/:worker_id
   * Get diagnostic reports for a worker
   */
  fastify.get<{ Params: WorkerParams; Querystring: LimitQuery }>(
    '/:worker_id',
    async (request, reply) => {
      try {
        const { worker_id } = request.params;
        const limit = parseInt(request.query.limit || '10');

        // Validate worker exists
        const worker = db.getWorker(worker_id);
        if (!worker) {
          return reply.status(404).send({ error: 'Worker not found' });
        }

        const reports = db.getDiagnosticReports(worker_id, limit);

        // Parse checks JSON
        const parsedReports = reports.map((report) => ({
          ...report,
          auto_fixed: report.auto_fixed === 1,
          checks: JSON.parse(report.checks),
        }));

        return reply.send({ worker_id, reports: parsedReports });
      } catch (err) {
        fastify.log.error('Error fetching diagnostic reports:', err);
        return reply.status(500).send({ error: 'Failed to fetch diagnostic reports' });
      }
    }
  );

  /**
   * GET /diagnostics/:worker_id/latest
   * Get latest diagnostic report for a worker
   */
  fastify.get<{ Params: WorkerParams }>('/:worker_id/latest', async (request, reply) => {
    try {
      const { worker_id } = request.params;

      // Validate worker exists
      const worker = db.getWorker(worker_id);
      if (!worker) {
        return reply.status(404).send({ error: 'Worker not found' });
      }

      const report = db.getLatestDiagnostic(worker_id);

      if (!report) {
        return reply.status(404).send({ error: 'No diagnostic reports found' });
      }

      // Parse checks JSON
      const parsedReport = {
        ...report,
        auto_fixed: report.auto_fixed === 1,
        checks: JSON.parse(report.checks),
      };

      return reply.send(parsedReport);
    } catch (err) {
      fastify.log.error('Error fetching latest diagnostic:', err);
      return reply.status(500).send({ error: 'Failed to fetch latest diagnostic' });
    }
  });
};
