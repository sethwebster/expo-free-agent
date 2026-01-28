# Distributed Controller Data Flow

## Overview

This document describes how data flows through the distributed controller network, from build submission to completion, including event propagation, state synchronization, and network healing.

## Network Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                     Distributed Network                          │
│                                                                   │
│  ┌─────────────┐  gossip  ┌─────────────┐  gossip  ┌──────────┐│
│  │Controller A │◄────────►│Controller B │◄────────►│Controller│││
│  │  (Seed)     │          │  (Seed)     │          │    C     │││
│  └──────┬──────┘          └──────┬──────┘          └─────┬────┘│
│         │                        │                         │     │
│         │ event                  │ event                   │     │
│         │ broadcast              │ broadcast               │     │
│         │                        │                         │     │
│         ▼                        ▼                         ▼     │
│  ┌─────────────┐          ┌─────────────┐          ┌──────────┐│
│  │  Worker W1  │          │  Worker W2  │          │Worker W3 │││
│  │  (builds)   │          │  (builds)   │          │ (builds) │││
│  └─────────────┘          └─────────────┘          └──────────┘│
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow: Build Lifecycle

### 1. Build Submission

```
User → Controller A
POST /api/builds/submit
{
  platform: "ios",
  sourceZip: <binary>,
  certsZip: <binary>
}
```

**Controller A Actions:**
1. **Validate request** (API key, file sizes)
2. **Store files** to local storage:
   - `storage/builds/{build-id}.zip` (source)
   - `storage/certs/{build-id}.zip` (certificates)
3. **Create build record** in database:
   ```sql
   INSERT INTO builds (id, status, platform, source_path, certs_path, ...)
   VALUES (?, 'pending', ?, ?, ...)
   ```
4. **Enqueue build** to JobQueue (in-memory):
   ```typescript
   queue.enqueue(build) // Triggers 'job:added' event
   ```
5. **QueueEventLogger** catches event:
   ```typescript
   queue.on('job:added', async (build) => {
     // Append to cryptographic event log
     const event = await eventLog.append({
       eventType: 'build:submitted',
       entityId: build.id,
       entityType: 'build',
       payload: { platform: 'ios', status: 'pending' }
     })

     // Broadcast to network
     await broadcaster.broadcast(event)
   })
   ```
6. **Return to user**:
   ```json
   {
     "buildId": "build-123",
     "accessToken": "token-for-status-checks"
   }
   ```

### 2. Event Propagation (Build Submitted)

**Controller A → Controllers B, C:**

```
Controller A broadcasts event:
  ├─► Controller B: POST /api/events/broadcast
  │   {
  │     id: "event-uuid-1",
  │     sequence: 42,
  │     timestamp: 1704067200000,
  │     eventType: "build:submitted",
  │     entityId: "build-123",
  │     entityType: "build",
  │     payload: { platform: "ios", status: "pending" },
  │     sourceControllerId: "controller-a",
  │     previousHash: "sha256-of-event-41",
  │     eventHash: "sha256-of-event-42"
  │   }
  │
  └─► Controller C: POST /api/events/broadcast
      (same event)
```

**Controllers B & C Actions:**
1. **Validate event hash**:
   ```typescript
   const calculatedHash = sha256(event - eventHash field)
   if (calculatedHash !== event.eventHash) {
     throw new Error('Invalid hash - tampered!')
   }
   ```
2. **Check if already seen** (deduplication):
   ```sql
   SELECT * FROM event_log WHERE id = ?
   -- If exists, return early
   ```
3. **Insert into local event log**:
   ```sql
   INSERT INTO event_log (id, sequence, timestamp, ...)
   VALUES (?, ?, ?, ...)
   ```
4. **Mark as propagated from source**:
   ```sql
   INSERT INTO event_propagation (event_id, controller_id, propagated_at)
   VALUES ('event-uuid-1', 'controller-a', ?)
   ```
5. **Do NOT re-broadcast** (already came from A, prevent loops)

**Result:** All controllers now have event in their local log, but files remain only on Controller A.

### 3. Build Assignment (Worker Polls)

**Worker W1 → Controller B:**
```
GET /api/workers/poll?worker_id=worker-1
```

**Controller B Actions:**
1. **Check local queue** for pending builds:
   ```typescript
   const build = queue.assignToWorker(worker)
   // Returns null - Controller B's queue is empty!
   ```
