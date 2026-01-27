# Expo Free Agent - Roadmap (Jan 26, 2026)

**Project Status:** 65% MVP Complete | 40% Production Ready
**Critical Path:** First real build execution (never achieved)

---

## Current State

### ✅ Completed Components

**Controller (packages/controller/)** - 90% Complete
- ✅ Fastify REST API (migrated from Express)
- ✅ SQLite persistence with schema
- ✅ Job queue with DB restoration on restart
- ✅ File storage abstraction
- ✅ API key authentication
- ✅ Build heartbeat + timeout detection
- ✅ Web UI with demo mode + Chart.js
- ✅ Docker deployment (CapRover)
- ✅ 30 integration tests passing
- ✅ Route path collision fixed (Fastify migration)
- ✅ Build timeout mechanism working

**CLI (cli/)** - 85% Complete
- ✅ submit, status, download, list commands
- ✅ API client with auth
- ✅ Config file support
- ✅ Progress indicators
- ✅ Path traversal protection
- ✅ 28 tests passing
- ✅ Exclude ios/android/cache from uploads

**Free Agent Swift App (free-agent/)** - 70% Complete
- ✅ Menu bar UI with status icons
- ✅ Settings window (SwiftUI)
- ✅ Statistics window with live updates
- ✅ Doctor mode diagnostics
- ✅ WorkerService polling (HTTP layer verified)
- ✅ Migrated to Tart VM management (simpler than Virtualization.framework)
- ✅ Multiple concurrency bugs fixed:
  - ✅ isWorkerProcessRunning blocking
  - ✅ Zombie process cleanup
  - ✅ Concurrent status checks
  - ✅ Timer interval throttled (2s → 5s)

### ❌ Critical Gaps

1. **No real build executed** - System never proven E2E
2. **No VM template** - Tart expects `expo-free-agent-tahoe-26.2-xcode-expo-54` but doesn't exist
3. **Certificate signing untested** - CertificateManager has shell escaping issues
4. **Zero Swift unit tests** - Every change requires manual VM testing
5. **No E2E automation** - No automated integration test

---

## Outstanding Issues (Consolidated from 3 Reviews)

### 🔴 CRITICAL (Blocks Production)

| Issue | Location | Impact | Effort |
|-------|----------|--------|--------|
| No template VM exists | Tart config | Workers can't execute builds | 4-6h manual |
| Shell escaping in CertificateManager | `CertificateManager.swift` | Code signing fails | 1h |
| File type validation missing | Controller routes | Malware upload vector | 1h |
| Swift worker never tested E2E | WorkerService | Unknown runtime failures | 2-4h |

### 🟡 HIGH (Production Quality)

| Issue | Location | Impact | Effort |
|-------|----------|--------|--------|
| No file size limits (streaming) | Controller upload | Memory exhaustion on large files | 4h |
| VMError loses error details | `TartVMManager.swift:362-377` | Hard to debug failures | 1h |
| No logging framework | Swift (uses print) | Can't debug production | 2h |
| Hardcoded template name | TartVMManager line 19 | Inflexible | 30min |

### 🟢 MEDIUM (Enhancements)

| Issue | Location | Impact | Effort |
|-------|----------|--------|--------|
| No build cancellation | Controller API | Poor UX | 2h |
| No worker deregistration | Controller API | Stale workers | 2h |
| No rate limiting | Controller middleware | DoS vulnerability | 2h |
| No structured logging | Controller (console.log) | Poor observability | 3h |
| TartVMManager blocking waitUntilExit | Lines 336-347 | UI freezes | 2h |

### ⚪ NICE TO HAVE

| Issue | Location | Impact | Effort |
|-------|----------|--------|--------|
| Duplicate multipart form building | Swift upload code | DRY violation | 1h |
| Inconsistent error formats | API responses | Inconsistent UX | 2h |
| No health check depth | /health endpoint | Limited monitoring | 1h |

---

## Deferred Work

### Cloudflare Workers Migration
**Status:** PLAN EXISTS, NOT RECOMMENDED
- 8 critical issues identified (data loss, security holes)
- Durable Object state loss on eviction
- Presigned URL auth missing
- Timing attacks on API key
- **Decision:** Fix critical issues in plan OR stay with current stack

### Economic/Credit System
**Status:** DEFERRED TO V2
- Architecture supports it (worker stats tracking)
- Not needed for prototype validation

