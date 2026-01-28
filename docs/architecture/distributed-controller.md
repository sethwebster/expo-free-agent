# Distributed Controller Architecture

## Overview

The Expo Free Agent controller supports distributed mode, allowing multiple controller nodes to form a mesh network with eventual consistency. Each node maintains a cryptographically secure event log that tracks all state changes, and events are propagated across the network to ensure all nodes converge to the same state.

## Key Features

### 1. Controller Registration

- Nodes register with a parent controller on startup
- Registration includes: unique ID, URL, name, and metadata
- TTL-based expiration (default 5 minutes)
- Heartbeat mechanism (every 2 minutes) refreshes TTL
- Stale nodes auto-expire if they stop sending heartbeats

### 2. Cryptographic Event Log

- **Merkle tree chain**: Each event contains hash of previous event + own data
- **Tamper detection**: Breaking the chain is immediately detectable
- **Replay capability**: Entire state can be rebuilt from event log
- **Globally unique event IDs**: UUID v4 prevents conflicts

#### Event Types

```typescript
type EventType =
  | 'build:submitted'    // New build submitted to queue
  | 'build:assigned'     // Build assigned to worker
  | 'build:building'     // Build started (not yet implemented)
  | 'build:completed'    // Build completed successfully
  | 'build:failed'       // Build failed
  | 'build:cancelled'    // Build cancelled
  | 'build:retried'      // Failed build retried
  | 'worker:registered'  // Worker registered
  | 'worker:offline'     // Worker went offline
  | 'controller:registered'  // Controller registered
  | 'controller:heartbeat'   // Controller heartbeat
  | 'controller:expired'     // Controller expired
```

### 3. Event Broadcasting

- Events propagate to all active controllers
- Loop prevention via propagation tracking
- Failed broadcasts logged but don't block
- Network resilience: controllers continue operating during partitions

### 4. Eventual Consistency

- All controllers receive all events (eventually)
- Conflict resolution: timestamp + event ID ordering
- State reconciliation via event replay
- No coordination required between nodes

## Usage

### Standalone Mode (Default)

```bash
bun controller --port 3000
```

No distributed features enabled. Single controller operates independently.

### Distributed Mode - Parent Controller

```bash
bun controller \
  --mode distributed \
  --port 3000 \
  --controller-name "main-controller"
```

Runs as root node. Other controllers can register with it.

### Distributed Mode - Child Controller

```bash
bun controller \
  --mode distributed \
  --port 3001 \
  --controller-name "worker-controller-1" \
  --parent-url http://localhost:3000
```

Registers with parent on startup. Sends heartbeats every 2 minutes.

### Environment Variables

```bash
export CONTROLLER_MODE=distributed
export CONTROLLER_ID=<uuid>              # Optional: auto-generated if not set
export CONTROLLER_NAME=my-controller     # Optional: defaults to hostname
export PARENT_CONTROLLER_URL=http://...  # Optional: no parent if not set
```

## API Endpoints

### Controller Management

#### Register Controller

```http
POST /api/controllers/register
X-API-Key: <your-api-key>
Content-Type: application/json

{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "url": "http://localhost:3001",
  "name": "worker-controller-1",
  "metadata": { "version": "1.0.0" },
  "ttl": 300000
}
```

Response:
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "expiresAt": 1704067200000
}
```

#### Heartbeat

```http
POST /api/controllers/:id/heartbeat
X-API-Key: <your-api-key>
```

Response:
```json
{
  "expiresAt": 1704067200000
}
```

#### List Active Controllers

```http
GET /api/controllers
X-API-Key: <your-api-key>
```

Response:
```json
{
  "controllers": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "url": "http://localhost:3001",
      "name": "worker-controller-1",
      "registeredAt": 1704066900000,
      "lastHeartbeatAt": 1704067080000,
      "expiresAt": 1704067200000,
      "isActive": true,
      "metadata": { "version": "1.0.0" }
    }
  ]
}
```

### Event Log

#### Broadcast Event

```http
POST /api/events/broadcast
X-API-Key: <your-api-key>
Content-Type: application/json

