import { Router, Request, Response } from 'express';
import type { DatabaseService } from '../db/Database.js';
import type { ControllerConfig } from '../domain/Config.js';
import { requireApiKey } from '../middleware/auth.js';

export function createDiagnosticsRoutes(
  db: DatabaseService,
  config: ControllerConfig
): Router {
  const router = Router();

  // Apply API key authentication
  router.use(requireApiKey(config));

  /**
   * POST /api/diagnostics/report
   * Receive diagnostic report from worker
   */
  router.post('/report', async (req: Request, res: Response) => {
    try {
      const { worker_id, status, duration_ms, auto_fixed, checks } = req.body;

      // Validate required fields
      if (!worker_id || !status || duration_ms === undefined || !checks) {
        return res.status(400).json({
          error: 'Missing required fields: worker_id, status, duration_ms, checks',
        });
      }

      // Validate status
      if (!['healthy', 'warning', 'critical'].includes(status)) {
        return res.status(400).json({
          error: 'Invalid status. Must be: healthy, warning, or critical',
        });
      }

      // Validate worker exists
      const worker = db.getWorker(worker_id);
      if (!worker) {
        return res.status(404).json({ error: 'Worker not found' });
      }

      // Validate checks is an array
      if (!Array.isArray(checks)) {
        return res.status(400).json({ error: 'checks must be an array' });
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

      res.json({ id, status: 'stored' });
    } catch (err) {
      console.error('Error saving diagnostic report:', err);
      res.status(500).json({ error: 'Failed to save diagnostic report' });
    }
  });

  /**
   * GET /api/diagnostics/:worker_id
   * Get diagnostic reports for a worker
   */
  router.get('/:worker_id', async (req: Request, res: Response) => {
    try {
      const { worker_id } = req.params;
      const limit = parseInt(req.query.limit as string) || 10;

      // Validate worker exists
      const worker = db.getWorker(worker_id);
      if (!worker) {
        return res.status(404).json({ error: 'Worker not found' });
      }

      const reports = db.getDiagnosticReports(worker_id, limit);

      // Parse checks JSON
      const parsedReports = reports.map((report) => ({
        ...report,
        auto_fixed: report.auto_fixed === 1,
        checks: JSON.parse(report.checks),
      }));

      res.json({ worker_id, reports: parsedReports });
    } catch (err) {
      console.error('Error fetching diagnostic reports:', err);
      res.status(500).json({ error: 'Failed to fetch diagnostic reports' });
    }
  });

  /**
   * GET /api/diagnostics/:worker_id/latest
   * Get latest diagnostic report for a worker
   */
  router.get('/:worker_id/latest', async (req: Request, res: Response) => {
    try {
      const { worker_id } = req.params;

      // Validate worker exists
      const worker = db.getWorker(worker_id);
      if (!worker) {
        return res.status(404).json({ error: 'Worker not found' });
      }

      const report = db.getLatestDiagnostic(worker_id);

      if (!report) {
        return res.status(404).json({ error: 'No diagnostic reports found' });
      }

      // Parse checks JSON
      const parsedReport = {
        ...report,
        auto_fixed: report.auto_fixed === 1,
        checks: JSON.parse(report.checks),
      };

      res.json(parsedReport);
    } catch (err) {
      console.error('Error fetching latest diagnostic:', err);
      res.status(500).json({ error: 'Failed to fetch latest diagnostic' });
    }
  });

  return router;
}