2. **Return 204 No Content** (no builds available locally)

**Worker W1 → Controller A:**
```
GET /api/workers/poll?worker_id=worker-1
```

**Controller A Actions:**
1. **Assign build from queue**:
   ```typescript
   const build = queue.assignToWorker(worker) // Triggers 'job:assigned' event
   ```
2. **Atomic database update** (transaction):
   ```sql
   BEGIN IMMEDIATE;
   UPDATE builds SET status = 'assigned', worker_id = ? WHERE id = ?;
   COMMIT;
   ```
3. **QueueEventLogger** catches event:
   ```typescript
   queue.on('job:assigned', async (build, worker) => {
     const event = await eventLog.append({
       eventType: 'build:assigned',
       entityId: build.id,
       entityType: 'build',
       payload: { workerId: worker.id, status: 'assigned' }
     })
     await broadcaster.broadcast(event)
   })
   ```
4. **Broadcast assignment event** to B, C
5. **Return build details** to worker:
   ```json
   {
     "buildId": "build-123",
     "platform": "ios",
     "sourceUrl": "http://controller-a:3000/api/builds/build-123/source",
     "certsUrl": "http://controller-a:3000/api/builds/build-123/certs"
   }
   ```

**Controllers B & C receive assignment event:**
- Append to event log
- Update local state tracking (eventually consistent)
- Mark propagated from A

### 4. Build Execution (Worker Downloads & Builds)

**Worker W1 → Controller A:**

1. **Download source**:
   ```
   GET /api/builds/build-123/source
   X-Worker-Id: worker-1
   ```
   - Controller A validates worker owns this build
   - Streams `storage/builds/build-123.zip`

2. **Download certificates**:
   ```
   GET /api/builds/build-123/certs
   X-Worker-Id: worker-1
   ```
   - Streams `storage/certs/build-123.zip`

3. **Send heartbeats** (every 30s):
   ```
   POST /api/builds/build-123/heartbeat?worker_id=worker-1
   { progress: 45 }
   ```
   - Controller A updates `last_heartbeat_at` timestamp
   - Prevents stuck build detection

4. **Send telemetry** (CPU/memory snapshots):
   ```
   POST /api/builds/build-123/telemetry
   {
     cpuPercent: 87.5,
     memoryMb: 4096,
     stage: "compiling"
   }
   ```
   - Stored in `cpu_snapshots` table

5. **Execute build** in Tart VM:
   - Extracts source
   - Installs dependencies
   - Runs Expo build
   - Signs with certificates

### 5. Build Completion (Upload Result)

**Worker W1 → Controller A:**
```
POST /api/workers/upload
Content-Type: multipart/form-data

buildId=build-123
success=true
result=<binary IPA file>
```

**Controller A Actions:**
1. **Store result file**:
   - Save to `storage/results/build-123.ipa`
2. **Update database**:
   ```sql
   UPDATE builds
   SET status = 'completed',
       result_path = 'storage/results/build-123.ipa',
       completed_at = ?
   WHERE id = 'build-123'
   ```
3. **Complete in queue**:
   ```typescript
   queue.complete('build-123') // Triggers 'job:completed' event
   ```
4. **QueueEventLogger** catches event:
   ```typescript
   queue.on('job:completed', async (build, worker) => {
     const event = await eventLog.append({
       eventType: 'build:completed',
       entityId: build.id,
       entityType: 'build',
       payload: {
         workerId: worker.id,
         status: 'completed',
         completedAt: Date.now()
       }
     })
     await broadcaster.broadcast(event)
   })
   ```
5. **Broadcast completion event** to B, C

**Controllers B & C receive completion event:**
- Append to event log
- Update local state (mark build as completed)
- Files still only on Controller A

### 6. Result Download (User)

**User → Controller A:**
```
GET /api/builds/build-123/download
X-Build-Token: <access-token>
```

**Controller A Actions:**
1. **Validate access token**:
   ```sql
   SELECT * FROM builds WHERE id = ? AND access_token = ?
   ```
2. **Stream result file**:
   - Read `storage/results/build-123.ipa`
   - Stream to user with proper headers:
     ```
     Content-Type: application/octet-stream
     Content-Disposition: attachment; filename="app.ipa"
     ```

## Data Flow: Network Healing

### Gossip Protocol (Every 30 seconds)

Each controller independently runs gossip rounds:

