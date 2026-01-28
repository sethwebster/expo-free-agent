# Distributed Controller Network Design

## Overview

Transform single controller into distributed mesh of controller nodes with eventual consistency via cryptographically secure event log.

## Requirements

1. **Controller Registration**
   - Nodes register with parent controller on launch
   - TTL-based registration (5min) with 2min heartbeat refresh
   - Self-heal: nodes re-register if TTL expires

2. **Event Broadcasting**
   - Globally unique event IDs (UUIDs)
   - Events: build state changes (submitted, assigned, building, completed, failed, cancelled)
   - Propagate through network for eventual consistency
   - Append-only, cryptographically secure event log

3. **Cryptographic Integrity**
   - Merkle tree chain: each event hashes previous event + own data
   - Tampering breaks chain → detectable
   - Replay yields identical state

4. **Eventual Consistency**
   - Each node maintains local DB replica
   - Event replay syncs state across network
   - Conflict resolution via event timestamp + event ID ordering

## Architecture

### New Database Tables

```sql
-- Controller nodes in network
CREATE TABLE controller_nodes (
  id TEXT PRIMARY KEY,           -- UUID
  url TEXT NOT NULL,             -- http://host:port
  name TEXT NOT NULL,            -- human-readable label
  registered_at INTEGER NOT NULL,
  last_heartbeat_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,   -- registered_at + 5min
  is_active INTEGER DEFAULT 1,   -- 0 = expired/offline
  metadata TEXT                  -- JSON: version, capabilities, etc
);

-- Cryptographic event log (append-only)
CREATE TABLE event_log (
  id TEXT PRIMARY KEY,           -- UUID (globally unique)
  sequence INTEGER NOT NULL,     -- auto-increment for local ordering
  timestamp INTEGER NOT NULL,    -- Unix ms
  event_type TEXT NOT NULL,      -- build:submitted, build:assigned, etc
  entity_id TEXT NOT NULL,       -- build_id, worker_id, etc
  entity_type TEXT NOT NULL,     -- build, worker, controller
  payload TEXT NOT NULL,         -- JSON event data
  source_controller_id TEXT NOT NULL, -- which node emitted event
  previous_hash TEXT,            -- SHA-256 of previous event (null for genesis)
  event_hash TEXT NOT NULL,      -- SHA-256 of this event
  UNIQUE(sequence)
);

-- Event propagation tracking (prevent re-broadcast loops)
CREATE TABLE event_propagation (
  event_id TEXT NOT NULL,
  controller_id TEXT NOT NULL,
  propagated_at INTEGER NOT NULL,
  PRIMARY KEY (event_id, controller_id)
);
```

### Event Types

```typescript
type EventType =
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

interface Event {
  id: string;              // UUID v4
  sequence: number;        // local sequence
  timestamp: number;       // Date.now()
  eventType: EventType;
  entityId: string;        // build/worker/controller ID
  entityType: 'build' | 'worker' | 'controller';
  payload: Record<string, unknown>; // event-specific data
  sourceControllerId: string;
  previousHash: string | null;
  eventHash: string;       // SHA-256 of canonical JSON
}
```

### Event Hash Calculation

```typescript
function calculateEventHash(event: Omit<Event, 'eventHash'>): string {
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
```

### API Endpoints (New)

```
POST /api/controllers/register
  - Register controller node with parent
  - Body: { id, url, name, metadata? }
  - Returns: { id, expiresAt }

POST /api/controllers/:id/heartbeat
  - Refresh TTL (resets expires_at to now + 5min)
  - Returns: { expiresAt }

GET /api/controllers
  - List active controller nodes
  - Returns: { controllers: ControllerNode[] }

POST /api/events/broadcast
  - Receive event from another controller
  - Body: Event
  - Validates hash chain
  - Applies to local DB
  - Propagates to other controllers (if not already seen)

GET /api/events/since/:sequence
  - Get events since sequence number
  - For sync/catchup scenarios
  - Returns: { events: Event[] }

GET /api/events/verify
  - Verify event log integrity
  - Returns: { valid: boolean, firstBrokenSequence?: number }
```

### Services

#### EventLog Service

```typescript
class EventLog {
  constructor(private db: Database, private controllerId: string);

  // Append event to log
  async append(
    eventType: EventType,
    entityId: string,
    entityType: string,
    payload: Record<string, unknown>
  ): Promise<Event>;

  // Get latest event for hash chaining
  async getLatest(): Promise<Event | null>;

  // Verify hash chain integrity
  async verify(): Promise<{ valid: boolean; firstBrokenSequence?: number }>;

  // Get events since sequence (for sync)
  async getSince(sequence: number, limit?: number): Promise<Event[]>;

  // Replay events to rebuild state
  async replay(fromSequence?: number): Promise<void>;
}
```

#### ControllerRegistry Service

```typescript
class ControllerRegistry {
  constructor(private db: Database, private eventLog: EventLog);

  // Register controller node
  async register(id: string, url: string, name: string, metadata?: object): Promise<void>;

  // Refresh heartbeat
  async heartbeat(id: string): Promise<Date>;

  // Get active controllers
  async getActive(): Promise<ControllerNode[]>;

  // Expire stale controllers (background task)
  async expireStale(): Promise<string[]>; // returns expired IDs

  // Broadcast event to all active controllers
  async broadcastEvent(event: Event): Promise<void>;
}
```

#### EventBroadcaster Service

