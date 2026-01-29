# Architecture Decision Records (ADRs)

This directory contains Architecture Decision Records (ADRs) — documents that capture important architectural decisions made in this project.

## What is an ADR?

An ADR is a lightweight document that captures a single architectural decision. Each ADR describes:
- **Context**: The problem we're solving and constraints we face
- **Decision**: What we decided to do
- **Consequences**: Positive, negative, and neutral impacts of the decision

## When to create an ADR

Create an ADR for decisions that:
- Change system boundaries or component responsibilities
- Introduce new technologies, frameworks, or dependencies
- Alter data models, API contracts, or storage patterns
- Impact security, performance, or scalability
- Solve non-trivial problems with multiple viable approaches
- Establish patterns that other code should follow

**Don't create ADRs for:**
- Bug fixes or refactoring within existing patterns
- Documentation improvements
- Test additions
- Minor UI tweaks

## ADR format

```markdown
# ADR-NNNN: Title

**Status:** Accepted | Proposed | Superseded by ADR-XXXX

**Date:** YYYY-MM-DD

## Context

What problem are we solving? What constraints exist?

## Decision

What did we decide? Be specific.

## Consequences

**Positive:**
- Benefit 1
- Benefit 2

**Negative:**
- Cost/limitation 1
- Cost/limitation 2

**Neutral:**
- Trade-off 1
```

## Naming convention

- Use sequential numbering: `0001-title.md`, `0002-title.md`, etc.
- Never reuse numbers
- Use lowercase-with-hyphens for titles
- Add entry to `docs/INDEX.md` when creating new ADR

## Example ADRs

Good examples of ADR-worthy decisions:
- "Use SQLite + filesystem instead of S3 for prototype storage"
- "Worker uses native tar extraction for code signing preservation"
- "Controller auth via API key header instead of JWT"
- "EAS Build compatibility layer using adapter pattern"

## ADR lifecycle

**Proposed** → Under discussion, not yet implemented
**Accepted** → Decision made and implementation complete
**Superseded** → Replaced by a newer ADR (link to replacement)

## Index of ADRs

### Accepted

1. [ADR-0001: Use SQLite + Filesystem Storage for Prototype](./0001-sqlite-filesystem-storage.md) - Storage architecture for prototype phase
2. [ADR-0002: Use Tart for VM Management](./0002-tart-vm-management.md) - VM isolation and execution strategy
3. [ADR-0003: Use Native tar and ditto for Code Signature Preservation](./0003-native-tar-ditto-for-code-signing.md) - macOS code signing preservation approach
4. [ADR-0004: Never Manipulate Quarantine Attributes on Notarized Apps](./0004-never-manipulate-quarantine-attributes.md) - Gatekeeper security model compliance
5. [ADR-0005: Enforce Version Synchronization Across All Components](./0005-enforce-version-synchronization.md) - Version management strategy
6. [ADR-0006: Build-Specific Access Tokens for Multi-Tenant Isolation](./0006-build-specific-access-tokens.md) - Authentication and authorization model
7. [ADR-0007: Polling-Based Worker-Controller Protocol](./0007-polling-based-worker-protocol.md) - Worker-controller communication pattern
8. [ADR-0008: VM Auto-Update System for Script Distribution](./0008-vm-auto-update-system.md) - VM script deployment and hotfix strategy
9. [ADR-0009: Migrate Controller from TypeScript to Elixir](./0009-migrate-controller-to-elixir.md) - Controller technology migration for performance and reliability
10. [ADR-0010: Automatic Worker Token Rotation with Short TTL](./0010-worker-token-rotation.md) - Worker authentication security model
11. [ADR-0011: Documentation Structure Reorganization](./0011-documentation-structure-reorganization.md) - Documentation architecture and navigation

### By Category

**Architecture & Design:**
- ADR-0001 (Storage), ADR-0002 (VM Management), ADR-0009 (Controller Migration)

**Security:**
- ADR-0003 (Code Signing), ADR-0004 (Gatekeeper), ADR-0006 (Build Tokens), ADR-0010 (Worker Tokens)

**Operations:**
- ADR-0005 (Version Sync), ADR-0008 (VM Auto-Update)

**Communication:**
- ADR-0007 (Polling Protocol)

**Documentation:**
- ADR-0011 (Docs Structure)

---

For more details on ADR guidelines, see [CLAUDE.md](../../CLAUDE.md#architecture-decision-records-adrs).
