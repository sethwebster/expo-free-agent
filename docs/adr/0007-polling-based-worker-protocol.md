# ADR-0007: Polling-Based Worker-Controller Protocol

**Status:** Accepted

**Date:** 2026-01-27 (Initial commit 47b1097)

## Context

Workers need to discover and claim available builds from controller. Several communication patterns possible:

1. **WebSocket/Long-polling**: Persistent connection, controller pushes jobs
2. **Server-Sent Events (SSE)**: HTTP-based push from server
3. **HTTP short polling**: Worker requests job at intervals
4. **Message queue (RabbitMQ/SQS)**: Workers subscribe to queue

Requirements:
- Prototype simplicity over production scalability
- Work behind NAT/firewalls (many home worker setups)
- Graceful network interruption handling
- No complex infrastructure dependencies

## Decision

Use **HTTP short polling** with 30-second default interval:

```typescript
// Worker loop (Swift)
while true {
  let response = await HTTP.get("/api/workers/poll?worker_id=\(id)")
  if let job = response.job {
    executeBuild(job)
    uploadResults(job)
  }
  sleep(30)  // Configurable poll interval
}
```

**Protocol flow:**
1. Worker sends `GET /api/workers/poll?worker_id=<id>`
2. Controller checks queue for pending builds
3. If available: assigns build, returns `{ job: {...} }`
4. If none: returns `{ job: null }`
5. Worker sleeps 30 seconds, repeats

**Heartbeat integration:**
- Each poll updates worker's `last_seen_at` timestamp
- Stale workers (no poll in 120s) marked offline
- Stale builds reassigned to active workers

## Consequences

### Positive

- **Simple implementation:** ~50 lines of Swift code vs 500+ for WebSocket
- **NAT/firewall friendly:** Outbound HTTP works everywhere
- **No persistent connections:** No connection management complexity
- **Stateless server:** Each request independent, no connection tracking
- **Easy debugging:** Can test with curl: `curl http://controller/api/workers/poll?worker_id=test`
- **Load balancer compatible:** No sticky session requirements
- **Works with reverse proxies:** Nginx/Cloudflare compatible out of the box
- **Graceful network recovery:** Worker automatically reconnects on next poll

### Negative

- **Polling latency:** Builds sit in queue up to 30 seconds before pickup
- **Wasted requests:** Empty polls when queue is empty (network/server overhead)
- **No real-time notifications:** Cannot push urgent jobs to idle workers
- **Scale challenges:** 100 workers = 200 req/min even when idle
- **Battery impact:** Mobile workers (if ever supported) waste battery polling
- **Thundering herd:** All workers polling simultaneously creates load spikes (no backoff/jitter)

### Performance Characteristics

**Best case (build available):**
- Latency: Instant (worker poll coincides with build submission)
- Network: 2 requests (poll + download source)

**Worst case (queue empty):**
- Latency: 30 seconds until next poll
- Network: Wasted poll every 30s

**Typical case (steady state):**
- Latency: ~15 seconds average (half of poll interval)
- Network: 1 request/30s per worker = 2 req/min per worker

**Scaling:**
- 10 workers: 20 req/min (negligible)
- 100 workers: 200 req/min (4 req/s, trivial for HTTP server)
- 1000 workers: 2000 req/min (33 req/s, still manageable)

## Alternative Patterns Considered

### WebSocket Persistent Connection

**Pros:**
- Real-time push notifications (instant job delivery)
- Lower latency (no polling delay)
- Fewer total requests (connection setup once)

**Cons:**
- 200+ lines of connection management code
- Must handle: disconnects, reconnects, heartbeats, timeouts
- Reverse proxy complexity (nginx websocket config)
- Load balancer sticky sessions required
- NAT/firewall traversal issues (some corporate firewalls block WebSocket)
- State management (track active connections server-side)

**Rejected:** Complexity outweighs latency benefit for 5-30 minute builds.

### Server-Sent Events (SSE)

**Pros:**
- HTTP-based (simpler than WebSocket)
- Browser-native fallback to long-polling
- One-way server → client (matches use case)

**Cons:**
- Still requires persistent connection management
- Not well-supported in Swift (requires manual HTTP streaming)
- Same NAT/firewall issues as WebSocket
- Same load balancer complexity

**Rejected:** Provides WebSocket-like complexity with HTTP-like constraints.

### Message Queue (RabbitMQ/Redis/SQS)

**Pros:**
- Industry-standard job distribution
- Automatic retry/dead-letter queues
- Pub/sub for multiple workers
- Durability guarantees

**Cons:**
- External dependency (RabbitMQ installation)
- Another service to monitor/maintain
- Overkill for prototype (thousands of messages/second capacity)
- Workers need queue credentials
- Network firewall requires additional ports

**Rejected:** Violates "zero dependencies" prototype constraint.

### Long Polling

**Pros:**
- Looks like push (request blocks until job available)
- No polling delay
- Still HTTP-based

**Cons:**
- Requires server timeout handling (30s+ connections)
- Connection limit issues (workers hold connections open)
- Reverse proxy timeout configuration needed
- Must handle timeout → reconnect loop (similar complexity to WebSocket)

**Rejected:** Complexity approaches WebSocket without browser compatibility benefit.

## Configuration

Workers can tune polling behavior:
- `POLL_INTERVAL_SECONDS` (default: 30)
- `HEARTBEAT_TIMEOUT_SECONDS` (default: 120)

Controller enforces minimum interval (prevent DDOS):
- Minimum: 5 seconds (configurable)
- Rate limit: 1 req/5s per worker ID

## Future Migration Path

When scaling to 1000+ workers or sub-second latency required:
1. Add WebSocket endpoint alongside polling
2. Workers detect WebSocket support, fall back to polling
3. Gradually migrate workers to WebSocket
4. Retire polling endpoint after migration complete

Or:

1. Introduce Redis pub/sub for job queue
2. Workers subscribe to `builds:pending` channel
3. Controller publishes build IDs to channel
4. Keep polling as fallback for workers behind restrictive firewalls

## Production Optimizations

**Low-hanging fruit (if needed):**
- Add jitter to poll interval (±5s randomization prevents thundering herd)
- Exponential backoff when queue empty (30s → 60s → 120s)
- Batch status updates (combine poll + heartbeat)
- HTTP/2 connection reuse (reduce TLS handshake overhead)
- Conditional requests (304 Not Modified if no pending builds)

## References

- Worker poll loop: `free-agent/Sources/WorkerCore/WorkerService.swift`
- Controller endpoint: `packages/controller/src/api/workers/index.ts` (poll handler)
- Heartbeat logic: `packages/controller/src/services/WorkerService.ts`
- Protocol documentation: `docs/architecture/build-pickup-flow.md`
