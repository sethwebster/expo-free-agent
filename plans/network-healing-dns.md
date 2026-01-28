# Network Healing & Controller Discovery

## Problem Statement

When a controller node goes offline (especially the "parent" node that others registered with), new nodes joining the network don't know where to connect. We need a self-healing mechanism similar to DNS that allows:

1. Nodes to discover active controllers when their parent dies
2. Network to reorganize itself after node failures
3. New nodes to bootstrap without hardcoded parent URLs

## Current State

**Limitations:**
- Parent controller URL is hardcoded (`--parent-url`)
- If parent dies, children become isolated
- No discovery mechanism for finding other controllers
- No automatic failover or re-parenting

## Solution Options

### Option 1: Gossip Protocol + Seed List (Recommended)

Similar to Cassandra/Bitcoin - nodes maintain a list of known peers and gossip to discover others.

**How it works:**
1. **Seed List**: Each node configured with 1+ seed controller URLs
2. **Peer Discovery**: On startup, contact seeds to get full peer list
3. **Gossip**: Periodically exchange peer lists with random subset of peers
4. **Failure Detection**: Mark peers as down if heartbeat fails
5. **Bootstrap**: New nodes only need to know 1 seed to join network

**Advantages:**
- No single point of failure
- Self-healing (network reforms after partitions)
- Simple configuration (just need 1-3 seed URLs)
- Scales well (gossip converges in O(log N) rounds)

**Implementation:**

```typescript
interface PeerInfo {
  id: string;
  url: string;
  name: string;
  lastSeen: number;
  status: 'active' | 'suspected' | 'down';
}

class PeerDiscovery {
  private peers = new Map<string, PeerInfo>();
  private seedUrls: string[];

  async bootstrap() {
    // Contact seeds to get initial peer list
    for (const seedUrl of this.seedUrls) {
      try {
        const peers = await this.getPeersFrom(seedUrl);
        for (const peer of peers) {
          this.addPeer(peer);
        }
      } catch (err) {
        console.warn(`Seed ${seedUrl} unavailable`);
      }
    }

    // If no seeds available, operate standalone
    if (this.peers.size === 0) {
      console.warn('No seeds reachable - operating standalone');
    }
  }

  async gossip() {
    // Pick 3 random active peers
    const targets = this.randomPeers(3);

    for (const peer of targets) {
      try {
        // Send our peer list
        const response = await fetch(`${peer.url}/api/peers/gossip`, {
          method: 'POST',
          body: JSON.stringify({ peers: this.getPeerList() })
        });

        // Receive their peer list
        const theirPeers = await response.json();
        this.mergePeerList(theirPeers);

        // Update last seen
        peer.lastSeen = Date.now();
        peer.status = 'active';
      } catch (err) {
        // Mark as suspected (will mark down after N failures)
        this.suspectPeer(peer.id);
      }
    }
  }
}
```

**Configuration:**
```bash
# Multiple seeds for redundancy
bun controller \
  --mode distributed \
  --seeds http://controller1:3000,http://controller2:3000,http://controller3:3000
```

**Event Types:**
- `controller:discovered` - New peer found via gossip
- `controller:suspected` - Peer missed heartbeats
- `controller:down` - Peer confirmed dead
- `controller:recovered` - Previously down peer returned

---

### Option 2: Distributed Hash Table (DHT) - Chord/Kademlia

Similar to BitTorrent/IPFS - nodes form a structured overlay with deterministic routing.

**How it works:**
1. Each node assigned position in hash ring (consistent hashing)
2. Each node maintains routing table (finger table)
3. Lookups use O(log N) hops via finger table
4. Self-stabilizing (nodes rejoin after failures)

**Advantages:**
- Deterministic routing (no flooding)
- Efficient lookups O(log N)
- Self-organizing topology

**Disadvantages:**
- More complex to implement
- Overkill for controller discovery (not storing data)
- Harder to debug

**Skip this**: Too complex for our use case.

---

### Option 3: Multicast DNS (mDNS) / Service Discovery