---

## Roadmap to First Real Build

### Phase 1: VM Infrastructure (4-8 hours)
**Goal:** Create working Tart template

**Tasks:**
1. Install macOS in Tart VM manually
   - Download macOS Tahoe IPSW
   - Create base VM: `tart create expo-free-agent-tahoe-26.2-xcode-expo-54`
   - Boot VM, complete setup assistant
2. Install Xcode 15.4 (Expo SDK 54 requirement)
   - Download from Apple (20GB+, 1-2h)
   - Extract to /Applications
   - Accept license, install CLI tools
3. Configure builder environment
   - Create `builder` user
   - Configure SSH access
   - Setup keychain for code signing
   - Install Node.js, Bun, dependencies
4. Create verification script
   - Check SSH connectivity
   - Verify Xcode installation
   - Test keychain access
   - Validate eas-cli works
5. Clone template for future use
   - `tart clone expo-free-agent-tahoe-26.2-xcode-expo-54 expo-base-template`

**Success Criteria:**
- VM boots and accepts SSH connections
- `eas build --local` runs inside VM
- Template reproducible via `tart clone`

### Phase 2: Fix Critical Swift Bugs (2-3 hours)

**Tasks:**
1. Fix CertificateManager shell escaping
   - Standardize on `~` vs `\\$HOME`
   - Test keychain operations end-to-end
2. Fix VMError information loss
   - Preserve underlying error messages
   - Add context about which operation failed
3. Add file type validation to Controller
   - Validate magic bytes (zip: `504B0304`)
   - Reject non-zip uploads
4. Make template name configurable
   - Move hardcoded name to WorkerConfiguration
   - Allow override via settings UI

**Success Criteria:**
- All shell commands execute correctly in VM
- Error messages are actionable
- Only valid zip files accepted

### Phase 3: First Real Build (4-8 hours)

**Tasks:**
1. Create minimal test Expo project
   - `npx create-expo-app test-app`
   - Minimal dependencies
   - Valid app.json/app.config.ts
2. Prepare signing credentials
   - Development cert + provisioning profile
   - OR adhoc distribution
3. Submit build via CLI
   - `expo-controller submit ./test-app --certs ./certs/`
4. Monitor worker execution
   - Watch logs in doctor mode
   - Track statistics in real-time
5. Debug failures iteratively
   - Expected: 2-4 debugging cycles
   - Common issues: cert installation, network, paths
6. Download + verify IPA
   - `expo-controller download <build-id>`
   - Verify code signature: `codesign -vv result.ipa`

**Success Criteria:**
- Build completes without errors
- IPA downloads successfully
- Code signature valid
- Process documented

### Phase 4: Stabilization (10-15 hours)

**Tasks:**
1. Add E2E test automation
   - Submit → build → download flow
   - Mock simple Expo app
   - Run in CI
2. Add structured logging
   - Pino for controller
   - os.Logger for Swift
   - JSON output for parsing
3. Implement streaming uploads
   - Replace bodyLimit with streaming parser
   - Prevent memory exhaustion
4. Add rate limiting middleware
   - Per-IP throttling
   - Per-worker limits
5. Build cancellation + worker deregistration
   - Cancel endpoint: `DELETE /api/builds/:id`
   - Deregister: `DELETE /api/workers/:id`
6. Document setup end-to-end
   - VM creation walkthrough
   - Worker installation guide
   - Troubleshooting common issues

**Success Criteria:**
- One automated E2E test passing
- Logs parseable for debugging
- Large files don't crash server
- Users can cancel/cleanup

---

## Phase 5: Production Hardening (Future)

**When:** After Phase 4 complete + real usage data

**Tasks:**
- Multi-worker load testing
- Retry logic for transient failures
- Observability (Prometheus/Grafana)
- Worker health monitoring
- Build artifact retention policy
- Performance optimization
- Swift unit test coverage
- Re-evaluate Cloudflare migration

---

## Metrics & Success Tracking

### Current Stats
- Controller tests: 30/30 passing
- CLI tests: 28/28 passing
- Swift tests: 0 (none exist)
- E2E tests: 0
- Real builds executed: 0

### MVP Success Criteria
- [ ] First real build completes successfully
- [ ] IPA installs on physical device
- [ ] Process documented for others
- [ ] One automated E2E test
- [ ] Error logs actionable

