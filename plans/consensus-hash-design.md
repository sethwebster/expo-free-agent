# Network Consensus Hash for Drift Detection

## Problem Statement

In a distributed system with eventual consistency, we need to detect when controllers have **diverged** from each other:

1. **Event log inconsistency**: Controller A has events 1-100, Controller B has 1-98 + 101-102 (missing events)
2. **State drift**: Same events but applied differently due to bugs
3. **Split brain**: Network partition healed but states never reconciled
4. **Malicious tampering**: One controller has tampered event log

**Current Design Gap:**
- Individual event hash chain detects tampering within ONE controller
- No mechanism to detect DIVERGENCE between controllers
- Controllers could silently drift apart without detection

## Solution: Merkle Root Consensus Hash

### Concept

Each controller maintains a **Merkle tree root hash** of its event log. During gossip, controllers exchange and compare these hashes to detect drift.

```
Controller A Event Log:          Controller B Event Log:
Events: [E1, E2, E3, E4, E5]    Events: [E1, E2, E3, E4, E5]
                ↓                               ↓
         Merkle Root Hash                Merkle Root Hash
         (sha256: abc123...)             (sha256: abc123...)
                ↓                               ↓
              MATCH ✅                       MATCH ✅

Controller C Event Log:
Events: [E1, E2, E3, E4, E6]  ← Different event!
                ↓
         Merkle Root Hash
         (sha256: def456...)  ← Different hash!
                ↓
           MISMATCH ❌
```

### How It Works

1. **Incremental Merkle Tree**: Build tree as events are appended
2. **Gossip Exchange**: Include Merkle root in every gossip message
3. **Hash Comparison**: If hashes differ, trigger reconciliation
4. **Binary Search**: Find first divergence point via bisection
5. **Automatic Healing**: Fetch missing/different events from majority

## Merkle Tree Structure

```
                  Root Hash
                  /        \
              H(E1-E2)    H(E3-E4)
              /    \      /    \
           H(E1) H(E2) H(E3) H(E4)
             |     |     |     |
            E1    E2    E3    E4
```

**Properties:**
- Any change to any event changes the root hash
- Can pinpoint divergence with O(log N) queries
- Lightweight: only store root hash + intermediate nodes

## Database Schema

```sql
-- Add Merkle root hash to controller nodes
ALTER TABLE controller_nodes ADD COLUMN merkle_root TEXT;

-- Add Merkle tree cache for fast verification
CREATE TABLE merkle_tree (
  level INTEGER NOT NULL,        -- Tree level (0 = leaves, 1 = parents, etc.)
  position INTEGER NOT NULL,     -- Position at this level
  hash TEXT NOT NULL,            -- SHA-256 hash
  sequence_start INTEGER,        -- First event in this subtree
  sequence_end INTEGER,          -- Last event in this subtree
  PRIMARY KEY (level, position)
);

CREATE INDEX idx_merkle_sequence ON merkle_tree(sequence_start, sequence_end);

-- Track detected inconsistencies
CREATE TABLE network_inconsistencies (
  id TEXT PRIMARY KEY,
  detected_at INTEGER NOT NULL,
  peer_id TEXT NOT NULL,
  our_merkle_root TEXT NOT NULL,
  their_merkle_root TEXT NOT NULL,
  divergence_sequence INTEGER,   -- First different event sequence
  resolved_at INTEGER,
  resolution TEXT,               -- 'we_synced' | 'they_synced' | 'manual'
  FOREIGN KEY (peer_id) REFERENCES controller_nodes(id)
);
```

## Implementation

### 1. Merkle Tree Builder

