# Expo Free Agent Documentation

All documentation is organized here. Start with **[INDEX.md](./INDEX.md)** for complete navigation.

## Quick Links

- [Documentation Index](./INDEX.md) - Complete documentation navigation
- [Getting Started](./getting-started/) - Setup guides and quickstarts
- [Architecture](./architecture/) - System design and technical decisions
- [Operations](./operations/) - Deployment, releases, and procedures
- [Testing](./testing/) - Test strategies and procedures
- [Historical](./historical/) - Archived docs and plans

## Directory Structure

```
docs/
├── INDEX.md              # Complete documentation index (start here)
├── README.md            # This file
├── getting-started/     # Setup and quickstart guides
│   ├── quickstart.md
│   ├── quicktest.md
│   ├── setup-local.md
│   ├── setup-remote.md
│   └── quickstart-monitoring.md
├── architecture/        # System design and decisions
│   ├── architecture.md  # Overall system design
│   ├── agents.md       # Agent rules (MANDATORY for contributors)
│   ├── cli-implementation.md
│   └── vm-implementation.md
├── operations/          # Deployment and release procedures
│   ├── release.md
│   ├── gatekeeper.md
│   ├── worker-installer.md
│   ├── vm-setup.md
│   └── secure-cert-status.md
├── testing/            # Testing documentation
│   ├── testing.md
│   ├── smoketest.md
│   └── test-summary.md
├── reference/          # Reference materials (future)
└── historical/         # Archived docs and plans
    ├── plans/
    └── *.md
```

## Contributing

For contributors and automated agents:
- **MANDATORY**: Read [agents.md](./architecture/agents.md) (also accessible via `/CLAUDE.md`)
- Review [INDEX.md](./INDEX.md) for complete documentation
- Component-specific docs remain in component directories
