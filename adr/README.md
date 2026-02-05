# Architecture Decision Records

This directory contains records of significant architectural decisions made in the Expo Free Agent project.

## What is an ADR?

An Architecture Decision Record (ADR) documents important architectural choices, including:
- Context and problem being solved
- Alternatives considered
- Decision made and rationale
- Consequences (positive, negative, neutral)

## Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [001](./adr-001-monorepo-structure.md) | Monorepo Structure - Swift App at Root | Accepted | 2026-01-30 |
| [002](./adr-002-local-signing-manual-xcodebuild.md) | Local Signing With Manual Xcodebuild for iOS Builds | Proposed | 2026-02-05 |

## When to Create an ADR

Document decisions when:
- Choosing between architectural patterns
- Selecting frameworks, libraries, or tools
- Defining API contracts or data models
- Establishing security policies
- Making performance trade-offs
- Changing core infrastructure
- Introducing new dependencies

## Process

1. Copy `template.md` to `adr-NNN-title.md`
2. Fill in all sections
3. Get review from team/agent
4. Update this index
5. Mark status as "Accepted" when implemented

See [CLAUDE.md](../CLAUDE.md) for full ADR guidelines.
