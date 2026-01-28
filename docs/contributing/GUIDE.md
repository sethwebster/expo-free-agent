# Contributing Guide

Welcome! We're excited you want to contribute to Expo Free Agent.

## Quick Start for Contributors

```bash
# 1. Fork and clone
git clone https://github.com/YOUR_USERNAME/expo-free-agent.git
cd expo-free-agent

# 2. Install dependencies
bun install

# 3. Run tests
bun test

# 4. Start controller
bun controller

# 5. Make changes, test, submit PR
```

---

## Before You Start

### Read These First

1. **[CLAUDE.md](../../CLAUDE.md)** - Mandatory agent rules and repo guardrails
2. **[Architecture](../architecture/architecture.md)** - System design overview
3. **[Testing](../testing/testing.md)** - How tests are structured

### Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and grow
- Follow the [Contributor Covenant](https://www.contributor-covenant.org/)

---

## Development Setup

### Prerequisites

- macOS 13.0+ or Linux
- Bun 1.0+
- Git
- (Optional) Xcode 15+ for iOS builds

### Initial Setup

```bash
# Clone repository
git clone https://github.com/expo/expo-free-agent.git
cd expo-free-agent

# Install dependencies
bun install

# Run smoketest
./smoketest.sh
```

### IDE Setup

**VS Code (Recommended):**

```json
{
  "editor.formatOnSave": true,
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": true
  },
  "typescript.tsdk": "node_modules/typescript/lib",
  "files.associations": {
    "*.ts": "typescript"
  }
}
```

**Extensions:**
- ESLint
- Prettier
- TypeScript and JavaScript Language Features

---

## Project Structure

```
expo-free-agent/
├── packages/
│   ├── controller/        # Central server
│   ├── worker-installer/  # Worker installation CLI
│   └── landing-page/      # Marketing site
├── cli/                   # Build submission CLI
├── free-agent/           # macOS worker app (Swift)
├── docs/                 # All documentation
├── test/                 # Test fixtures and utilities
└── scripts/              # Build and utility scripts
```

### Component Responsibilities

| Component | Language | Purpose |
|-----------|----------|---------|
| Controller | TypeScript/Bun | Coordinates builds, manages workers |
| CLI | TypeScript/Bun | Submits builds, downloads artifacts |
| Worker | Swift | Executes builds in VMs on macOS |
| Worker Installer | TypeScript | Installs worker app |
| Landing Page | React/Vite | Marketing site |

---

## Making Changes

### Branch Naming

```
feature/add-webhook-support
fix/database-locking-issue
docs/improve-api-reference
refactor/simplify-queue-logic
```

### Commit Messages

Follow conventional commits:

```
type(scope): subject

body (optional)

footer (optional)
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `test`: Test changes
- `chore`: Build/tooling changes

**Examples:**

```
feat(controller): add webhook support for build events

Implement webhook notifications for build lifecycle events.
Users can configure webhooks in the controller settings.

Closes #123
```

```
fix(worker): prevent VM memory leak

VMs were not being properly destroyed after build completion,
causing memory accumulation. Now explicitly calling cleanup.

Fixes #456
```

---

## Code Style

### TypeScript/JavaScript

```typescript
// Use TypeScript strict mode
interface BuildConfig {
  platform: 'ios' | 'android';
  timeout?: number;
}

// Prefer async/await over promises
async function submitBuild(config: BuildConfig): Promise<string> {
  const response = await fetch('/api/builds', {
    method: 'POST',
    body: JSON.stringify(config),
  });

  return response.json();
}

// Use descriptive names
const MAX_BUILD_TIMEOUT = 1800; // seconds
const DEFAULT_POLL_INTERVAL = 5000; // ms
```

### Swift

```swift
// Follow Swift API Design Guidelines
struct BuildConfiguration {
    let platform: Platform
    let timeout: TimeInterval?
}

// Use guard for early exits
func startBuild(_ config: BuildConfiguration) throws {
    guard let worker = availableWorker else {
        throw BuildError.noWorkerAvailable
    }

    // Continue with build
}

// Use meaningful variable names
let maximumConcurrentBuilds = 2
let defaultVMMemorySize = 8 * 1024 * 1024 * 1024 // 8 GB
```

---

## Testing

### Running Tests

```bash
# All tests
bun test

# Specific component
cd packages/controller && bun test
cd cli && bun test

# With coverage
bun test --coverage

# Watch mode
bun test --watch
```

### Writing Tests

**Controller tests:**

```typescript
import { describe, it, expect } from 'bun:test';
import { submitBuild } from './builds';

describe('Build Submission', () => {
  it('should create build record', async () => {
    const result = await submitBuild({
      platform: 'ios',
      source: Buffer.from('test'),
    });

    expect(result.buildId).toMatch(/^build-/);
    expect(result.status).toBe('pending');
  });

  it('should reject invalid platform', async () => {
    await expect(
      submitBuild({ platform: 'windows' as any })
    ).rejects.toThrow('Invalid platform');
  });
});
```

**CLI tests:**

```typescript
import { describe, it, expect } from 'bun:test';
import { parseArgs } from './cli';

describe('CLI Argument Parsing', () => {
  it('should parse build command', () => {
    const args = parseArgs(['build', '--platform', 'ios']);

    expect(args.command).toBe('build');
    expect(args.platform).toBe('ios');
  });
});
```

### Test Coverage Requirements

- New features: ≥80% coverage
- Bug fixes: Add test that reproduces bug
- Refactoring: Maintain existing coverage

---

## Pull Request Process

### 1. Create Feature Branch

```bash
git checkout -b feature/your-feature-name
```

### 2. Make Changes

```bash
# Make your changes
# ...

# Run tests
bun test

# Run linter
bun lint

# Format code
bun format
```

### 3. Commit Changes

```bash
git add .
git commit -m "feat(controller): add webhook support"
```

### 4. Push to Fork

```bash
git push origin feature/your-feature-name
```

### 5. Create Pull Request

**PR Title:** Same as commit message convention

```
feat(controller): add webhook support
```

**PR Description Template:**

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix (non-breaking change fixing an issue)
- [ ] New feature (non-breaking change adding functionality)
- [ ] Breaking change (fix or feature causing existing functionality to break)
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Tested locally
- [ ] Smoketest passes

## Documentation
- [ ] Updated docs/
- [ ] Updated README if needed
- [ ] Updated CHANGELOG if needed

## Checklist
- [ ] Code follows project style guide
- [ ] Self-review completed
- [ ] Comments added for complex code
- [ ] No warnings in console
- [ ] Related documentation updated

## Related Issues
Closes #123
Fixes #456
```

### 6. Review Process

- Automated CI checks must pass
- At least one approving review required
- Address review comments
- Squash commits before merge (if requested)

### 7. After Merge

```bash
# Update your local main
git checkout main
git pull upstream main

# Delete feature branch
git branch -d feature/your-feature-name
git push origin --delete feature/your-feature-name
```

---

## Common Tasks

### Add New API Endpoint

1. Add route in `packages/controller/src/routes/`
2. Add handler in `packages/controller/src/handlers/`
3. Add types in `packages/controller/src/types/`
4. Add tests in `packages/controller/tests/`
5. Update `docs/reference/api.md`

**Example:**

```typescript
// packages/controller/src/routes/webhooks.ts
import { Router } from 'express';
import { createWebhook } from '../handlers/webhooks';

const router = Router();

router.post('/webhooks', createWebhook);

export default router;
```

### Add New CLI Command

1. Add command in `cli/src/commands/`
2. Register in `cli/src/index.ts`
3. Add tests in `cli/tests/`
4. Update `cli/README.md`

**Example:**

```typescript
// cli/src/commands/list.ts
import { Command } from 'commander';

export const listCommand = new Command('list')
  .description('List all builds')
  .option('-s, --status <status>', 'Filter by status')
  .action(async (options) => {
    // Implementation
  });
```

### Add Worker Feature

1. Update Swift code in `free-agent/Sources/FreeAgent/`
2. Add tests in `free-agent/Tests/`
3. Update worker-controller protocol if needed
4. Test with `swift build && swift test`
5. Update `free-agent/README.md`

---

## Debugging

### Controller Debugging

```bash
# Enable debug logs
DEBUG=* bun controller

# Or specific namespaces
DEBUG=controller:builds,controller:workers bun controller

# Attach debugger (VS Code)
# Set breakpoints, press F5
```

### CLI Debugging

```bash
# Verbose output
expo-build submit --verbose

# Inspect API calls
DEBUG=api:* expo-build submit
```

### Worker Debugging

```swift
// Add debug prints
print("[DEBUG] Starting build: \(buildId)")

// View logs
// Worker → Menu Bar → View Logs

// Or console:
log stream --predicate 'process == "FreeAgent"' --level debug
```

---

## Architecture Decisions

### When to Use What

**Database (SQLite):**
- ✅ Build records, job queue, worker registry
- ❌ Large binary data (use filesystem)
- ❌ Real-time data (use in-memory)

**Filesystem:**
- ✅ Source code archives
- ✅ Build artifacts
- ❌ Temporary data (use /tmp)

**In-Memory:**
- ✅ Active job queue
- ✅ Worker heartbeat cache
- ❌ Persistent state

### Design Patterns

**Controller:**
- DDD (Domain-Driven Design)
- Repository pattern for data access
- Use cases for business logic
- Express middleware for cross-cutting concerns

**CLI:**
- Commander for argument parsing
- Inquirer for interactive prompts
- Progress bars for long operations
- Exit codes: 0 = success, 1 = error

**Worker:**
- MVVM where applicable
- Delegate pattern for callbacks
- Swift Concurrency (async/await)

---

## Performance Guidelines

### Database

```typescript
// ✅ Good: Use transactions for multiple writes
db.transaction(() => {
  db.run('INSERT INTO builds ...');
  db.run('INSERT INTO jobs ...');
});

// ❌ Bad: Individual writes
db.run('INSERT INTO builds ...');
db.run('INSERT INTO jobs ...');
```

### API

```typescript
// ✅ Good: Stream large files
app.get('/download/:id', (req, res) => {
  const stream = fs.createReadStream(filePath);
  stream.pipe(res);
});

// ❌ Bad: Load entire file
app.get('/download/:id', (req, res) => {
  const data = fs.readFileSync(filePath);
  res.send(data);
});
```

### Worker

```swift
// ✅ Good: Async file operations
Task {
    let data = try await FileHandle(forReadingFrom: url).readToEnd()
}

// ❌ Bad: Blocking operations on main thread
let data = try Data(contentsOf: url)
```

---

## Security Guidelines

### Never Commit

- API keys or secrets
- Private certificates
- Database files
- `.env` files with real credentials

### Always Validate

```typescript
// ✅ Good: Validate all inputs
function getBuild(buildId: string) {
  if (!/^build-[a-z0-9]+$/.test(buildId)) {
    throw new Error('Invalid build ID');
  }
  // ...
}

// ❌ Bad: Trust user input
function getBuild(buildId: string) {
  return db.get(`SELECT * FROM builds WHERE id = '${buildId}'`);
  // SQL injection vulnerability!
}
```

### Path Safety

```typescript
// ✅ Good: Use path.join and validate
import path from 'path';

function getFile(filename: string) {
  const safePath = path.normalize(filename).replace(/^(\.\.(\/|\\|$))+/, '');
  const fullPath = path.join(STORAGE_DIR, safePath);

  if (!fullPath.startsWith(STORAGE_DIR)) {
    throw new Error('Path traversal detected');
  }

  return fs.readFileSync(fullPath);
}
```

---

## Resources for Contributors

- [Documentation Index](../INDEX.md) - All documentation
- [Accessibility Guide](./accessibility.md) - Making docs accessible
- [Maintaining Documentation](./maintaining-docs.md) - Keeping docs up-to-date
- [Architecture Diagrams](../architecture/diagrams.md) - System architecture
- [Testing Guide](../testing/testing.md) - Test strategies
- [Documentation Verification Script](../../scripts/verify-docs.sh) - Automated checks

---

## Getting Help

### Resources

- **Documentation:** [docs/INDEX.md](../INDEX.md)
- **GitHub Discussions:** [discussions](https://github.com/expo/expo-free-agent/discussions)
- **GitHub Issues:** [issues](https://github.com/expo/expo-free-agent/issues)

### Ask Questions

- Use GitHub Discussions for general questions
- Use GitHub Issues for bugs and feature requests
- Tag maintainers only when necessary

### Pair Programming

- Available via Discord (future)
- Schedule via GitHub Discussions

---

## Recognition

Contributors are recognized in:
- GitHub contributors graph
- Release notes
- CONTRIBUTORS.md (for significant contributions)

---

Thank you for contributing to Expo Free Agent! 🚀

---

**Last Updated:** 2026-01-28