**Controller A Gossip Round:**
```typescript
// 1. Select 3 random active peers
const peers = [Controller B, Controller C, Controller D]

// 2. Exchange peer lists with each
for (const peer of peers) {
  const response = await fetch(`${peer.url}/api/peers/gossip`, {
    method: 'POST',
    body: JSON.stringify({
      peers: [
        { id: 'ctrl-b', url: 'http://b:3000', lastSeen: ... },
        { id: 'ctrl-c', url: 'http://c:3000', lastSeen: ... },
        { id: 'ctrl-d', url: 'http://d:3000', lastSeen: ... }
      ]
    })
  })

  // 3. Receive their peer list
  const theirPeers = await response.json()

  // 4. Merge: add any new peers, update existing
  mergePeerList(theirPeers)

  // 5. Persist successful connection
  await db.run(`
    UPDATE peers
    SET last_successful_connect = ?,
        successful_connects = successful_connects + 1,
        status = 'active'
    WHERE id = ?
  `, [Date.now(), peer.id])
}
```

**Result:**
- Peer lists converge in O(log N) rounds
- New controllers discovered within 30-60 seconds
- Failed controllers detected via missed gossip exchanges

### Node Restart with Peer Memory

**Controller D Restarts:**

```
Startup Flow:
1. Load config, initialize database
2. Attempt reconnection to previous peers:

   SELECT * FROM peers
   WHERE last_successful_connect IS NOT NULL
   ORDER BY last_successful_connect DESC
   LIMIT 10

   Result: [Ctrl A, Ctrl B, Ctrl C, ...]

3. Try reconnecting to Ctrl A:
   POST /api/peers/gossip (with empty peer list)

   Success! Receive peer list from A:
   {
     peers: [
       { id: 'ctrl-b', url: 'http://b:3000', ... },
       { id: 'ctrl-c', url: 'http://c:3000', ... },
       { id: 'ctrl-e', url: 'http://e:3000', ... } // New peer!
     ]
   }

4. Merge peer list (now knows about Ctrl E)
5. Mark A as active with successful reconnection
6. Start gossip timer
7. Network rejoined in ~200ms
```

## Data Synchronization: Eventual Consistency

### Event Log Replay

Controllers can rebuild state by replaying event log:

```typescript
async function rebuildStateFromEventLog() {
  // 1. Clear in-memory state
  queue.clear()

  // 2. Get all events in sequence order
  const events = await eventLog.getAll()

  // 3. Replay each event
  for (const event of events) {
    switch (event.eventType) {
      case 'build:submitted':
        // Recreate build record (if we have files)
        // Or mark as "external" (files on another controller)
        break

      case 'build:assigned':
        // Update assignment tracking
        break

      case 'build:completed':
        // Update status
        break
    }
  }

  // 4. State now consistent with event log
}
```

### Conflict Resolution

**Scenario: Network Partition (Split Brain)**

```
Network splits: [A, B] and [C, D]

Partition 1:
- User submits Build X to Controller A
- Event: { id: 'e1', timestamp: 1000, type: 'build:submitted' }
- Controllers A, B have Build X

Partition 2:
- Different user submits Build Y to Controller C
- Event: { id: 'e2', timestamp: 1001, type: 'build:submitted' }
- Controllers C, D have Build Y

Network Heals:
- Gossip reconnects partitions
- Events e1 and e2 propagate across network
- All controllers now have both events
- Events ordered by: timestamp (1000 < 1001), then event ID
- Final state: All controllers know about Build X and Build Y
- No conflict (different builds)
```

**Scenario: Conflicting Events**

```
Race condition: Two controllers assign same build

Controller A: Assigns Build X to Worker 1
- Event: { id: 'ea', timestamp: 1000, type: 'build:assigned', workerId: 'w1' }

Controller B: Assigns Build X to Worker 2 (race!)
- Event: { id: 'eb', timestamp: 1000, type: 'build:assigned', workerId: 'w2' }

Resolution:
- Both events propagate
- Events have same timestamp (1000)
- Break tie by event ID: 'ea' < 'eb' (lexicographic)
- Event 'ea' wins (first in sequence)
- Event 'eb' ignored during replay (build already assigned)
- Worker 1 proceeds, Worker 2's assignment rejected
```

## Data Storage & Persistence

### Controller A Storage Layout