```typescript
class MerkleTreeBuilder {
  constructor(private db: Database) {}

  /**
   * Build Merkle tree from event log
   * Called after appending events
   */
  async rebuildTree(): Promise<string> {
    // Clear existing tree
    this.db.prepare('DELETE FROM merkle_tree').run();

    // Get all events ordered by sequence
    const events = await this.db.prepare<EventRow>(
      'SELECT * FROM event_log ORDER BY sequence ASC'
    ).all();

    if (events.length === 0) {
      return '0000000000000000000000000000000000000000000000000000000000000000'; // Empty tree
    }

    // Level 0: Hash each event
    const leafHashes = events.map((event, idx) => {
      const hash = crypto.createHash('sha256')
        .update(event.event_hash) // Use existing event hash
        .digest('hex');

      this.db.prepare(
        'INSERT INTO merkle_tree (level, position, hash, sequence_start, sequence_end) VALUES (?, ?, ?, ?, ?)'
      ).run(0, idx, hash, event.sequence, event.sequence);

      return { hash, start: event.sequence, end: event.sequence };
    });

    // Build tree bottom-up
    let currentLevel = leafHashes;
    let level = 1;

    while (currentLevel.length > 1) {
      const nextLevel = [];

      for (let i = 0; i < currentLevel.length; i += 2) {
        const left = currentLevel[i];
        const right = currentLevel[i + 1] || left; // Duplicate last if odd

        const combinedHash = crypto.createHash('sha256')
          .update(left.hash + right.hash)
          .digest('hex');

        const node = {
          hash: combinedHash,
          start: left.start,
          end: right.end,
        };

        this.db.prepare(
          'INSERT INTO merkle_tree (level, position, hash, sequence_start, sequence_end) VALUES (?, ?, ?, ?, ?)'
        ).run(level, Math.floor(i / 2), combinedHash, node.start, node.end);

        nextLevel.push(node);
      }

      currentLevel = nextLevel;
      level++;
    }

    // Root hash is top of tree
    return currentLevel[0].hash;
  }

  /**
   * Incrementally update tree when new event added
   * More efficient than full rebuild
   */
  async appendEvent(event: Event): Promise<string> {
    // For MVP, do full rebuild
    // Production: implement incremental update
    return this.rebuildTree();
  }

  /**
   * Get current Merkle root hash
   */
  async getRootHash(): Promise<string> {
    const root = this.db.prepare<{ hash: string }>(
      'SELECT hash FROM merkle_tree ORDER BY level DESC, position ASC LIMIT 1'
    ).get();

    return root?.hash || '0000000000000000000000000000000000000000000000000000000000000000';
  }
}
```

### 2. Consensus Verification During Gossip

```typescript
class GossipService {
  async doGossip() {
    const targets = this.selectGossipTargets();
    const ourMerkleRoot = await this.merkleTree.getRootHash();
    const ourEventCount = await this.eventLog.count();

    for (const peer of targets) {
      try {
        const response = await fetch(`${peer.url}/api/peers/gossip`, {
          method: 'POST',
          headers: { 'X-API-Key': this.config.apiKey },
          body: JSON.stringify({
            peers: this.getPeerList(),
            merkleRoot: ourMerkleRoot,      // NEW: Include our Merkle root
            eventCount: ourEventCount,       // NEW: Include our event count
          }),
        });

        const data = await response.json();

        // NEW: Compare Merkle roots
        if (data.merkleRoot !== ourMerkleRoot) {
          console.warn(`⚠️  Merkle root mismatch with ${peer.name}!`);
          console.warn(`   Our root:   ${ourMerkleRoot}`);
          console.warn(`   Their root: ${data.merkleRoot}`);
          console.warn(`   Our events: ${ourEventCount}, Their events: ${data.eventCount}`);

          // Log inconsistency
          await this.logInconsistency(peer.id, ourMerkleRoot, data.merkleRoot);

          // Trigger reconciliation
          await this.reconcileWith(peer, ourEventCount, data.eventCount);
        }

        // Merge peer lists as usual
        this.mergePeerList(data.peers);
        await this.updatePeerStatus(peer.id, 'active', data.merkleRoot);

      } catch (err) {
        await this.handleGossipFailure(peer.id);
      }
    }
  }
}
```

### 3. Reconciliation Algorithm