Similar to Bonjour/Avahi - broadcast presence on local network.

**How it works:**
1. Controllers broadcast presence via multicast
2. Nodes listen for announcements
3. Build peer list from announcements
4. No configuration needed (zero-conf)

**Advantages:**
- Zero configuration
- Works great on LAN
- Simple implementation

**Disadvantages:**
- LAN-only (doesn't cross routers)
- Doesn't work in cloud/containers without special config
- Not suitable for distributed deployments

**Use case**: Optional enhancement for local dev setups.

---

### Option 4: External Service Registry (Consul/etcd/ZooKeeper)

Centralized service registry that all nodes connect to.

**How it works:**
1. All nodes register with external registry
2. Nodes query registry for peer list
3. Registry provides health checks

**Advantages:**
- Battle-tested
- Rich features (health checks, watches, etc.)

**Disadvantages:**
- External dependency (defeats "distributed" goal)
- Additional ops complexity
- Single point of failure (unless registry is clustered)

**Skip this**: Contradicts distributed architecture goals.

---

## Recommended Solution: Gossip + Seed List

### Architecture

```
┌─────────────┐  gossip  ┌─────────────┐
│ Controller 1│◄────────►│ Controller 2│
│  (Seed)     │          │             │
└──────┬──────┘          └──────┬──────┘
       │                        │
       │ gossip          gossip │
       │                        │
       ▼                        ▼
┌─────────────┐          ┌─────────────┐
│ Controller 3│◄────────►│ Controller 4│
│             │  gossip  │             │
└─────────────┘          └─────────────┘
```

- Every controller knows about every other controller (eventually)
- Peer list propagates via gossip (converges in seconds)
- No single point of failure
- New nodes bootstrap from any seed
- **Peer list persisted to database** - nodes remember previous connections across restarts

### Database Schema

```sql
CREATE TABLE peers (
  id TEXT PRIMARY KEY,
  url TEXT NOT NULL,
  name TEXT NOT NULL,
  discovered_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  last_successful_connect INTEGER,  -- Track successful connections
  status TEXT NOT NULL,              -- active, suspected, down
  failure_count INTEGER DEFAULT 0,
  successful_connects INTEGER DEFAULT 0,  -- Connection history
  metadata TEXT                       -- JSON
);

CREATE INDEX idx_peers_status ON peers(status, last_seen_at);
CREATE INDEX idx_peers_reconnect ON peers(last_successful_connect DESC);  -- Fast restart
```

**Schema Notes:**
- `last_successful_connect`: Timestamp of last successful gossip exchange
- `successful_connects`: Total successful connections (prefer reliable peers)
- `idx_peers_reconnect`: Index for fast "reconnect to previous peers" query

### Configuration

```typescript
interface DistributedConfig {
  // ... existing fields ...
  seedUrls: string[];                  // 1-3 seed controller URLs
  gossipInterval: number;              // default: 30s
  gossipFanout: number;                // default: 3 peers per round
  failureThreshold: number;            // default: 3 failures = suspected
  downThreshold: number;               // default: 5 failures = down
  peerTimeout: number;                 // default: 5 minutes
}
```

### New API Endpoints

```typescript
// Exchange peer lists (gossip protocol)
POST /api/peers/gossip
Body: { peers: PeerInfo[] }
Response: { peers: PeerInfo[] }

// Get full peer list (bootstrap)
GET /api/peers
Response: { peers: PeerInfo[] }

// Report peer status
POST /api/peers/:id/status
Body: { status: 'active' | 'suspected' | 'down' }
```

### Reconnection Logic (Fast Restart)

```typescript
class PeerDiscovery {
  /**
   * Attempt to reconnect to previously known peers
   * Called on startup before falling back to seeds
   */
  async reconnectToPreviousPeers(): Promise<boolean> {
    // Get previous peers ordered by reliability
    const previousPeers = await this.db.prepare<PeerInfo>(
      `SELECT * FROM peers
       WHERE last_successful_connect IS NOT NULL
       ORDER BY last_successful_connect DESC, successful_connects DESC
       LIMIT 10`
    ).all();

    if (previousPeers.length === 0) {
      return false; // No previous peers, need to bootstrap
    }

    console.log(`Attempting to reconnect to ${previousPeers.length} previous peers...`);

    let successfulReconnects = 0;

    // Try to reconnect to each previous peer
    for (const peer of previousPeers) {
      try {
        // Attempt gossip exchange
        const response = await fetch(`${peer.url}/api/peers/gossip`, {
          method: 'POST',
          headers: { 'X-API-Key': this.config.apiKey },
          body: JSON.stringify({ peers: [] }),
          signal: AbortSignal.timeout(5000), // 5s timeout
        });

        if (response.ok) {
          const data = await response.json();

          // Success! Update peer status
          await this.db.prepare(
            `UPDATE peers
             SET last_seen_at = ?,
                 last_successful_connect = ?,
                 successful_connects = successful_connects + 1,
                 failure_count = 0,
                 status = 'active'
             WHERE id = ?`
          ).run(Date.now(), Date.now(), peer.id);

          // Merge their peer list
          await this.mergePeerList(data.peers);

          successfulReconnects++;

          console.log(`✅ Reconnected to ${peer.name} (${peer.url})`);

          // Stop after 3 successful reconnections (enough to rejoin network)
          if (successfulReconnects >= 3) {
            break;
          }
        }
      } catch (err) {
        // Peer unreachable, try next one
        console.log(`⏭️  ${peer.name} unreachable, trying next peer...`);
      }
    }

    if (successfulReconnects > 0) {
      console.log(`🎉 Rejoined network via ${successfulReconnects} previous peers`);
      return true;
    }

    console.log(`❌ All previous peers unreachable, falling back to seed bootstrap`);
    return false;
  }
}
```

### Gossip Algorithm

```typescript
class GossipService {
  private gossipTimer?: NodeJS.Timeout;

  start() {
    this.gossipTimer = setInterval(
      () => this.doGossip(),
      this.config.gossipInterval
    );
  }

  async doGossip() {
    // 1. Select random subset of active peers
    const targets = this.selectGossipTargets();

    // 2. Send our peer list to each target
    for (const peer of targets) {
      try {
        const response = await this.sendGossip(peer, this.getPeerList());

        // 3. Merge their peer list into ours
        this.mergePeerList(response.peers);

        // 4. Mark peer as active and update success tracking
        await this.db.prepare(
          `UPDATE peers
           SET status = 'active',
               last_seen_at = ?,
               last_successful_connect = ?,
               successful_connects = successful_connects + 1,
               failure_count = 0
           WHERE id = ?`
        ).run(Date.now(), Date.now(), peer.id);
      } catch (err) {
        // 5. Handle failure
        await this.handleGossipFailure(peer.id);
      }
    }

    // 6. Clean up stale peers
    await this.pruneDeadPeers();
  }

  selectGossipTargets(): PeerInfo[] {
    const active = this.getActivePeers();
    return this.randomSample(active, this.config.gossipFanout);
  }

  async handleGossipFailure(peerId: string) {
    const peer = await this.registry.getById(peerId);
    if (!peer) return;

    const failures = peer.failureCount + 1;

    if (failures >= this.config.downThreshold) {
      // Mark as down
      await this.updatePeerStatus(peerId, 'down');
      await this.eventLog.append({
        eventType: 'controller:down',
        entityId: peerId,
        entityType: 'controller',
        payload: { failures }
      });
    } else if (failures >= this.config.failureThreshold) {
      // Mark as suspected
      await this.updatePeerStatus(peerId, 'suspected');
      await this.eventLog.append({
        eventType: 'controller:suspected',
        entityId: peerId,
        entityType: 'controller',
        payload: { failures }
      });
    }
  }
}
```

### Bootstrap Flow

```
New Controller Startup:
1. Load previously known peers from database (if restarting)
2. Try to reconnect to previous peers first (priority order by last_seen)
   - Significantly faster than seed bootstrap
   - Maintains network locality
   - Only falls back to seeds if all previous peers fail
3. If new node OR all previous peers unreachable:
   a. Load seed URLs from config
   b. Contact seed 1: GET /api/peers → receive peer list
   c. If seed 1 fails, try seed 2, 3, etc.
   d. Merge peer list into local registry
4. Register self with all active peers
5. Start gossip timer (every 30s)
6. Start broadcasting own events

Gossip Round (every 30s):
1. Select 3 random active peers
2. For each peer:
   a. Send POST /api/peers/gossip with our peer list
   b. Receive their peer list
   c. Merge their peers into our registry
   d. Persist peer updates to database
3. Mark responsive peers as 'active'
4. Increment failure counter for unresponsive peers
5. Mark peers as 'suspected' after 3 failures
6. Mark peers as 'down' after 5 failures
7. Persist all status changes to database
```

**Why Persist Peers?**

1. **Fast Restart**: Node restarts in seconds (reconnect to known peers vs. seed bootstrap)
2. **Network Stability**: Maintains existing connections and network topology
3. **Locality Preservation**: Keeps nodes connected to geographically/logically close peers
4. **Resilience**: Seeds can be offline; node still rejoins via previous peers
5. **Reduced Load**: Doesn't hammer seeds on every restart

### Failure Scenarios

#### Scenario 1: Seed Controller Dies

```
Network: [Seed], [Node2], [Node3], [Node4]
Seed dies ❌

Result:
- Node2, Node3, Node4 continue gossiping among themselves
- New Node5 tries Seed (fails) → tries other seeds → joins via Node2
- Network remains functional
```

#### Scenario 2: Network Partition (Split Brain)

```
Network splits into [A, B] and [C, D]

Partition A:          Partition B:
- Build submitted     - Build submitted
- Event ID: E1        - Event ID: E2
- Both create build

Network heals:
- Gossip reconnects partitions
- Events E1 and E2 propagate
- Conflict resolution via timestamp ordering
- One build wins, other marked duplicate
```

#### Scenario 3: Temporary Network Blip

```
Node A temporarily unreachable (3 gossip rounds)

Round 1: A misses → failure_count = 1
Round 2: A misses → failure_count = 2
Round 3: A misses → failure_count = 3 → status = 'suspected'
Round 4: A responds → failure_count = 0 → status = 'active'

Event log:
- controller:suspected (A)
- controller:recovered (A)
```

#### Scenario 4: Node Restart with Peer Memory (Fast Reconnect)

```
Node C restarts (previously knew Nodes A, B, D)

Without Peer Memory (Old Way):
1. Contact Seed1 → timeout (5s)
2. Contact Seed2 → timeout (5s)
3. Contact Seed3 → success (2s)
4. Download peer list (1s)
5. Total: 13 seconds to rejoin

With Peer Memory (New Way):
1. Load previous peers from DB (10ms)
2. Try to reconnect to Node A → success (200ms)
3. Node A shares peer list (including B, D)
4. Total: 210ms to rejoin

Benefit: 60x faster rejoining network
```

**Why This Matters:**
- **Rolling Restarts**: In production, nodes restart for updates/maintenance
- **Network Stability**: Fast reconnects prevent cascade failures
- **Reduced Seed Load**: Seeds aren't hammered on every restart
- **Better UX**: Builds don't queue up waiting for network to form

### Configuration Examples

**Production (3 seed nodes):**
```bash
# Seed 1
bun controller --mode distributed --seeds http://seed1:3000,http://seed2:3000,http://seed3:3000

# Seed 2
bun controller --mode distributed --seeds http://seed1:3000,http://seed2:3000,http://seed3:3000

# Worker nodes
bun controller --mode distributed --seeds http://seed1:3000,http://seed2:3000
```

**Local Dev (single seed):**
```bash
# Seed
bun controller --mode distributed --port 3000

# Workers (bootstrap from seed)
bun controller --mode distributed --port 3001 --seeds http://localhost:3000
bun controller --mode distributed --port 3002 --seeds http://localhost:3000
```

## Implementation Plan

### Phase 1: Peer Storage
- [ ] Add `peers` table to schema (with reconnection fields)
- [ ] Create `PeerInfo` domain model
- [ ] Add peer CRUD methods to `ControllerRegistry`
- [ ] Add reconnection query (ORDER BY last_successful_connect DESC)

### Phase 2: Gossip Protocol
- [ ] Implement `GossipService`
- [ ] Add `POST /api/peers/gossip` endpoint
- [ ] Add `GET /api/peers` endpoint
- [ ] Wire gossip timer into server

### Phase 3: Bootstrap & Reconnection
- [ ] Add `--seeds` CLI flag (comma-separated URLs)
- [ ] Implement `reconnectToPreviousPeers()` (fast path)
- [ ] Implement bootstrap logic (fallback to seeds)
- [ ] Fall back to standalone if no seeds available
- [ ] Update all gossip success handlers to persist to DB

### Phase 4: Failure Detection
- [ ] Track failure counts in peer records
- [ ] Implement suspected/down state transitions
- [ ] Log `controller:suspected`, `controller:down`, `controller:recovered` events
- [ ] Prune dead peers after threshold

### Phase 5: Testing
- [ ] Unit tests for gossip convergence
- [ ] Integration tests for network partitions
- [ ] Chaos testing (kill random nodes)

## Open Questions

1. **Gossip Interval**: 30s good default? Or more aggressive (10s)?
   - **Decision**: Start with 30s, make configurable

2. **Seed Count**: Require 1, 3, or 5 seeds?
   - **Decision**: Allow 1+ seeds, recommend 3 for production

3. **Peer Pruning**: When to remove 'down' peers permanently?
   - **Decision**: Keep for 24h, then prune (in case they recover)

4. **Split Brain**: How to detect and handle?
   - **Decision**: Accept eventual consistency, use timestamp+eventID ordering

5. **Encryption**: Should gossip be encrypted?
   - **Decision**: No (same trust model as existing API key)

## Comparison to Existing `--parent-url`

**Old Way (Hierarchical):**
```
         ┌───────┐
         │ Parent│ ← single point of failure
         └───┬───┘
     ┌───────┼───────┐
     ▼       ▼       ▼
  ┌────┐ ┌────┐ ┌────┐
  │ C1 │ │ C2 │ │ C3 │  (isolated if parent dies)
  └────┘ └────┘ └────┘
```

**New Way (Peer-to-Peer with Seeds):**
```
  ┌────┐gossip┌────┐
  │ S1 │◄────►│ S2 │ (seed nodes)
  └─┬──┘      └─┬──┘
    │gossip gossip│
    ▼           ▼
  ┌────┐     ┌────┐
  │ C1 │◄───►│ C2 │  (all nodes peer)
  └────┘gossip└────┘
```

## Migration Path

1. **Backward Compatible**: Keep `--parent-url` working (maps to single seed)
2. **Deprecation**: Mark `--parent-url` as deprecated, recommend `--seeds`
3. **Hybrid Mode**: Support both simultaneously during transition
4. **Default Behavior**: If no seeds, operate standalone

```typescript
// Config resolution priority
const seeds =
  config.seedUrls ||                    // 1. Explicit --seeds
  (config.parentControllerUrl ? [config.parentControllerUrl] : []) ||  // 2. Legacy --parent-url
  [];                                   // 3. Standalone
```

## Security Considerations

- **Gossip DoS**: Rate limit gossip endpoint (max 10 req/min per peer)
- **Peer Spoofing**: Require API key for gossip (same as other endpoints)
- **Data Integrity**: Events still have cryptographic hash chain
- **Network Partitions**: Accept eventual consistency (AP over CP in CAP)

## Summary

Gossip protocol with seed list provides:
- **Resilience**: No single point of failure
- **Simplicity**: O(log N) convergence, easy to understand
- **Self-Healing**: Network reforms after partitions
- **Zero Downtime**: Nodes join/leave without disruption
- **Minimal Config**: Just need 1-3 seed URLs

This matches distributed systems best practices (Cassandra, Consul, etcd use similar approaches).
