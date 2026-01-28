import crypto from 'crypto';
import { Database } from '../db/Database';
import { Event, EventType, EntityType, eventFromRow, eventToRow, EventRow } from '../domain/Event';

export interface AppendEventOptions {
  eventType: EventType;
  entityId: string;
  entityType: EntityType;
  payload: Record<string, unknown>;
}

export interface VerifyResult {
  valid: boolean;
  firstBrokenSequence?: number;
  error?: string;
}

export class EventLog {
  constructor(
    private db: Database,
    private controllerId: string
  ) {}

  /**
   * Calculate SHA-256 hash of event for cryptographic chain
   */
  private calculateHash(event: Omit<Event, 'eventHash'>): string {
    const canonical = JSON.stringify({
      id: event.id,
      sequence: event.sequence,
      timestamp: event.timestamp,
      eventType: event.eventType,
      entityId: event.entityId,
      entityType: event.entityType,
      payload: event.payload,
      sourceControllerId: event.sourceControllerId,
      previousHash: event.previousHash,
    });
    return crypto.createHash('sha256').update(canonical, 'utf8').digest('hex');
  }

  /**
   * Generate unique event ID
   */
  private generateEventId(): string {
    return crypto.randomUUID();
  }

  /**
   * Get latest event for hash chaining
   */
  async getLatest(): Promise<Event | null> {
    const row = this.db.prepare<EventRow>(
      'SELECT * FROM event_log ORDER BY sequence DESC LIMIT 1'
    ).get();

    return row ? eventFromRow(row) : null;
  }

  /**
   * Get event by ID
   */
  async getById(eventId: string): Promise<Event | null> {
    const row = this.db.prepare<EventRow>(
      'SELECT * FROM event_log WHERE id = ?'
    ).get(eventId);

    return row ? eventFromRow(row) : null;
  }

  /**
   * Get events since sequence number
   */
  async getSince(sequence: number, limit = 1000): Promise<Event[]> {
    const rows = this.db.prepare<EventRow>(
      'SELECT * FROM event_log WHERE sequence > ? ORDER BY sequence ASC LIMIT ?'
    ).all(sequence, limit);

    return rows.map(eventFromRow);
  }

  /**
   * Get all events in sequence order
   */
  async getAll(limit?: number): Promise<Event[]> {
    const query = limit
      ? 'SELECT * FROM event_log ORDER BY sequence ASC LIMIT ?'
      : 'SELECT * FROM event_log ORDER BY sequence ASC';

    const rows = limit
      ? this.db.prepare<EventRow>(query).all(limit)
      : this.db.prepare<EventRow>(query).all();

    return rows.map(eventFromRow);
  }

  /**
   * Append event to log (creates new event with hash chain)
   */
  async append(options: AppendEventOptions): Promise<Event> {
    const { eventType, entityId, entityType, payload } = options;

    // Get previous event for hash chaining
    const previous = await this.getLatest();
    const timestamp = Date.now();
    const id = this.generateEventId();
    const previousHash = previous ? previous.eventHash : null;

    // Build event without hash
    const eventWithoutHash: Omit<Event, 'eventHash'> = {
      id,
      sequence: previous ? previous.sequence + 1 : 1,
      timestamp,
      eventType,
      entityId,
      entityType,
      payload,
      sourceControllerId: this.controllerId,
      previousHash,
    };

    // Calculate hash
    const eventHash = this.calculateHash(eventWithoutHash);

    // Full event with hash
    const event: Event = {
      ...eventWithoutHash,
      eventHash,
    };

    // Insert into database
    const row = eventToRow(event);
    this.db.prepare(
      `INSERT INTO event_log (
        id, sequence, timestamp, event_type, entity_id, entity_type,
        payload, source_controller_id, previous_hash, event_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).run(
      row.id,
      event.sequence,
      row.timestamp,
      row.event_type,
      row.entity_id,
      row.entity_type,
      row.payload,
      row.source_controller_id,
      row.previous_hash,
      row.event_hash
    );

    return event;
  }

  /**
   * Insert received event from another controller (validates hash chain)
   */
  async receive(event: Event): Promise<void> {
    // Check if event already exists
    const existing = await this.getById(event.id);
    if (existing) {
      return; // Already have this event
    }

    // Verify event hash
    const calculatedHash = this.calculateHash({
      id: event.id,
      sequence: event.sequence,
      timestamp: event.timestamp,
      eventType: event.eventType,
      entityId: event.entityId,
      entityType: event.entityType,
      payload: event.payload,
      sourceControllerId: event.sourceControllerId,
      previousHash: event.previousHash,
    });

    if (calculatedHash !== event.eventHash) {
      throw new Error(`Event ${event.id} has invalid hash`);
    }

    // Insert into database
    const row = eventToRow(event);
    this.db.prepare(
      `INSERT INTO event_log (
        id, sequence, timestamp, event_type, entity_id, entity_type,
        payload, source_controller_id, previous_hash, event_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).run(
      row.id,
      event.sequence,
      row.timestamp,
      row.event_type,
      row.entity_id,
      row.entity_type,
      row.payload,
      row.source_controller_id,
      row.previous_hash,
      row.event_hash
    );
  }

  /**
   * Verify hash chain integrity
   */
  async verify(): Promise<VerifyResult> {
    const events = await this.getAll();

    if (events.length === 0) {
      return { valid: true };
    }

    // First event should have null previous hash
    if (events[0].previousHash !== null) {
      return {
        valid: false,
        firstBrokenSequence: events[0].sequence,
        error: 'First event has non-null previousHash',
      };
    }

    // Verify each subsequent event
    for (let i = 0; i < events.length; i++) {
      const event = events[i];

      // Verify hash
      const calculatedHash = this.calculateHash({
        id: event.id,
        sequence: event.sequence,
        timestamp: event.timestamp,
        eventType: event.eventType,
        entityId: event.entityId,
        entityType: event.entityType,
        payload: event.payload,
        sourceControllerId: event.sourceControllerId,
        previousHash: event.previousHash,
      });

      if (calculatedHash !== event.eventHash) {
        return {
          valid: false,
          firstBrokenSequence: event.sequence,
          error: `Event hash mismatch at sequence ${event.sequence}`,
        };
      }

      // Verify chain (previousHash matches previous event's hash)
      if (i > 0) {
        const previousEvent = events[i - 1];
        if (event.previousHash !== previousEvent.eventHash) {
          return {
            valid: false,
            firstBrokenSequence: event.sequence,
            error: `Hash chain broken at sequence ${event.sequence}`,
          };
        }
      }
    }

    return { valid: true };
  }

  /**
   * Get count of events
   */
  async count(): Promise<number> {
    const result = this.db.prepare<{ count: number }>(
      'SELECT COUNT(*) as count FROM event_log'
    ).get();
    return result?.count ?? 0;
  }

  /**
   * Get events by entity
   */
  async getByEntity(entityType: EntityType, entityId: string): Promise<Event[]> {
    const rows = this.db.prepare<EventRow>(
      'SELECT * FROM event_log WHERE entity_type = ? AND entity_id = ? ORDER BY sequence ASC'
    ).all(entityType, entityId);

    return rows.map(eventFromRow);
  }
}
