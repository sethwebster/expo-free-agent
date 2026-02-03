# Expo Free Agent Documentation Index

Central index for all documentation in this repository.

## Quick Navigation

- **New to the project?** Start with [Getting Started](#getting-started)
- **Setting up locally?** See [Setup Local](./getting-started/setup-local.md)
- **Want to understand the system?** Read [Architecture](./architecture/architecture.md)
- **Deploying or releasing?** Check [Operations](#operations)
- **Running tests?** See [Testing](#testing)

## Getting Started

Essential guides for new users and contributors.

- [**5-Minute Start**](./getting-started/5-minute-start.md) - Get running in 5 minutes (start here!)
- [Quickstart](./getting-started/quickstart.md) - Fast path to running the system
- [Quicktest](./getting-started/quicktest.md) - Quick validation tests
- [Setup Local](./getting-started/setup-local.md) - Local development setup
- [Setup Remote](./getting-started/setup-remote.md) - Remote deployment setup
- [Quickstart Monitoring](./getting-started/quickstart-monitoring.md) - Monitoring setup

## Architecture

System design, component structure, and technical decisions.

- **[Complete Architecture Guide](../ARCHITECTURE.md)** - Comprehensive system architecture (START HERE)
- **[Agent Workspace Guide](../AGENT-WORKSPACE.md)** - For AI agents working on the codebase
- [Architecture](./architecture/architecture.md) - Overall system design and prototype plan (historical)
- [Diagrams](./architecture/diagrams.md) - Visual architecture diagrams and flows
- [Security](./architecture/security.md) - Security model, threat mitigation, and isolation
- [Build Pickup Flow](./architecture/build-pickup-flow.md) - Complete build assignment transaction lifecycle
- [Agents](./architecture/agents.md) - Agent rules and guardrails for code changes
- [CLI Implementation](./architecture/cli-implementation.md) - Submit CLI design
- [VM Implementation](./architecture/vm-implementation.md) - VM execution architecture
- [TS Compatibility Routes](./architecture/ts-compatibility-routes.md) - Elixir controller route aliases for TS API compatibility

## Architecture Decision Records

Lightweight documents capturing key architectural decisions made throughout the project.

- [ADR Index](./adr/README.md) - Overview, format guide, and full index

### Core Architecture
- [ADR-0001: SQLite + Filesystem Storage](./adr/0001-sqlite-filesystem-storage.md) - Prototype storage strategy
- [ADR-0002: Tart for VM Management](./adr/0002-tart-vm-management.md) - VM isolation approach
- [ADR-0009: Migrate to Elixir Controller](./adr/0009-migrate-controller-to-elixir.md) - Controller technology migration

### Security & Distribution
- [ADR-0003: Native tar/ditto for Code Signing](./adr/0003-native-tar-ditto-for-code-signing.md) - macOS signature preservation
- [ADR-0004: Never Manipulate Quarantine Attributes](./adr/0004-never-manipulate-quarantine-attributes.md) - Gatekeeper compliance
- [ADR-0006: Build-Specific Access Tokens](./adr/0006-build-specific-access-tokens.md) - Multi-tenant authentication
- [ADR-0010: Worker Token Rotation](./adr/0010-worker-token-rotation.md) - Short-lived worker credentials

### Operations & Communication
- [ADR-0005: Version Synchronization](./adr/0005-enforce-version-synchronization.md) - Monorepo version management
- [ADR-0007: Polling-Based Protocol](./adr/0007-polling-based-worker-protocol.md) - Worker-controller communication
- [ADR-0008: VM Auto-Update System](./adr/0008-vm-auto-update-system.md) - Script distribution and hotfixes

### Documentation
- [ADR-0011: Documentation Reorganization](./adr/0011-documentation-structure-reorganization.md) - Docs structure and navigation

## Operations

Production deployment, releases, and operational procedures.

- [Release](./operations/release.md) - FreeAgent.app release process (build/sign/notarize)
- [Runbook](./operations/runbook.md) - Day-to-day operational procedures and emergency response
- [Notarization Setup](./operations/notarization-setup.md) - One-time notarization credentials setup
- [Troubleshooting](./operations/troubleshooting.md) - Comprehensive troubleshooting guide
- [Gatekeeper](./operations/gatekeeper.md) - macOS code signing and notarization details
- [Worker Installer](./operations/worker-installer.md) - Worker installation process
- [VM Setup](./operations/vm-setup.md) - VM image creation and configuration
- [Secure Cert Status](./operations/secure-cert-status.md) - Certificate handling status

## Testing

Test strategies, test suites, and testing procedures.

- [Testing](./testing/testing.md) - Comprehensive testing documentation
- [Smoketest](./testing/smoketest.md) - Fast sanity checks (30 seconds)
- [Test Summary](./testing/test-summary.md) - Test coverage summary

## Reference

API references, error codes, and technical specifications.

- [API Reference](./reference/api.md) - Complete REST API documentation
- [Error Reference](./reference/errors.md) - Complete error code catalog with solutions

## Examples

Complete, runnable examples for common workflows.

- [Build for TestFlight](../examples/01-build-for-testflight/) - End-to-end iOS app deployment
- [Setup Worker Mac](../examples/02-setup-worker-mac/) - Configure Mac hardware as worker
- [Custom Build Pipeline](../examples/03-custom-build-pipeline/) - Advanced build configuration
- [Debug Failed Build](../examples/04-debug-failed-build/) - Troubleshooting build failures
- [Deploy Controller to VPS](../examples/05-deploy-controller-vps/) - Production deployment

## Component Documentation

Each component has its own README and component-specific docs:

### Controller

Component-specific docs in `packages/controller/`:
- [README](../packages/controller/README.md) - Controller overview
- [ROUTES](../packages/controller/ROUTES.md) - API endpoints reference

### Submit CLI

Component-specific docs in `packages/cli/`:
- [README](../cli/README.md) - CLI overview

### Worker App

Component-specific docs in `free-agent/`:
- [README](../free-agent/README.md) - Worker app overview

### Worker Installer

Component-specific docs in `packages/worker-installer/`:
- [README](../packages/worker-installer/README.md) - Installer overview

## Historical Documentation

Archived documentation, completion reports, and planning docs.

- [Week 1 Complete](./historical/week1-complete.md) - Week 1 milestone
- [Week 3-4 Summary](./historical/week3-4-summary.md) - Week 3-4 progress
- [Plans Archive](./historical/plans/) - Historical planning documents
  - [Root Plans](./historical/plans/) - Project-level plans
  - [CLI Plans](./historical/plans/cli/) - CLI-specific plans
  - [Controller Plans](./historical/plans/controller/) - Controller plans
  - [Free Agent Plans](./historical/plans/free-agent/) - Worker app plans
  - [Landing Page Plans](./historical/plans/landing-page/) - Landing page plans
- [Implementation Status](./historical/IMPLEMENTATION_STATUS.md) - Historical status
- [Completion Report](./historical/COMPLETION-REPORT.md) - Landing page completion
- [Implementation Summary](./historical/IMPLEMENTATION-SUMMARY.md) - Implementation notes
- [Deliverables](./historical/DELIVERABLES.md) - Historical deliverables
- [Done](./historical/DONE.md) - Completed items
- [Contrast Fixes](./historical/CONTRAST-FIXES.md) - UI contrast improvements
- [Redesign](./historical/REDESIGN.md) - Redesign notes
- [Changelog P0 Fixes](./historical/CHANGELOG-P0-FIXES.md) - Critical fixes
- [Worker Installer Implementation](./historical/IMPLEMENTATION.md) - Implementation notes
- [Worker Installer TODO](./historical/TODO.md) - Historical TODOs

## Contributing

For contributors and automated agents:

- [Contributing Guide](./contributing/GUIDE.md) - Complete contributor guide
- [Accessibility Guide](./contributing/accessibility.md) - Making documentation accessible
- [Maintaining Documentation](./contributing/maintaining-docs.md) - Keeping docs up-to-date
- [CLAUDE.md](../CLAUDE.md) / [AGENTS.md](../AGENTS.md) - Agent rules and repo guardrails (MANDATORY reading)
- [Agents](./architecture/agents.md) - Full agent development guide (same as CLAUDE.md/AGENTS.md)

## Key Workflows

### Local Development
1. Read [Setup Local](./getting-started/setup-local.md)
2. Run [Smoketest](./testing/smoketest.md)
3. Review [Testing](./testing/testing.md)

### Release Management
1. Review [Release](./operations/release.md)
2. Understand [Gatekeeper](./operations/gatekeeper.md)
3. Follow version sync requirements in [CLAUDE.md](../CLAUDE.md)

### System Understanding
1. Start with [Architecture](./architecture/architecture.md)
2. Review component-specific READMEs
3. Check [Testing](./testing/testing.md) for validation

## Repository Structure

```
expo-free-agent/
├── docs/                     # All documentation (you are here)
│   ├── INDEX.md             # This file
│   ├── getting-started/     # Setup and quickstart guides
│   ├── architecture/        # System design and decisions
│   ├── adr/                 # Architecture Decision Records
│   ├── operations/          # Deployment and release procedures
│   ├── testing/            # Testing documentation
│   ├── reference/          # Reference materials (future)
│   └── historical/         # Archived docs and plans
├── packages/
│   ├── controller/         # Central controller (each has own docs)
│   ├── landing-page/       # Marketing site
│   ├── worker-installer/   # Worker installation CLI
│   └── controller_elixir/  # Elixir port (experimental)
├── cli/                    # Build submission CLI
├── free-agent/            # macOS worker app
├── vm-setup/              # VM image setup scripts
├── test/                  # Test fixtures and utilities
├── README.md             # Project overview (start here!)
└── CLAUDE.md             # Agent rules (MANDATORY for contributors)
```

## Documentation Standards

- All paths use lowercase with hyphens (e.g., `setup-local.md`)
- Root-level `README.md` and `CLAUDE.md` remain at project root
- Component-specific docs stay in component directories
- Historical/obsolete docs moved to `docs/historical/`
- Plans and code reviews archived in `docs/historical/plans/`

## Finding What You Need

**I want to...**
- **...get started quickly** → [Quickstart](./getting-started/quickstart.md)
- **...set up my local environment** → [Setup Local](./getting-started/setup-local.md)
- **...understand the complete architecture** → [Complete Architecture Guide](../ARCHITECTURE.md)
- **...see visual diagrams** → [Architecture Diagrams](./architecture/diagrams.md)
- **...understand security** → [Security](./architecture/security.md)
- **...understand build assignment** → [Build Pickup Flow](./architecture/build-pickup-flow.md)
- **...work as an AI agent** → [Agent Workspace](../AGENT-WORKSPACE.md)
- **...release a new version** → [Release](./operations/release.md)
- **...run tests** → [Testing](./testing/testing.md)
- **...deploy to production** → [Setup Remote](./getting-started/setup-remote.md)
- **...understand code signing** → [Gatekeeper](./operations/gatekeeper.md)
- **...contribute code** → [CLAUDE.md](../CLAUDE.md)
- **...use the API** → [Controller ROUTES](../packages/controller/ROUTES.md)
- **...debug issues** → [Testing](./testing/testing.md) + component READMEs

---

## Documentation Feedback

**Was this helpful?** 👍 👎

Help us improve the documentation:
- [Report an issue](https://github.com/expo/expo-free-agent/issues/new?labels=documentation)
- [Suggest improvements](https://github.com/expo/expo-free-agent/discussions)
- [Edit any page](https://github.com/expo/expo-free-agent/tree/main/docs)

**Can't find what you need?**
- Search [GitHub Discussions](https://github.com/expo/expo-free-agent/discussions)
- Check [Troubleshooting Guide](./operations/troubleshooting.md)
- Ask in [GitHub Issues](https://github.com/expo/expo-free-agent/issues)
