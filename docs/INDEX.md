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

- [Quickstart](./getting-started/quickstart.md) - Fast path to running the system
- [Quicktest](./getting-started/quicktest.md) - Quick validation tests
- [Setup Local](./getting-started/setup-local.md) - Local development setup
- [Setup Remote](./getting-started/setup-remote.md) - Remote deployment setup
- [Quickstart Monitoring](./getting-started/quickstart-monitoring.md) - Monitoring setup

## Architecture

System design, component structure, and technical decisions.

- [Architecture](./architecture/architecture.md) - Overall system design and prototype plan
- [Agents](./architecture/agents.md) - Agent rules and guardrails for code changes
- [CLI Implementation](./architecture/cli-implementation.md) - Submit CLI design
- [VM Implementation](./architecture/vm-implementation.md) - VM execution architecture
- [TS Compatibility Routes](./architecture/ts-compatibility-routes.md) - Elixir controller route aliases for TS API compatibility

## Operations

Production deployment, releases, and operational procedures.

- [Release](./operations/release.md) - FreeAgent.app release process (build/sign/notarize)
- [Gatekeeper](./operations/gatekeeper.md) - macOS code signing and notarization details
- [Worker Installer](./operations/worker-installer.md) - Worker installation process
- [VM Setup](./operations/vm-setup.md) - VM image creation and configuration
- [Secure Cert Status](./operations/secure-cert-status.md) - Certificate handling status

## Testing

Test strategies, test suites, and testing procedures.

- [Testing](./testing/testing.md) - Comprehensive testing documentation
- [Smoketest](./testing/smoketest.md) - Fast sanity checks (30 seconds)
- [Test Summary](./testing/test-summary.md) - Test coverage summary

## Component Documentation

Each component has its own README and component-specific docs:

### Controller (`packages/controller/`)
- [README](../packages/controller/README.md) - Controller overview
- [ROUTES](../packages/controller/ROUTES.md) - API endpoints reference
- [SECURITY](../packages/controller/SECURITY.md) - Security considerations
- [ARCHITECTURE-DDD](../packages/controller/ARCHITECTURE-DDD.md) - Domain-driven design
- [DEPLOYMENT](../packages/controller/DEPLOYMENT.md) - Deployment guide
- [DEPLOY_QUICK_START](../packages/controller/DEPLOY_QUICK_START.md) - Quick deploy

### Submit CLI (`cli/`)
- [README](../cli/README.md) - CLI overview
- [USAGE](../cli/USAGE.md) - Usage examples
- [SECURITY](../cli/SECURITY.md) - Security considerations

### Worker App (`free-agent/`)
- [README](../free-agent/README.md) - Worker app overview
- [QUICK_START](../free-agent/QUICK_START.md) - Quick start guide
- [DISTRIBUTION](../free-agent/DISTRIBUTION.md) - Distribution process

### Worker Installer (`packages/worker-installer/`)
- [README](../packages/worker-installer/README.md) - Installer overview
- [TESTING](../packages/worker-installer/TESTING.md) - Installer testing
- [CHANGELOG](../packages/worker-installer/CHANGELOG.md) - Version history

### Landing Page (`packages/landing-page/`)
- [README](../packages/landing-page/README.md) - Landing page overview
- [DESIGN](../packages/landing-page/DESIGN.md) - Design guidelines
- [EXPO-DESIGN](../packages/landing-page/EXPO-DESIGN.md) - Expo-specific design
- [DARK-MODE](../packages/landing-page/DARK-MODE.md) - Dark mode implementation
- [SETUP](../packages/landing-page/SETUP.md) - Development setup
- [QUICK-START](../packages/landing-page/QUICK-START.md) - Quick start
- [CLOUDFLARE_DEPLOY](../packages/landing-page/CLOUDFLARE_DEPLOY.md) - Cloudflare deployment
- [ROADMAP](../packages/landing-page/ROADMAP.md) - Feature roadmap
- [TESTING-CHECKLIST](../packages/landing-page/TESTING-CHECKLIST.md) - Testing checklist

### Elixir Controller (`packages/controller_elixir/`)
- [README](../packages/controller_elixir/README.md) - Elixir port overview
- [ELIXIR_PORT](../packages/controller_elixir/ELIXIR_PORT.md) - Port details
- [INTEGRATION](../packages/controller_elixir/INTEGRATION.md) - Integration guide
- [AGENTS](../packages/controller_elixir/AGENTS.md) - Agent guidelines

### VM Setup (`vm-setup/`)
- [README](../vm-setup/README.md) - VM setup overview
- [BOOTSTRAP-README](../vm-setup/BOOTSTRAP-README.md) - Bootstrap process
- [FIRST-TIME-INSTALL](../vm-setup/FIRST-TIME-INSTALL.md) - First-time setup
- [TART-SETUP](../vm-setup/TART-SETUP.md) - Tart VM setup
- [VERIFY_NEW_IMAGE](../vm-setup/VERIFY_NEW_IMAGE.md) - Image verification

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

- [CLAUDE.md](../CLAUDE.md) - Agent rules and repo guardrails (MANDATORY reading)
- [Agents](./architecture/agents.md) - Detailed agent behavior expectations

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
- **...understand the architecture** → [Architecture](./architecture/architecture.md)
- **...release a new version** → [Release](./operations/release.md)
- **...run tests** → [Testing](./testing/testing.md)
- **...deploy to production** → [Setup Remote](./getting-started/setup-remote.md)
- **...understand code signing** → [Gatekeeper](./operations/gatekeeper.md)
- **...contribute code** → [CLAUDE.md](../CLAUDE.md)
- **...use the API** → [Controller ROUTES](../packages/controller/ROUTES.md)
- **...debug issues** → [Testing](./testing/testing.md) + component READMEs