```typescript
class NetworkReconciliation {
  /**
   * Reconcile event log with peer when Merkle roots differ
   */
  async reconcileWith(
    peer: PeerInfo,
    ourEventCount: number,
    theirEventCount: number
  ): Promise<void> {
    // Determine who is likely behind
    if (theirEventCount > ourEventCount) {
      // They have more events - we need to sync from them
      await this.syncEventsFrom(peer, ourEventCount);
    } else if (ourEventCount > theirEventCount) {
      // We have more events - they should sync from us
      // Just log; they'll reconcile when they gossip with us
      console.log(`📤 Waiting for ${peer.name} to sync from us`);
    } else {
      // Same count but different hash - DIVERGENCE!
      await this.findAndResolveDoivergence(peer);
    }
  }

  /**
   * Sync missing events from peer
   */
  async syncEventsFrom(peer: PeerInfo, fromSequence: number): Promise<void> {
    console.log(`📥 Syncing events from ${peer.name} (from sequence ${fromSequence})...`);

    const response = await fetch(
      `${peer.url}/api/events/since/${fromSequence}?limit=1000`,
      { headers: { 'X-API-Key': this.config.apiKey } }
    );

    const data = await response.json();
    const events = data.events as Event[];

    for (const event of events) {
      try {
        // Receive and validate event
        await this.eventLog.receive(event);
        console.log(`  ✅ Synced event ${event.sequence} (${event.eventType})`);
      } catch (err) {
        console.error(`  ❌ Failed to sync event ${event.sequence}:`, err);
        throw err; // Stop on error
      }
    }

    // Rebuild Merkle tree after sync
    const newRoot = await this.merkleTree.rebuildTree();
    console.log(`📊 Merkle root after sync: ${newRoot}`);
  }

  /**
   * Find first divergence point using binary search
   */
  async findDivergencePoint(peer: PeerInfo): Promise<number> {
    const ourCount = await this.eventLog.count();

    // Binary search for first different event
    let left = 1;
    let right = ourCount;
    let firstDivergence = -1;

    while (left <= right) {
      const mid = Math.floor((left + right) / 2);

      // Get our event at sequence mid
      const ourEvents = await this.eventLog.getSince(mid - 1, 1);
      const ourEvent = ourEvents[0];

      // Get their event at sequence mid
      const response = await fetch(
        `${peer.url}/api/events/since/${mid - 1}?limit=1`,
        { headers: { 'X-API-Key': this.config.apiKey } }
      );
      const theirData = await response.json();
      const theirEvent = theirData.events[0];

      if (!theirEvent || ourEvent.eventHash !== theirEvent.eventHash) {
        // Divergence found - search left half
        firstDivergence = mid;
        right = mid - 1;
      } else {
        // Same - search right half
        left = mid + 1;
      }
    }

    return firstDivergence;
  }

  /**
   * Resolve divergence (same count, different hashes)
   */
  async findAndResolveDoivergence(peer: PeerInfo): Promise<void> {
    console.warn(`🔍 Divergence detected with ${peer.name} - finding first difference...`);

    const divergenceSeq = await this.findDivergencePoint(peer);

    if (divergenceSeq === -1) {
      console.log(`✅ No divergence found (hash collision or resolved)`);
      return;
    }

    console.warn(`⚠️  Divergence at sequence ${divergenceSeq}`);

    // Log for manual review
    await this.db.prepare(
      `INSERT INTO network_inconsistencies
       (id, detected_at, peer_id, our_merkle_root, their_merkle_root, divergence_sequence)
       VALUES (?, ?, ?, ?, ?, ?)`
    ).run(
      crypto.randomUUID(),
      Date.now(),
      peer.id,
      await this.merkleTree.getRootHash(),
      peer.merkleRoot,
      divergenceSeq
    );

    // Strategy: Trust majority
    // If most controllers have hash X, we adopt hash X
    // This requires querying multiple peers - simplified for MVP:
    console.error(`❌ MANUAL INTERVENTION REQUIRED`);
    console.error(`   Event logs have diverged at sequence ${divergenceSeq}`);
    console.error(`   Administrator must investigate and resolve`);
  }
}
```

### 4. API Updates

