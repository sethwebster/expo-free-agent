# Expo Free Agent - Project Status & Roadmap Evaluation

**Date:** 2026-01-26
**Reviewer:** Code Review
**Focus:** Roadmap completion assessment, production readiness, technical debt

---

## Executive Summary

The expo-free-agent project has **completed approximately 60-70% of its MVP roadmap** but is **NOT production-ready**. The system has three components (controller, CLI, Swift worker) at varying levels of maturity. The controller is the most complete, the CLI is functional but untested in production, and the Swift worker has never executed a real build. Multiple previous code reviews identified critical issues that remain only partially addressed.

**Bottom Line:** This is a functional prototype that proves the architecture works. It is NOT safe to deploy for real builds without significant additional work.

---

## Roadmap Analysis

### ARCHITECTURE.md Defined MVP (6 weeks)

| Week | Component | Target | Status |
|------|-----------|--------|--------|
| 1 | Central Controller | REST API, SQLite, Job Queue, Web UI | COMPLETE |
| 2 | Submit CLI | submit, status, download commands | COMPLETE |
| 3-4 | Free Agent App | Menu bar UI, polling, VM execution | PARTIAL |
| 5-6 | Integration Testing | End-to-end build flow | NOT DONE |

### What's Actually Been Done

**Central Controller (packages/controller)**
- REST API with Fastify (migrated from Express)
- SQLite database (builds, workers, build_logs)
- In-memory job queue with DB persistence/restoration
- File storage abstraction
- Web UI with demo mode and Chart.js
- API key authentication
- Build heartbeat timeout detection
- Docker deployment with CapRover
- ~30 integration tests passing

**CLI (cli/)**
- submit, status, download, list commands
- API client with authentication
- Config file support
- Progress indicators
- Path traversal protection
- ~28 tests passing

**Free Agent Swift App (free-agent/)**
- Menu bar UI with status icons
- Settings window (SwiftUI)
- Statistics window with live updates
- Doctor mode diagnostics
- WorkerService polling
- TartVMManager for VM execution
- DiagnosticsCore with multiple checks

### What's NOT Done

1. **No real build has ever executed** - The Swift worker has never built an actual Expo app
2. **VM infrastructure not validated** - TartVMManager exists but template VM setup incomplete
3. **End-to-end testing absent** - No automated E2E tests exist
4. **Certificate signing untested** - CertificateManager has shell escaping issues
5. **No production monitoring** - Basic logging only, no structured observability

---

## Critical Issues From Previous Reviews

### Issues Fixed Since Last Review

| Issue | Status | Evidence |
|-------|--------|----------|
| Route path collision `/api/workers/poll` | FIXED | Fastify migration resolved |
| `isWorkerProcessRunning()` blocking | FIXED | Uses async/await + DispatchQueue |
| Zombie processes from pgrep | FIXED | `waitUntilExit()` always called |
| Multiple concurrent status checks | FIXED | `isCheckingStatus` guard added |
| Timer interval too aggressive | FIXED | Changed from 2s to 5s |
| Old WorkerService not stopped | FIXED | Stops before replacing |

### Issues Still Outstanding

| Issue | Severity | Location |
|-------|----------|----------|
| No upload size limits on controller | CRITICAL | See Fastify bodyLimit |
| No file type validation on uploads | HIGH | No magic byte validation |
| VMError loses error information | MEDIUM | `/free-agent/Sources/BuildVM/TartVMManager.swift:362-377` |
| Hardcoded template image name | MEDIUM | TartVMManager line 19 |
| No logging framework in Swift | MEDIUM | Uses print() |
| Shell escaping issues in CertificateManager | HIGH | Inconsistent `\\$HOME` vs `~` |
| TartVMManager blocking `waitUntilExit()` | MEDIUM | Lines 336-347 |

---

## Technical Debt Inventory

### [RED] Critical - Blocks Production

1. **Swift Worker Never Tested Against Real Controller**
   - WorkerService.swift has correct API endpoints now (fixed)
   - BUT: No evidence of end-to-end validation
   - No test fixtures for real Expo apps
   - Risk: Unknown runtime failures when deployed

2. **No Template VM Exists**
   - TartVMManager expects `expo-free-agent-tahoe-26.2-xcode-expo-54`
   - No automation to create this image
   - Manual setup requires 15+ steps, 20GB+ downloads
   - Blocker: Workers literally cannot execute builds

3. **Certificate Handling Not Validated**
   - CertificateManager.swift has shell escaping bugs
   - P12 password handling unclear
   - No test coverage for signing workflow

### [YELLOW] Architecture Concerns

1. **Queue State Durability**
   - In-memory queue with DB restoration on startup
   - No WAL mode verification for SQLite
   - Risk: Queue state corruption on crash

2. **No Rate Limiting**
   - Controller accepts unlimited requests
   - No per-IP or per-worker throttling
   - Risk: Easy DoS

3. **Cloudflare Workers Migration Plan Incomplete**
   - Plan exists at `/plans/cloudflare-workers-migration.md`
   - 8 critical issues identified in that review
   - Migration NOT recommended without fixes

4. **Fastify bodyLimit Only Partial Solution**
   - `bodyLimit` is set to max of source/certs/result limits
   - Still allows 500MB uploads that exhaust memory
   - Need streaming uploads for large files

