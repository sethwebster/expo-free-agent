# Contributing to Expo Free Agent

Thanks for your interest in contributing to Expo Free Agent!

## Getting Started

See the [5-Minute Start Guide](./docs/getting-started/5-minute-start.md) to get the project running locally.

## Development Guidelines

**Read first:** [AGENTS.md](./AGENTS.md) contains mandatory development rules and guardrails.

Key principles:
- Less code is better than more code
- Production-quality from day 1
- Security by design (no regressions on Gatekeeper/notarization)
- Version synchronization enforced by pre-commit hook

## Project Structure

This monorepo uses an **unconventional structure** by design:

```
expo-free-agent/
├── free-agent/      # Swift app (Swift Package Manager)
└── packages/        # JS/TS/Elixir (Bun workspace)
    ├── controller-elixir/
    ├── cli/
    ├── landing-page/
    └── worker-installer/
```

**Why?** Swift Package Manager and Bun workspaces conflict. Keeping them separate prevents build tool cross-contamination.

**When adding code:**
- Swift/native macOS → `free-agent/`
- JavaScript/TypeScript → `packages/`
- Elixir → `packages/controller-elixir/`

**Read:** [ADR-001](./adr/adr-001-monorepo-structure.md) for full rationale.

## Making Changes

### Architecture Decisions

All significant architectural decisions require an ADR:

1. Copy `adr/template.md` to `adr/adr-NNN-title.md`
2. Fill in all sections with rationale
3. Get review approval
4. Update `adr/README.md` index
5. Mark status as "Accepted"

See [AGENTS.md → Architecture Decision Records](./AGENTS.md#architecture-decision-records-adrs) for full guidelines.

### Testing Requirements

**CRITICAL:** All fixes and features require breaking tests first, then code.

**Workflow:**
1. Write failing test that demonstrates the bug/feature
2. Verify test fails for the right reason
3. Implement minimum code to make test pass
4. Refactor if needed (test still passing)

**Run tests:**
```bash
# Quick smoketest (30 seconds)
./smoketest.sh

# Full end-to-end test (5 minutes)
./test-e2e.sh

# All test suites
bun run test:all
```

All PRs must pass `bun run test:all`.

### Version Synchronization

All components share the same version number (enforced by pre-commit hook).

**Update version:**
```bash
# Automatic - updates all package.json files
./scripts/update-version.sh 0.1.24
```

### Git Workflow

**Commit messages:**
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `perf`: Performance improvement
- `refactor`: Code restructuring
- `test`: Test additions/changes
- `docs`: Documentation only
- `chore`: Build, CI, dependencies

**Rules:**
- Subject: ≤50 chars, imperative mood, no period
- Body: Wrap at 72 chars, explain why not what
- Reference issues and ADRs in footer

**Example:**
```
feat(worker): add VM snapshot support

Add ability to snapshot VM state between builds for faster startup.
Uses Apple Virtualization Framework's save/restore API.

Refs #123
Implements ADR-042
```

### Pull Requests

**Required:**
- ≥1 approval
- CI passing
- No merge conflicts
- Branch up to date with target
- Description explains changes
- Links to issue/ticket
- Links to ADR if architectural change

## Running Components

### Controller
```bash
# Start controller (development)
bun controller

# With auto-reload
bun controller:dev

# Custom port
bun controller -- --port 8080
```

### Worker
```bash
# Install worker app
npx @sethwebster/expo-free-agent-worker

# Launch (menu bar app)
open /Applications/FreeAgent.app
```

### CLI
```bash
# Submit build
expo-build submit --platform ios

# Check status
expo-build status build-abc123
```

## Documentation

All documentation in `docs/`:
- **Update docs** for any user-facing changes
- **Screenshots** for UI changes
- **Diagrams** for architectural changes

See [Documentation Index](./docs/INDEX.md).

## Security

**Never commit:**
- API keys or secrets
- Signing certificates
- `.env` files with credentials
- Personal access tokens

**Security-sensitive changes require:**
- Thorough testing
- Security review
- Documentation of threat model

## Questions?

- **Documentation:** [docs/INDEX.md](./docs/INDEX.md)
- **Issues:** [GitHub Issues](https://github.com/expo/expo-free-agent/issues)
- **Discussions:** [GitHub Discussions](https://github.com/expo/expo-free-agent/discussions)

---

**Made with ☕️ by engineers who wanted control over their build infrastructure.**
