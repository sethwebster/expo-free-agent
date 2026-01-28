import { Database } from '../db/Database';
import { EventLog } from './EventLog';
import { ControllerRegistry } from './ControllerRegistry';
import { Event } from '../domain/Event';

export interface PropagationRecord {
  eventId: string;
  controllerId: string;
  propagatedAt: number;
}

export class EventBroadcaster {
  constructor(
    private db: Database,
    private eventLog: EventLog,
    private registry: ControllerRegistry,
    private apiKey: string
  ) {}

  /**
   * Receive event from another controller
   */
  async receive(event: Event): Promise<void> {
    // Insert event (validates hash and deduplicates)
    await this.eventLog.receive(event);

    // Mark as seen from source controller
    await this.markPropagated(event.id, event.sourceControllerId);

    // Broadcast to other controllers (except source)
    await this.broadcast(event, [event.sourceControllerId]);
  }

  /**
   * Check if event has been propagated to controller
   */
  async hasSeenEvent(eventId: string, controllerId: string): Promise<boolean> {
    const row = this.db.prepare<PropagationRecord>(
      'SELECT * FROM event_propagation WHERE event_id = ? AND controller_id = ?'
    ).get(eventId, controllerId);

    return row !== undefined;
  }

  /**
   * Mark event as propagated to controller
   */
  async markPropagated(eventId: string, controllerId: string): Promise<void> {
    const now = Date.now();

    // Use INSERT OR IGNORE to avoid errors on duplicate
    this.db.prepare(
      'INSERT OR IGNORE INTO event_propagation (event_id, controller_id, propagated_at) VALUES (?, ?, ?)'
    ).run(eventId, controllerId, now);
  }

  /**
   * Broadcast event to all active controllers (skip excluded)
   */
  async broadcast(event: Event, excludeControllerIds: string[] = []): Promise<void> {
    const controllers = await this.registry.getActive();

    // Exclude specified controllers
    const targets = controllers.filter(c => !excludeControllerIds.includes(c.id));

    // Broadcast to each controller
    const promises = targets.map(async (controller) => {
      // Skip if already propagated
      if (await this.hasSeenEvent(event.id, controller.id)) {
        return;
      }

      try {
        // Send event to controller
        const response = await fetch(`${controller.url}/api/events/broadcast`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-API-Key': this.apiKey,
          },
          body: JSON.stringify(event),
        });

        if (!response.ok) {
          console.error(`Failed to broadcast to ${controller.id}: ${response.status}`);
          return;
        }

        // Mark as propagated
        await this.markPropagated(event.id, controller.id);
      } catch (error) {
        console.error(`Error broadcasting to ${controller.id}:`, error);
      }
    });

    await Promise.allSettled(promises);
  }

  /**
   * Get propagation status for event
   */
  async getPropagationStatus(eventId: string): Promise<PropagationRecord[]> {
    const rows = this.db.prepare<PropagationRecord>(
      'SELECT * FROM event_propagation WHERE event_id = ? ORDER BY propagated_at ASC'
    ).all(eventId);

    return rows;
  }

  /**
   * Clean up old propagation records (optional maintenance)
   */
  async cleanupOldRecords(olderThanMs: number): Promise<number> {
    const cutoff = Date.now() - olderThanMs;
    const result = this.db.prepare(
      'DELETE FROM event_propagation WHERE propagated_at < ?'
    ).run(cutoff);

    return result.changes;
  }
}
