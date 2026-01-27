import { Database as BunDatabase } from 'bun:sqlite';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

export interface Worker {
  id: string;
  name: string;
  status: 'idle' | 'building' | 'offline';
  capabilities: string; // JSON
  registered_at: number;
  last_seen_at: number;
  builds_completed: number;
  builds_failed: number;
}

export interface Build {
  id: string;
  status: 'pending' | 'assigned' | 'building' | 'completed' | 'failed';
  platform: 'ios' | 'android';
  source_path: string;
  certs_path: string | null;
  result_path: string | null;
  worker_id: string | null;
  submitted_at: number;
  started_at: number | null;
  completed_at: number | null;
  error_message: string | null;
}

export interface BuildLog {
  id: number;
  build_id: string;
  timestamp: number;
  level: 'info' | 'warn' | 'error';
  message: string;
}

export interface DiagnosticReport {
  id: string;
  worker_id: string;
  status: 'healthy' | 'warning' | 'critical';
  run_at: number;
  duration_ms: number;
  auto_fixed: number; // SQLite boolean (0 or 1)
  checks: string; // JSON array
}

export class DatabaseService {
  private db: BunDatabase;

  constructor(dbPath: string) {
    this.db = new BunDatabase(dbPath);
    this.initSchema();
  }

  private initSchema() {
    const schema = readFileSync(join(__dirname, 'schema.sql'), 'utf-8');
    this.db.exec(schema);
  }

  // Workers
  registerWorker(worker: Omit<Worker, 'builds_completed' | 'builds_failed'>) {
    const stmt = this.db.prepare(`
      INSERT INTO workers (id, name, status, capabilities, registered_at, last_seen_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `);
    stmt.run(
      worker.id,
      worker.name,
      worker.status,
      worker.capabilities,
      worker.registered_at,
      worker.last_seen_at
    );
  }

  updateWorkerStatus(id: string, status: Worker['status'], lastSeenAt: number) {
    const stmt = this.db.prepare(`
      UPDATE workers
      SET status = ?, last_seen_at = ?
      WHERE id = ?
    `);
    stmt.run(status, lastSeenAt, id);
  }

  getWorker(id: string): Worker | undefined {
    const stmt = this.db.prepare('SELECT * FROM workers WHERE id = ?');
    return stmt.get(id) as Worker | undefined;
  }

  getAllWorkers(): Worker[] {
    const stmt = this.db.prepare('SELECT * FROM workers ORDER BY last_seen_at DESC');
    return stmt.all() as Worker[];
  }

  getIdleWorkers(): Worker[] {
    const stmt = this.db.prepare(`
      SELECT * FROM workers
      WHERE status = 'idle'
      ORDER BY builds_completed ASC
    `);
    return stmt.all() as Worker[];
  }

  incrementWorkerBuilds(workerId: string, success: boolean) {
    const field = success ? 'builds_completed' : 'builds_failed';
    const stmt = this.db.prepare(`
      UPDATE workers
      SET ${field} = ${field} + 1
      WHERE id = ?
    `);
    stmt.run(workerId);
  }

  // Builds
  createBuild(build: Omit<Build, 'worker_id' | 'started_at' | 'completed_at' | 'error_message' | 'result_path'>) {
    const stmt = this.db.prepare(`
      INSERT INTO builds (id, status, platform, source_path, certs_path, submitted_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `);
    stmt.run(
      build.id,
      build.status,
      build.platform,
      build.source_path,
      build.certs_path,
      build.submitted_at
    );
  }

  getBuild(id: string): Build | undefined {
    const stmt = this.db.prepare('SELECT * FROM builds WHERE id = ?');
    return stmt.get(id) as Build | undefined;
  }

  getAllBuilds(): Build[] {
    const stmt = this.db.prepare('SELECT * FROM builds ORDER BY submitted_at DESC');
    return stmt.all() as Build[];
  }