### Production Readiness Criteria
- [ ] 10 consecutive successful builds
- [ ] Average build time <25min
- [ ] 95% build success rate
- [ ] Structured logging in place
- [ ] Rate limiting active
- [ ] Monitoring/alerting configured

---

## Priority Matrix

| Task | Value | Effort | Priority |
|------|-------|--------|----------|
| Create VM template | CRITICAL | 6h | P0 |
| Fix CertificateManager | HIGH | 1h | P0 |
| Execute first real build | CRITICAL | 6h | P0 |
| Add file type validation | HIGH | 1h | P1 |
| Add structured logging | MEDIUM | 3h | P1 |
| Streaming uploads | MEDIUM | 4h | P1 |
| E2E test automation | MEDIUM | 4h | P2 |
| Build cancellation | LOW | 2h | P2 |
| Rate limiting | LOW | 2h | P2 |
| Swift unit tests | LOW | 8h | P3 |

---

## Risk Assessment

### High Risk
1. **VM setup complexity** - 15+ manual steps, easy to miss something
   - Mitigation: Write verification script that validates each step
2. **Xcode licensing** - Apple EULA unclear on distributed builds
   - Mitigation: Research Apple developer program terms, consult legal
3. **Certificate security** - Workers have access to signing certs
   - Mitigation: Document trust model clearly, ephemeral keychain

### Medium Risk
1. **Build timeout calibration** - Need real data to set proper limits
   - Mitigation: Start conservative (4h), adjust based on metrics
2. **Network requirements** - Xcode needs SPM, CocoaPods, notarization
   - Mitigation: Allow proxied network, log all connections
3. **Tart reliability** - Newer tech, less battle-tested than Docker
   - Mitigation: Have rollback plan to raw Virtualization.framework

### Low Risk
1. **Storage growth** - Build artifacts accumulate
   - Mitigation: Add retention policy (30 days default)
2. **Worker churn** - Users uninstall app
   - Mitigation: Graceful degradation, fallback to fewer workers

---

## Open Questions

1. **VM template distribution** - How do workers get template? Pre-install? Download? Size: 40GB+
2. **Xcode version matrix** - Support multiple Xcode versions? How handle SDK updates?
3. **Certificate trust model** - Users comfortable sharing signing certs with worker VMs?
4. **Build retention** - How long keep IPAs? Storage costs?
5. **Worker incentives** - What motivates users to run workers? (deferred)
6. **Expo integration** - When/how integrate with EAS? (post-prototype)

---

## Next Immediate Steps

**This Week:**
1. Create Tart VM template (6h blocked time)
2. Fix CertificateManager shell escaping (1h)
3. Execute first real build (6h, expect debugging)
4. Document what worked/failed

**Next Week:**
1. Add file type validation
2. Implement structured logging
3. Write E2E test
4. Deploy to staging environment

**Two Weeks:**
1. Streaming uploads
2. Rate limiting
3. Build cancellation
4. Production deployment decision

---

## Code Review Cleanup Status

### Archived Reviews
- `code-review-2026-01-23-controller.md` - Issues addressed by Fastify migration
- `code-review-production-transition.md` - Partially addressed, consolidated here

### Active Reviews
- `code-review-2026-01-26.md` - Latest comprehensive review (used as source)
- `cloudflare-workers-migration.md` - Deferred, 8 critical issues to fix first

### Action: Clean Up Plans Directory
- Keep: roadmap-jan-26.md (this file), cloudflare-workers-migration.md (reference)
- Archive: code-review-*.md to plans/archive/
- Reason: Consolidate into single source of truth

---

## Summary

**Where We Are:**
- Functional prototype with 65% MVP complete
- Three components compile and communicate
- Demo mode works, HTTP layer verified
- Key architectural decisions proven (Tart, Fastify, SwiftUI)

**Critical Blocker:**
- No VM template = workers can't build = system unproven

**Critical Path (20-25 hours):**
1. Create VM template (6h)
2. Fix cert bugs (1h)
3. First real build (6h)
4. Stabilization (8h)

**Production Ready:** After Phase 4 + real usage validation (30-40 hours total)

**Recommendation:** Focus 100% on Phase 1-3 (first real build) before any other work. Everything else is speculation until we prove the core flow works.
