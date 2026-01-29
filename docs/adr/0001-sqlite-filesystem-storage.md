# ADR-0001: Use SQLite + Filesystem Storage for Prototype

**Status:** Accepted

**Date:** 2026-01-27 (Initial commit 47b1097)

## Context

Building a distributed build mesh for Expo apps requires:
- Persistent storage for build metadata (status, worker assignments, logs)
- Artifact storage for build inputs (source code, certificates) and outputs (IPA/APK files)
- Multi-tenant isolation (users should only access their own builds)
- Prototype needs to validate core build execution flow before scaling

Traditional production approach would use:
- PostgreSQL/MySQL for relational data
- S3/cloud storage for large artifacts
- Redis for job queue
- Multi-server deployment with load balancing

## Decision

Use **SQLite + local filesystem** for prototype storage:

- **Database:** SQLite file (`controller.db`) for all relational data
- **Artifacts:** Local filesystem under `data/storage/` directory
- **Job queue:** In-memory JavaScript Map with periodic SQLite sync
- **Auth:** Simple API key in environment variable
- **Deployment:** Single-server process

## Consequences

### Positive

- **Zero configuration:** No database setup, just run the controller
- **Fast iteration:** Schema changes are `CREATE TABLE` statements, no migrations initially
- **Portable:** Entire system state in one directory (easy backup/restore)
- **Debuggable:** SQLite CLI lets you inspect state directly
- **Cost-free:** No cloud dependencies for prototype validation
- **Fast local dev:** No network latency to external services

### Negative

- **Concurrency limits:** SQLite single-writer model later caused race conditions (fixed in v0.1.16)
- **Data loss risk:** In-memory queue lost on crash (later fixed with queue restoration)
- **No horizontal scaling:** Single server bottleneck
- **Storage limits:** Local filesystem capacity limits artifact storage
- **Manual cleanup:** No automatic artifact expiration/deletion
- **Security gaps:** File path traversal risks (mitigated by FileStorage service)
- **Backup complexity:** Must coordinate SQLite + filesystem backups

### Migration Path

When transitioning to production:
1. Migrate to PostgreSQL for better concurrency (completed in Elixir controller)
2. Add S3-compatible storage for artifacts
3. Implement Redis/RabbitMQ for queue
4. Add proper multi-tenant auth (OAuth/JWT)
5. Deploy behind load balancer

## Notes

This decision was **intentional prototyping strategy**:
- Validates build execution flow first
- Defers scaling complexity until concept is proven
- Documents production migration path in architecture docs
- Explicitly calls out prototype constraints

The v0.1.x TypeScript controller ran successfully with this architecture. The Elixir controller migration addressed the main limitation (concurrency) while preserving the simple deployment model.

## References

- Initial implementation: `packages/controller/src/db/schema.sql`
- Storage service: `packages/controller/src/services/FileStorage.ts`
- Architecture doc: `docs/architecture/architecture.md` (prototype constraints section)
