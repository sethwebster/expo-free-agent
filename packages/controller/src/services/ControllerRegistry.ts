import { Database } from '../db/Database';
import { EventLog } from './EventLog';
import { ControllerNode, ControllerNodeRow, controllerNodeFromRow } from '../domain/ControllerNode';

export interface RegistrationOptions {
  id: string;
  url: string;
  name: string;
  metadata?: Record<string, unknown>;
  ttl?: number; // milliseconds, default 5 minutes
}

export class ControllerRegistry {
  private readonly defaultTtl = 5 * 60 * 1000; // 5 minutes

  constructor(
    private db: Database,
    private eventLog: EventLog
  ) {}

  /**
   * Register controller node
   */
  async register(options: RegistrationOptions): Promise<ControllerNode> {
    const { id, url, name, metadata } = options;
    const ttl = options.ttl ?? this.defaultTtl;
    const now = Date.now();
    const expiresAt = now + ttl;

    // Check if already registered
    const existing = this.db.prepare<ControllerNodeRow>(
      'SELECT * FROM controller_nodes WHERE id = ?'
    ).get(id);

    if (existing) {
      // Update existing registration
      this.db.prepare(
        `UPDATE controller_nodes
         SET url = ?, name = ?, last_heartbeat_at = ?, expires_at = ?, is_active = 1, metadata = ?
         WHERE id = ?`
      ).run(url, name, now, expiresAt, metadata ? JSON.stringify(metadata) : null, id);

      await this.eventLog.append({
        eventType: 'controller:heartbeat',
        entityId: id,
        entityType: 'controller',
        payload: { url, name, expiresAt },
      });
    } else {
      // New registration
      this.db.prepare(
        `INSERT INTO controller_nodes (id, url, name, registered_at, last_heartbeat_at, expires_at, is_active, metadata)
         VALUES (?, ?, ?, ?, ?, ?, 1, ?)`
      ).run(id, url, name, now, now, expiresAt, metadata ? JSON.stringify(metadata) : null);

      await this.eventLog.append({
        eventType: 'controller:registered',
        entityId: id,
        entityType: 'controller',
        payload: { url, name, metadata },
      });
    }

    const row = this.db.prepare<ControllerNodeRow>(
      'SELECT * FROM controller_nodes WHERE id = ?'
    ).get(id);

    if (!row) {
      throw new Error('Failed to register controller');
    }

    return controllerNodeFromRow(row);
  }

  /**
   * Refresh heartbeat for controller
   */
  async heartbeat(id: string, ttl?: number): Promise<Date> {
    const actualTtl = ttl ?? this.defaultTtl;
    const now = Date.now();
    const expiresAt = now + actualTtl;

    const result = this.db.prepare(
      `UPDATE controller_nodes
       SET last_heartbeat_at = ?, expires_at = ?, is_active = 1
       WHERE id = ?`
    ).run(now, expiresAt, id);

    if (result.changes === 0) {
      throw new Error(`Controller ${id} not found`);
    }

    await this.eventLog.append({
      eventType: 'controller:heartbeat',
      entityId: id,
      entityType: 'controller',
      payload: { expiresAt },
    });

    return new Date(expiresAt);
  }

  /**
   * Get controller by ID
   */
  async getById(id: string): Promise<ControllerNode | null> {
    const row = this.db.prepare<ControllerNodeRow>(
      'SELECT * FROM controller_nodes WHERE id = ?'
    ).get(id);

    return row ? controllerNodeFromRow(row) : null;
  }

  /**
   * Get all active controllers
   */
  async getActive(): Promise<ControllerNode[]> {
    const now = Date.now();
    const rows = this.db.prepare<ControllerNodeRow>(
      'SELECT * FROM controller_nodes WHERE is_active = 1 AND expires_at > ?'
    ).all(now);

    return rows.map(controllerNodeFromRow);
  }

  /**
   * Get all controllers (including expired)
   */
  async getAll(): Promise<ControllerNode[]> {
    const rows = this.db.prepare<ControllerNodeRow>(
      'SELECT * FROM controller_nodes ORDER BY registered_at DESC'
    ).all();

    return rows.map(controllerNodeFromRow);
  }

  /**
   * Expire stale controllers (background task)
   */
  async expireStale(): Promise<string[]> {
    const now = Date.now();

    // Find expired controllers
    const expired = this.db.prepare<{ id: string }>(
      'SELECT id FROM controller_nodes WHERE is_active = 1 AND expires_at <= ?'
    ).all(now);

    if (expired.length === 0) {
      return [];
    }

    const expiredIds = expired.map(r => r.id);

    // Mark as inactive
    this.db.prepare(
      'UPDATE controller_nodes SET is_active = 0 WHERE id IN (' +
      expiredIds.map(() => '?').join(',') + ')'
    ).run(...expiredIds);

    // Log expiration events
    for (const id of expiredIds) {
      await this.eventLog.append({
        eventType: 'controller:expired',
        entityId: id,
        entityType: 'controller',
        payload: { expiredAt: now },
      });
    }

    return expiredIds;
  }

  /**
   * Count active controllers
   */
  async countActive(): Promise<number> {
    const now = Date.now();
    const result = this.db.prepare<{ count: number }>(
      'SELECT COUNT(*) as count FROM controller_nodes WHERE is_active = 1 AND expires_at > ?'
    ).get(now);
    return result?.count ?? 0;
  }

  /**
   * Remove controller (permanent delete)
   */
  async remove(id: string): Promise<void> {
    this.db.prepare('DELETE FROM controller_nodes WHERE id = ?').run(id);
  }
}
