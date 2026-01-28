export type EventType =
  | 'build:submitted'
  | 'build:assigned'
  | 'build:building'
  | 'build:completed'
  | 'build:failed'
  | 'build:cancelled'
  | 'build:retried'
  | 'worker:registered'
  | 'worker:offline'
  | 'controller:registered'
  | 'controller:heartbeat'
  | 'controller:expired';

export type EntityType = 'build' | 'worker' | 'controller';

export interface Event {
  id: string;
  sequence: number;
  timestamp: number;
  eventType: EventType;
  entityId: string;
  entityType: EntityType;
  payload: Record<string, unknown>;
  sourceControllerId: string;
  previousHash: string | null;
  eventHash: string;
}

export interface EventRow {
  id: string;
  sequence: number;
  timestamp: number;
  event_type: string;
  entity_id: string;
  entity_type: string;
  payload: string;
  source_controller_id: string;
  previous_hash: string | null;
  event_hash: string;
}

export function eventFromRow(row: EventRow): Event {
  return {
    id: row.id,
    sequence: row.sequence,
    timestamp: row.timestamp,
    eventType: row.event_type as EventType,
    entityId: row.entity_id,
    entityType: row.entity_type as EntityType,
    payload: JSON.parse(row.payload),
    sourceControllerId: row.source_controller_id,
    previousHash: row.previous_hash,
    eventHash: row.event_hash,
  };
}

export function eventToRow(event: Event): Omit<EventRow, 'sequence'> {
  return {
    id: event.id,
    timestamp: event.timestamp,
    event_type: event.eventType,
    entity_id: event.entityId,
    entity_type: event.entityType,
    payload: JSON.stringify(event.payload),
    source_controller_id: event.sourceControllerId,
    previous_hash: event.previousHash,
    event_hash: event.eventHash,
  };
}
