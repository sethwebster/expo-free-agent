# Elixir Controller Documentation Index

Complete documentation for Expo Free Agent Elixir controller migration.

---

## Quick Links

**New to the project?** Start here:
1. [README.md](./README.md) - Quick start and overview
2. [MIGRATION.md](./MIGRATION.md) - Migration rationale and strategy
3. [DEVELOPMENT.md](./DEVELOPMENT.md) - Local development setup

**Need to deploy?** Go here:
1. [DEPLOYMENT.md](./DEPLOYMENT.md) - Production deployment guide
2. [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Common issues and solutions

**Want to understand the system?** Read these:
1. [ARCHITECTURE.md](./ARCHITECTURE.md) - Deep dive into OTP design
2. [API_COMPATIBILITY.md](./API_COMPATIBILITY.md) - Complete API reference
3. [TESTING.md](./TESTING.md) - Testing strategy and requirements

---

## Documentation Files

### [README.md](./README.md)
**Main entry point** - Quick start, key features, basic operations

**Contents**:
- Why Elixir? (benefits over TypeScript)
- Quick start guide
- API endpoint reference
- Testing examples
- Configuration
- Development workflow
- Architecture highlights

**Use when**: First time setup, general reference

---

### [MIGRATION.md](./MIGRATION.md)
**Migration strategy** - Why migrate, what changed, deployment plan

**Contents**:
- Technology stack comparison
- Architecture changes
- Path parity guarantees
- Deployment strategy (blue-green)
- Testing requirements
- Rollback plan
- Success metrics

**Use when**: Planning migration, understanding rationale, executing cutover

---

### [API_COMPATIBILITY.md](./API_COMPATIBILITY.md)
**API reference** - Complete endpoint mapping, request/response formats

**Contents**:
- Complete endpoint mapping (TypeScript → Elixir)
- Request/response examples
- Authentication details
- Breaking changes summary
- Migration checklist for CLI/worker

**Use when**: Updating clients, debugging API issues, ensuring compatibility

---

### [DEVELOPMENT.md](./DEVELOPMENT.md)
**Developer guide** - Local setup, testing, debugging

**Contents**:
- Prerequisites and installation
- Environment configuration
- Running tests
- Database operations
- Debugging techniques (IEx, breakpoints, logging)
- Code formatting and linting
- Common development tasks

**Use when**: Setting up local environment, running tests, debugging code

---

### [ARCHITECTURE.md](./ARCHITECTURE.md)
**System design** - OTP supervision, GenServers, concurrency model

**Contents**:
- OTP supervision tree
- GenServer processes (QueueManager, HeartbeatMonitor)
- Database transaction boundaries
- File storage architecture
- Race condition prevention
- Concurrency model
- Fault tolerance
- Security architecture
- Observability

**Use when**: Understanding system design, debugging complex issues, adding features

---

### [TESTING.md](./TESTING.md)
**Testing guide** - Unit tests, integration tests, concurrency tests

**Contents**:
- Test categories (unit, integration, concurrency, load)
- Running tests
- Test helpers and fixtures
- Concurrency test examples
- Load testing
- Property-based testing
- CI/CD integration
- Performance benchmarks

**Use when**: Writing tests, debugging test failures, validating behavior

---

### [DEPLOYMENT.md](./DEPLOYMENT.md)
**Production deployment** - Environment setup, monitoring, backups

**Contents**:
- System requirements
- Environment variables
- Database setup
- Building releases
- Systemd service configuration
- Nginx reverse proxy
- Health check endpoint
- Monitoring and observability
- Backup and disaster recovery
- Blue-green deployment
- Performance tuning

**Use when**: Deploying to production, configuring infrastructure, setting up monitoring

---

### [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
**Problem solving** - Common errors, debugging techniques, solutions

**Contents**:
- Quick diagnosis commands
- Common errors (15+ scenarios)
- Debugging techniques (IEx, remote console, logging)
- Performance issues
- Database troubleshooting
- Log collection
- Bug report template

**Use when**: Encountering errors, debugging production issues, performance problems

---

## Documentation Map by Task

### Setting Up Locally

1. [README.md](./README.md#quick-start) - Quick start
2. [DEVELOPMENT.md](./DEVELOPMENT.md#initial-setup) - Detailed setup
3. [TROUBLESHOOTING.md](./TROUBLESHOOTING.md#common-errors) - If issues occur

### Understanding the System

1. [README.md](./README.md#key-features) - High-level overview
2. [ARCHITECTURE.md](./ARCHITECTURE.md) - Deep dive
3. [MIGRATION.md](./MIGRATION.md#what-changed) - Changes from TypeScript

### Writing Tests

1. [TESTING.md](./TESTING.md) - Complete testing guide
2. [DEVELOPMENT.md](./DEVELOPMENT.md#running-tests) - Running tests locally
3. [README.md](./README.md#testing) - Quick reference

### Deploying to Production

1. [DEPLOYMENT.md](./DEPLOYMENT.md) - Full deployment guide
2. [MIGRATION.md](./MIGRATION.md#deployment-strategy) - Migration strategy
3. [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Common deployment issues

### Updating Clients (CLI/Worker)

1. [API_COMPATIBILITY.md](./API_COMPATIBILITY.md) - API changes
2. [MIGRATION.md](./MIGRATION.md#path-parity-guarantees) - Path compatibility
3. [README.md](./README.md#api-endpoints) - Quick API reference

### Debugging Issues

1. [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Common errors and solutions
2. [DEVELOPMENT.md](./DEVELOPMENT.md#debugging) - Debugging techniques
3. [ARCHITECTURE.md](./ARCHITECTURE.md) - System internals

---

## File Summary

| File | Size | Purpose | Audience |
|------|------|---------|----------|
| README.md | ~15KB | Quick start, overview | All developers |
| MIGRATION.md | ~10KB | Migration strategy | DevOps, tech leads |
| API_COMPATIBILITY.md | ~12KB | API reference | Client developers |
| DEVELOPMENT.md | ~18KB | Local development | Contributors |
| ARCHITECTURE.md | ~25KB | System design | Senior engineers |
| TESTING.md | ~22KB | Testing guide | QA, developers |
| DEPLOYMENT.md | ~20KB | Production deployment | DevOps, SRE |
| TROUBLESHOOTING.md | ~20KB | Problem solving | All developers |

**Total documentation**: ~140KB, ~3500 lines

---

## External Resources

### Elixir/Phoenix
- [Elixir Getting Started](https://elixir-lang.org/getting-started/introduction.html)
- [Phoenix Guides](https://hexdocs.pm/phoenix/overview.html)
- [Ecto Documentation](https://hexdocs.pm/ecto/)
- [ExUnit Testing](https://hexdocs.pm/ex_unit/)

### PostgreSQL
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Performance Tuning](https://wiki.postgresql.org/wiki/Performance_Optimization)

### OTP
- [OTP Design Principles](https://www.erlang.org/doc/design_principles/users_guide.html)
- [GenServer Guide](https://hexdocs.pm/elixir/GenServer.html)
- [Supervisor Guide](https://hexdocs.pm/elixir/Supervisor.html)

---

## Contributing to Documentation

### Guidelines

- Keep examples runnable
- Include expected output
- Use code blocks with language tags
- Link between related docs
- Update index when adding new sections

### Style

- Use present tense
- Active voice preferred
- Short paragraphs (3-5 lines)
- Bullet points for lists
- Code examples for concepts
- Tables for comparisons

### Maintenance

**When updating docs**:
- Update version numbers
- Test all code examples
- Check internal links
- Update this index if structure changes
- Update README if quick start changes

---

## Quick Reference

### Common Commands

```bash
# Start server
mix phx.server

# Run tests
mix test

# Create migration
mix ecto.gen.migration name

# Format code
mix format

# Build release
MIX_ENV=prod mix release

# Remote console (production)
/opt/expo-controller/bin/expo_controller remote
```

### Common Endpoints

```bash
# Health check
curl http://localhost:4000/health

# Stats
curl http://localhost:4000/api/stats

# List builds
curl -H "X-API-Key: KEY" http://localhost:4000/api/builds

# Worker poll
curl -H "X-Worker-Id: ID" http://localhost:4000/api/workers/poll
```

### Common Errors

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for:
- Port already in use
- Database connection failed
- Migration errors
- API authentication fails
- GenServer timeout
- File upload fails

---

## Documentation Version

**Last Updated**: 2026-01-28
**Elixir Controller Version**: 0.1.0
**Migration Status**: Phase 1 complete (Core implementation)

---

## Feedback

Found an issue in the documentation?
- Check if still accurate
- File GitHub issue
- Include doc file name and section
- Suggest correction