{
  "id": "event-uuid",
  "sequence": 42,
  "timestamp": 1704067200000,
  "eventType": "build:submitted",
  "entityId": "build-123",
  "entityType": "build",
  "payload": { "platform": "ios" },
  "sourceControllerId": "controller-1",
  "previousHash": "sha256-hash-of-previous-event",
  "eventHash": "sha256-hash-of-this-event"
}
```

#### Get Events Since Sequence

```http
GET /api/events/since/42?limit=100
X-API-Key: <your-api-key>
```

Response:
```json
{
  "events": [...]
}
```

#### Verify Event Log Integrity

```http
GET /api/events/verify
X-API-Key: <your-api-key>
```

Response (valid):
```json
{
  "valid": true
}
```

Response (tampered):
```json
{
  "valid": false,
  "firstBrokenSequence": 42,
  "error": "Hash chain broken at sequence 42"
}
```

## Architecture Details

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

### Event Flow Example

**Scenario**: User submits build to Controller A

1. User → Controller A: POST /api/builds/submit
2. Controller A: Append `build:submitted` event to local log (sequence 42)
   - Calculate hash based on previous event (sequence 41)
3. Controller A → Controller B, C: POST /api/events/broadcast (event 42)
4. Controller B: Receive event, validate hash chain
5. Controller B: Append event to local log (sequence 89 in B's log)
6. Controller B: Apply event → create build record in local DB
7. Controller B: Do NOT re-broadcast (already propagated from A)
8. Eventually: All controllers have build in local DB

### Conflict Resolution

**Event Ordering**: Timestamp → Event ID (lexicographic)

If two controllers emit conflicting events:
- Events ordered by timestamp (ascending)
- Ties broken by event ID (lexicographic)
- First event wins
- Second event ignored during replay (idempotent operations)

### State Reconciliation

Periodic event replay ensures consistency:
1. Fetch all events from log (sequence ASC)
2. Rebuild state from scratch
3. Apply events in order
4. Detect inconsistencies

## Database Schema

### controller_nodes

```sql
CREATE TABLE controller_nodes (
  id TEXT PRIMARY KEY,
  url TEXT NOT NULL,
  name TEXT NOT NULL,
  registered_at INTEGER NOT NULL,
  last_heartbeat_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  is_active INTEGER DEFAULT 1,
  metadata TEXT
);
```

### event_log

```sql
CREATE TABLE event_log (
  id TEXT PRIMARY KEY,
  sequence INTEGER NOT NULL UNIQUE,
  timestamp INTEGER NOT NULL,
  event_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  payload TEXT NOT NULL,
  source_controller_id TEXT NOT NULL,
  previous_hash TEXT,
  event_hash TEXT NOT NULL
);
```

### event_propagation

```sql
CREATE TABLE event_propagation (
  event_id TEXT NOT NULL,
  controller_id TEXT NOT NULL,
  propagated_at INTEGER NOT NULL,
  PRIMARY KEY (event_id, controller_id)
);
```

## Security Considerations

### Tamper Detection

- Hash chain makes tampering immediately detectable
- Verify endpoint allows checking log integrity
- Broken chain identifies first tampered event

### Replay Attacks

- Event IDs are globally unique (UUID v4)
- Duplicate events ignored (no effect)
- Timestamps prevent backdating

### API Authentication

- Same API key used for controller-controller requests
- Trust network model (localhost/VPN)
- NOT production-ready (needs mutual TLS, per-controller keys)

### DoS Protection

- No rate limiting (MVP limitation)
- Future: Rate limit /api/events/broadcast
- Future: Backpressure for slow consumers

## Testing

### Unit Tests

```bash
bun test packages/controller/src/services/EventLog.test.ts
```

Tests:
- Hash chain validity
- Tamper detection
- Event deduplication
- Sequence ordering

### Integration Tests

```bash
# Run 3 controllers in distributed mode
bun controller --mode distributed --port 3000 &
bun controller --mode distributed --port 3001 --parent-url http://localhost:3000 &
bun controller --mode distributed --port 3002 --parent-url http://localhost:3000 &

# Submit build to controller 1
curl -X POST http://localhost:3000/api/builds/submit ...

# Check that all controllers have the build
curl http://localhost:3001/api/builds
curl http://localhost:3002/api/builds
```

## Limitations & Future Work

### Current Limitations

- **No leader election**: All nodes equal (leaderless)
- **Manual parent URL**: No auto-discovery
- **No network partition handling**: Accept eventual consistency
- **No event pruning**: Event log grows unbounded
- **Single API key**: No per-controller authentication

### Future Enhancements

- **Vector clocks**: Better conflict resolution
- **DNS-SD/mDNS**: Auto-discovery of controller nodes
- **Event archival**: Prune old events to bounded storage
- **Mutual TLS**: Secure controller-controller communication
- **Monitoring**: Event propagation latency metrics
- **Split-brain detection**: Alert on network partitions

## Migration Path

Existing single-controller setups continue working (standalone mode is default). Opt-in to distributed mode via CLI flags or environment variables. Schema migrations auto-apply (backward compatible).

## References

- Design document: `/plans/distributed-controller-design.md`
- Implementation: `packages/controller/src/services/`
- Tests: `packages/controller/src/services/EventLog.test.ts`