```typescript
class EventBroadcaster {
  constructor(
    private db: Database,
    private eventLog: EventLog,
    private registry: ControllerRegistry
  );

  // Receive event from network
  async receive(event: Event): Promise<void>;

  // Check if event already propagated to controller
  async hasSeenEvent(eventId: string, controllerId: string): Promise<boolean>;

  // Mark event as propagated to controller
  async markPropagated(eventId: string, controllerId: string): Promise<void>;

  // Broadcast to network (skip controllers who've seen it)
  async broadcast(event: Event): Promise<void>;
}
```

### Modified Services

#### JobQueue

Add event logging for state transitions:

```typescript
async enqueue(build: Build): Promise<void> {
  // ... existing logic ...

  await this.eventLog.append(
    'build:submitted',
    build.id,
    'build',
    { platform: build.platform, status: 'pending' }
  );
}

async assignToWorker(worker: Worker): Promise<Build | null> {
  // ... existing logic ...

  if (assigned) {
    await this.eventLog.append(
      'build:assigned',
      assigned.id,
      'build',
      { workerId: worker.id, status: 'assigned' }
    );
  }
}
```

### Configuration

```typescript
interface DistributedConfig {
  mode: 'standalone' | 'distributed';  // default: standalone
  controllerId?: string;               // UUID (generated if not set)
  controllerName?: string;             // human name (default: hostname)
  parentControllerUrl?: string;        // parent to register with
  registrationTtl: number;             // default: 300000 (5min)
  heartbeatInterval: number;           // default: 120000 (2min)
  expirationCheckInterval: number;     // default: 60000 (1min)
}
```

### Startup Flow (Distributed Mode)

1. Load config with distributed settings
2. Initialize database + event log
3. Register with parent controller (if parentControllerUrl set)
4. Start heartbeat timer (every 2min)
5. Start expiration checker (every 1min)
6. Subscribe to JobQueue events → append to event log
7. Subscribe to EventLog append → broadcast to network
8. Start HTTP server

### Event Flow Example

**Scenario**: Build submitted to Controller A

1. User submits build to Controller A
2. A appends `build:submitted` event to local log (sequence 42)
   - Calculates hash based on previous event (sequence 41)
3. A broadcasts event to all active controllers (B, C)
4. B receives event, validates hash chain (checks previous_hash)
5. B appends event to local log (sequence 89 in B's log)
6. B applies event: creates build record in local DB
7. B does NOT re-broadcast (already marked as propagated from A)
8. C does same as B
9. Eventually: all controllers have build in local DB

### Conflict Resolution

**Event Ordering**: Timestamp + Event ID (lexicographic)

If two controllers emit conflicting events (e.g., both assign same build):
- Events ordered by timestamp, then by event ID
- First event wins
- Second event ignored during replay (build already assigned)

**State Reconciliation**: Periodic replay from genesis
- Rebuilds entire state from event log
- Ensures consistency even if bugs in incremental application

## Implementation Phases

### Phase 1: Event Log Foundation
- [ ] Schema migration: event_log table
- [ ] EventLog service with hash chaining
- [ ] Event verification
- [ ] Tests: hash integrity, replay

### Phase 2: Controller Registry
- [ ] Schema: controller_nodes, event_propagation
- [ ] ControllerRegistry service
- [ ] Registration + heartbeat endpoints
- [ ] Expiration background task
- [ ] Tests: registration, TTL, expiration

### Phase 3: Event Broadcasting
- [ ] EventBroadcaster service
- [ ] POST /api/events/broadcast endpoint
- [ ] Network propagation logic
- [ ] Loop prevention (event_propagation tracking)
- [ ] Tests: broadcast, deduplication

### Phase 4: Integration
- [ ] JobQueue → EventLog integration
- [ ] Config for distributed mode
- [ ] Startup flow modifications
- [ ] CLI args: --controller-id, --parent-url, --mode
- [ ] Tests: end-to-end distributed scenarios

### Phase 5: Observability
- [ ] GET /api/events/verify endpoint
- [ ] GET /api/events/since/:sequence endpoint
- [ ] Web UI: controller network graph
- [ ] Web UI: event log viewer
- [ ] Metrics: event propagation latency

## Security Considerations

- **Event Tampering**: Hash chain makes tampering detectable
- **Replay Attacks**: Event IDs are globally unique (UUID v4)
- **API Auth**: Extend existing X-API-Key to controller-controller requests
- **Network Trust**: Assume trusted network (localhost/VPN) per MVP design
- **DoS**: Rate limiting on /api/events/broadcast (future enhancement)

## Testing Strategy

1. **Unit Tests**: EventLog hash calculation, ControllerRegistry TTL
2. **Integration Tests**: Event propagation, conflict resolution
3. **E2E Tests**: Multi-controller network, state convergence
4. **Chaos Tests**: Network partitions, out-of-order events

## Migration Path

- Existing single-controller setups run in 'standalone' mode (no changes)
- Opt-in to distributed via `--mode distributed --parent-url http://...`
- Schema migrations auto-apply (backward compatible)

## Open Questions

1. **Conflict Resolution**: Should we use vector clocks or just timestamp+ID ordering?
   - **Decision**: Start with timestamp+ID, add vector clocks if conflicts emerge

2. **Event Pruning**: Keep event log forever or prune old events?
   - **Decision**: Keep forever for now (append-only integrity), add archival later

3. **Network Discovery**: Manual parent URL or auto-discovery?
   - **Decision**: Manual for MVP, DNS-SD/mDNS for future

4. **Split Brain**: How to handle network partitions?
   - **Decision**: Accept eventual consistency, add monitoring/alerts

5. **Leader Election**: Do we need a leader for coordination?
   - **Decision**: No leader (leaderless), all nodes equal