```typescript
// Enhanced gossip endpoint
POST /api/peers/gossip
Request:
{
  peers: [...],
  merkleRoot: "sha256-hash",
  eventCount: 1234
}

Response:
{
  peers: [...],
  merkleRoot: "sha256-hash",
  eventCount: 1234
}

// New verification endpoint
GET /api/network/verify
Response:
{
  ourMerkleRoot: "sha256...",
  eventCount: 1234,
  peers: [
    {
      id: "ctrl-a",
      name: "Controller A",
      merkleRoot: "sha256...",  // Same = consistent
      eventCount: 1234,
      consistent: true
    },
    {
      id: "ctrl-b",
      name: "Controller B",
      merkleRoot: "sha256-diff...",  // Different!
      eventCount: 1230,
      consistent: false,
      divergenceSequence: 1150
    }
  ]
}
```

## Detecting Network-Wide Issues

### Dashboard View

```
Network Consistency Status:

Controllers: 5 total
├─ Consistent:   4 (80%)
├─ Diverged:     1 (20%)
└─ Unreachable:  0 (0%)

Merkle Root Distribution:
├─ abc123... : 4 controllers (MAJORITY) ✅
└─ def456... : 1 controller  (MINORITY) ⚠️

Detected Issues:
⚠️  Controller C has diverged at sequence 1150
    - Last consistent: Event 1149
    - Their root: def456...
    - Majority root: abc123...
    - Action: Controller C should sync from majority
```

### Automatic Healing

```typescript
async autoHeal() {
  // Get our Merkle root
  const ourRoot = await this.merkleTree.getRootHash();

  // Poll all peers for their roots
  const peers = await this.registry.getActive();
  const rootCounts = new Map<string, number>();

  for (const peer of peers) {
    const root = peer.merkleRoot || 'unknown';
    rootCounts.set(root, (rootCounts.get(root) || 0) + 1);
  }

  // Add ourselves
  rootCounts.set(ourRoot, (rootCounts.get(ourRoot) || 0) + 1);

  // Find majority root
  let majorityRoot = ourRoot;
  let majorityCount = 1;

  for (const [root, count] of rootCounts) {
    if (count > majorityCount) {
      majorityRoot = root;
      majorityCount = count;
    }
  }

  // Are we in minority?
  if (ourRoot !== majorityRoot && majorityCount > peers.length / 2) {
    console.warn(`⚠️  We are in MINORITY (our root: ${ourRoot})`);
    console.warn(`   Majority root: ${majorityRoot} (${majorityCount} controllers)`);
    console.warn(`   Auto-healing: Syncing from majority...`);

    // Find peer with majority root
    const majorityPeer = peers.find(p => p.merkleRoot === majorityRoot);
    if (majorityPeer) {
      await this.reconciliation.syncEventsFrom(majorityPeer, 0);
    }
  }
}
```

## Performance Considerations

### Merkle Tree Rebuild Cost

```
Full rebuild on every event:
- 10,000 events: ~50ms
- 100,000 events: ~500ms
- 1,000,000 events: ~5s

Optimization: Incremental update
- Rebuild only affected path: O(log N)
- 1,000,000 events: <10ms per append
```

### Gossip Overhead

```
Before: 1KB gossip message (peer list)
After: 1KB + 64 bytes (Merkle root hash)
Overhead: 6% increase (negligible)
```

## Summary

**Merkle Root Consensus Hash provides:**

✅ **Drift Detection**: Detect when controllers have diverged
✅ **Fast Verification**: O(1) comparison during gossip
✅ **Pinpoint Divergence**: O(log N) binary search to find first difference
✅ **Automatic Healing**: Sync from majority when in minority
✅ **Lightweight**: Only 64-byte hash exchanged per gossip
✅ **Audit Trail**: Log all inconsistencies for investigation

**Protects Against:**
- Missing events (network partition)
- State drift (bugs in event application)
- Split brain (unreconciled partitions)
- Malicious tampering (altered event logs)

**Complements Existing Design:**
- Event hash chain: Detects tampering within ONE controller
- Merkle root: Detects divergence BETWEEN controllers
- Together: Complete integrity verification