```
/data/
  └── controller.db (SQLite)
      ├── builds (status, assignments)
      ├── workers (registrations)
      ├── build_logs (per-build logs)
      ├── event_log (cryptographic chain)
      ├── controller_nodes (peer registry)
      ├── event_propagation (tracking)
      └── peers (gossip peer list)

/storage/
  ├── builds/
  │   └── build-123.zip (source code)
  ├── certs/
  │   └── build-123.zip (certificates)
  └── results/
      └── build-123.ipa (built artifact)
```

### Data Distribution

| Data Type | Storage Location | Distribution |
|-----------|-----------------|--------------|
| Build metadata | All controllers | Event log (replicated) |
| Build files (source/certs) | Origin controller only | Not replicated |
| Build results (IPA/APK) | Origin controller only | Not replicated |
| Event log | All controllers | Fully replicated |
| Peer list | All controllers | Gossip protocol |
| Worker registrations | All controllers | Event log (replicated) |

**Why files aren't replicated:**
- Large size (100MB-1GB per build)
- Network bandwidth constraints
- Workers always contact origin controller for files
- Event log provides coordination, files provide artifacts

## Performance Characteristics

### Event Propagation Latency

```
Single Event Broadcast:
- Controller A → Controllers B, C (parallel HTTP POSTs)
- Network latency: ~10-50ms per hop
- Total: 50-100ms for full network propagation

Gossip Convergence:
- New peer joins network
- Discovered via gossip in O(log N) rounds
- Round interval: 30 seconds
- Full convergence: 30-90 seconds (1-3 rounds)
```

### Build Assignment Latency

```
Without Distribution:
- Worker → Controller A
- Queue check: <1ms
- Database update: 1-5ms
- Total: <10ms

With Distribution (worker polls wrong controller):
- Worker → Controller B (no builds) → 204 No Content
- Worker → Controller A (has builds) → Assignment
- Extra round-trip: +10-50ms
```

### Node Restart Performance

```
Without Peer Memory:
- Try Seed 1: 5s timeout
- Try Seed 2: 5s timeout
- Try Seed 3: 2s success + 1s peer download
- Total: 13 seconds

With Peer Memory:
- Load from DB: 10ms
- Reconnect to previous peer: 200ms
- Total: 210ms (60x faster)
```

## Security & Integrity

### Cryptographic Chain Verification

```
Event Log Integrity Check:
1. Read all events in sequence order
2. For each event:
   - Recalculate hash: sha256(event - eventHash)
   - Verify: calculated == stored
   - Verify chain: event.previousHash == previous.eventHash
3. If any verification fails → tamper detected

Result:
- Tampering with any event breaks the chain
- Modification of event N invalidates events N+1, N+2, ...
- Replay from genesis rebuilds exact state
```

### Access Control

```
Build Submission:
- Requires: X-API-Key (shared secret)
- Returns: Access token for this build

Build Status/Download:
- Requires: X-Build-Token (per-build)
- OR: X-API-Key (admin access)

Worker Operations:
- Requires: X-API-Key + X-Worker-Id
- Validated against build assignment

Gossip/Events:
- Requires: X-API-Key (same network key)
- Trust model: all controllers trusted
```

## Monitoring & Observability

### Event Log Stats

```
GET /api/events/verify
→ { valid: true }

GET /api/events
→ { events: [...], count: 1234 }

GET /api/events/since/1000
→ { events: [1001, 1002, ...] }
```

### Peer Network Stats

```
GET /api/controllers
→ { controllers: [active controllers] }

GET /api/peers
→ { peers: [all known peers with status] }
```

### Build Stats

```
GET /api/stats
→ {
  totalBuilds: 150,
  completedBuilds: 120,
  failedBuilds: 10,
  pendingBuilds: 5,
  activeBuilds: 15,
  ...
}
```

## Summary

**Data Flows:**
1. **Builds**: Submitted to origin controller, files stay there, metadata propagates
2. **Events**: Broadcast to all controllers, cryptographically chained
3. **State**: Eventually consistent via event log replay
4. **Peers**: Discovered via gossip, persisted for fast reconnection
5. **Workers**: Poll any controller, redirected to builds on origin

**Key Properties:**
- **Eventual consistency**: All controllers converge to same state
- **No single point of failure**: Any controller can coordinate
- **Fast reconnection**: Peer memory enables sub-second rejoining
- **Tamper detection**: Cryptographic chain prevents history modification
- **Scalability**: O(log N) gossip convergence