### [GREEN] DRY Opportunities

1. **Duplicate Multipart Form Building in Swift**
   - `uploadBuildResult()` and `reportJobFailure()` share code
   - Should extract shared builder

2. **API Client HTTP Logic**
   - Both CLI and mock worker have similar fetch patterns
   - Could share module

3. **SSH Options Repeated**
   - TartVMManager has shared `sshOptions` array (good)
   - But some calls still inline options

### [BLUE] Maintenance Improvements

1. **No Structured Logging**
   - Controller: `console.log` with timestamps only
   - Swift: raw `print()`
   - Recommendation: pino for TS, os.Logger for Swift

2. **Missing Health Endpoint Details**
   - `/health` returns basic stats
   - No database connectivity check
   - No storage space check

3. **No Build Cancellation**
   - Users cannot cancel pending/stuck builds
   - Must wait for timeout

4. **No Worker Deregistration**
   - Workers registered forever
   - No stale worker cleanup

---

## What's Required for Production

### Phase 1: Minimum Viable (est. 10-15 hours)

| Task | Effort | Why |
|------|--------|-----|
| Create template VM with Xcode | 4-6h | Blocker: workers can't build |
| Validate Swift worker E2E | 2-4h | Proves system works |
| Fix CertificateManager escaping | 1h | Signing will fail |
| Add file type validation | 1h | Security |
| Document VM setup process | 2h | Enable others |

### Phase 2: Production Hardening (est. 15-20 hours)

| Task | Effort | Why |
|------|--------|-----|
| Streaming uploads for large files | 4h | Memory exhaustion |
| Rate limiting middleware | 2h | DoS protection |
| Structured logging | 3h | Debugging |
| Build cancellation endpoint | 2h | User experience |
| Worker deregistration + cleanup | 2h | Maintenance |
| E2E test automation | 4h | Regression prevention |

### Phase 3: Scale Prep (future)

| Task | Why |
|------|-----|
| Cloudflare Workers migration | Global distribution |
| Multi-worker load testing | Verify queue logic |
| Observability (metrics, traces) | Production debugging |

---

## Honest Assessment

### Strengths

1. **Clean Architecture** - Separation of concerns is solid. Controller/CLI/Worker boundaries are well-defined. DDD patterns applied appropriately.

2. **Test Coverage for TypeScript** - Controller and CLI have meaningful integration tests. The mock worker enables testing without real VMs.

3. **Swift Code Compiles** - Despite never running real builds, the Swift codebase compiles cleanly. Concurrency bugs from earlier reviews have been fixed.

4. **Documentation Exists** - ARCHITECTURE.md, QUICKSTART.md, and plan files provide context. Not complete, but better than average.

5. **Security Consciousness** - API key auth, path traversal protection, worker verification patterns are present even if incomplete.

### Weaknesses

1. **No End-to-End Validation** - The most critical weakness. The entire system's purpose is to build apps, and that has never been tested.

2. **Infrastructure Gap** - The gap between "code exists" and "system works" is the missing VM template. This is a hard prerequisite.

3. **Incomplete Error Recovery** - Build failures, worker crashes, network issues - the happy path works, but error handling is shallow.

4. **Swift Code Untested** - Zero unit tests for Swift. Every change requires manual testing with slow feedback loop.

5. **Production Operations Missing** - No monitoring, no alerting, no runbooks for common failures.

---

## Recommendations

### Immediate (before any deployment)

1. **Create one working VM** - Manually follow the setup process, document every step, verify `eas build --local` works inside it.

2. **Run one real build** - Submit a minimal Expo app through the CLI, watch it flow through the system, download the IPA.

3. **Fix the blockers** - CertificateManager escaping, VMError information loss, any issues discovered during the real build.

### Short-term (next 2 weeks)

1. **Automate VM creation** - Script the template creation so others can reproduce it.

2. **Add E2E test** - Even one automated test that submits a build and waits for completion provides massive confidence.

3. **Improve logging** - When builds fail in production, you need logs to debug. Add structured logging now.

### Long-term (next month)

1. **Cloudflare migration** - Only after the critical issues in that plan are fixed.

2. **Multi-worker testing** - Verify the queue handles concurrent workers correctly.

3. **Production monitoring** - Prometheus/Grafana or similar for visibility.

---

## Unresolved Questions

1. **Template VM storage** - Where do workers get the template? Local pre-install? Network download? Registry?
2. **Xcode licensing** - Apple EULA compliance for distributed builds?
3. **Certificate trust** - How do users trust workers with their signing certs?
4. **Build retention** - How long are artifacts stored? What cleanup policy?
5. **Worker incentives** - Why would anyone run a worker? Credit system deferred.

---

## Summary

The expo-free-agent project is a **promising prototype** with solid foundations. The code quality is good, the architecture is sound, and the test coverage for TypeScript components is meaningful. However, **the system has never actually built an app**, which is its entire purpose.

**Production readiness: 40%**
- Code completeness: 70%
- Integration testing: 20%
- Infrastructure: 30%
- Documentation: 50%
- Operations readiness: 10%

The critical path is:
1. Create working VM template
2. Execute one real build
3. Fix issues discovered
4. Add E2E automation
5. Deploy cautiously

Without steps 1-3, deployment will fail immediately. This is not a criticism of the code - it's recognition that systems need integration testing before production.