  updateBuildStatus(
    id: string,
    status: Build['status'],
    updates: {
      worker_id?: string;
      started_at?: number;
      completed_at?: number;
      error_message?: string;
      result_path?: string;
    } = {}
  ) {
    const fields = ['status = ?'];
    const values = [status];

    if (updates.worker_id !== undefined) {
      fields.push('worker_id = ?');
      values.push(updates.worker_id);
    }
    if (updates.started_at !== undefined) {
      fields.push('started_at = ?');
      values.push(updates.started_at);
    }
    if (updates.completed_at !== undefined) {
      fields.push('completed_at = ?');
      values.push(updates.completed_at);
    }
    if (updates.error_message !== undefined) {
      fields.push('error_message = ?');
      values.push(updates.error_message);
    }
    if (updates.result_path !== undefined) {
      fields.push('result_path = ?');
      values.push(updates.result_path);
    }

    values.push(id);

    const stmt = this.db.prepare(`
      UPDATE builds
      SET ${fields.join(', ')}
      WHERE id = ?
    `);
    stmt.run(...values);
  }

  getPendingBuilds(): Build[] {
    const stmt = this.db.prepare(`
      SELECT * FROM builds
      WHERE status = 'pending'
      ORDER BY submitted_at ASC
    `);
    return stmt.all() as Build[];
  }

  getAssignedBuilds(): Build[] {
    const stmt = this.db.prepare(`
      SELECT * FROM builds
      WHERE status = 'assigned'
      ORDER BY started_at ASC
    `);
    return stmt.all() as Build[];
  }

  /**
   * Atomic transaction: assign build to worker
   * Prevents race condition where two workers claim same build
   */
  assignBuildToWorker(buildId: string, workerId: string, timestamp: number): boolean {
    try {
      // Use transaction to make assignment atomic
      this.db.exec('BEGIN IMMEDIATE');

      // Check build is still pending
      const checkStmt = this.db.prepare('SELECT status FROM builds WHERE id = ?');
      const build = checkStmt.get(buildId) as { status: string } | undefined;

      if (!build || build.status !== 'pending') {
        this.db.exec('ROLLBACK');
        return false;
      }

      // Assign build
      const updateStmt = this.db.prepare(`
        UPDATE builds
        SET status = 'assigned', worker_id = ?, started_at = ?
        WHERE id = ?
      `);
      updateStmt.run(workerId, timestamp, buildId);

      // Update worker
      const workerStmt = this.db.prepare(`
        UPDATE workers
        SET status = 'building', last_seen_at = ?
        WHERE id = ?
      `);
      workerStmt.run(timestamp, workerId);

      this.db.exec('COMMIT');
      return true;
    } catch (err) {
      this.db.exec('ROLLBACK');
      throw err;
    }
  }

  // Build Logs
  addBuildLog(log: Omit<BuildLog, 'id'>) {
    const stmt = this.db.prepare(`
      INSERT INTO build_logs (build_id, timestamp, level, message)
      VALUES (?, ?, ?, ?)
    `);
    stmt.run(log.build_id, log.timestamp, log.level, log.message);
  }

  getBuildLogs(buildId: string): BuildLog[] {
    const stmt = this.db.prepare(`
      SELECT * FROM build_logs
      WHERE build_id = ?
      ORDER BY timestamp ASC
    `);
    return stmt.all(buildId) as BuildLog[];
  }

  // Diagnostics
  saveDiagnosticReport(report: Omit<DiagnosticReport, 'id'>): string {
    const id = crypto.randomUUID();
    const stmt = this.db.prepare(`
      INSERT INTO diagnostics (id, worker_id, status, run_at, duration_ms, auto_fixed, checks)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `);
    stmt.run(
      id,
      report.worker_id,
      report.status,
      report.run_at,
      report.duration_ms,
      report.auto_fixed,
      report.checks
    );
    return id;
  }

  getDiagnosticReports(workerId: string, limit: number = 10): DiagnosticReport[] {
    const stmt = this.db.prepare(`
      SELECT * FROM diagnostics
      WHERE worker_id = ?
      ORDER BY run_at DESC
      LIMIT ?
    `);
    return stmt.all(workerId, limit) as DiagnosticReport[];
  }

  getLatestDiagnostic(workerId: string): DiagnosticReport | undefined {
    const stmt = this.db.prepare(`
      SELECT * FROM diagnostics
      WHERE worker_id = ?
      ORDER BY run_at DESC
      LIMIT 1
    `);
    return stmt.get(workerId) as DiagnosticReport | undefined;
  }

  close() {
    this.db.close();
  }
}
