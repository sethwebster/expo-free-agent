# Expo Free Agent — Agent Rules & Repo Guardrails

This repository is a **distributed build mesh for Expo apps**:

- **Controller** (`packages/controller`): Bun + Express + SQLite + local filesystem storage + small Web UI
- **Worker app** (`free-agent`): macOS Swift menu bar app that executes builds in macOS VMs
- **Worker installer** (`packages/worker-installer`): TypeScript CLI that downloads/verifies/installs `FreeAgent.app`
- **Submit CLI** (`cli`): TypeScript CLI for submitting builds and downloading artifacts
- **Landing page** (`packages/landing-page`): Vite + React + Tailwind v4 marketing site

This document defines **mandatory** rules for automated agents changing code/docs in this repo.

---

## Required reading (before meaningful changes)

- `README.md` (repo overview + key scripts)
- `docs/INDEX.md` (documentation navigation)
- `docs/architecture/architecture.md` (system design + prototype constraints)
- `docs/testing/testing.md` (how tests are structured/run)
- `docs/getting-started/setup-local.md` / `docs/getting-started/setup-remote.md` (how people actually run this)
- `docs/operations/gatekeeper.md` (macOS distribution constraints; do not regress)
- `docs/operations/release.md` (FreeAgent.app release process)

If a change touches a component, also skim that component's README:
- `packages/controller/README.md`
- `packages/worker-installer/README.md`
- `packages/cli/README.md`
- `free-agent/README.md`

---

## Core Principles

### 1. Explicit Over Implicit
- Every decision must have a clear rationale
- No magic values or hidden assumptions
- State changes must be traceable
- Dependencies must be declared upfront

### 2. Fail Fast, Fail Loud
- Validate inputs at boundaries
- No silent failures or degraded modes
- Throw errors immediately when invariants break
- Never catch exceptions just to log them

### 3. Optimize for Deletion
- Code that doesn't exist can't break
- Delete > Comment out > Keep
- Prefer inline over abstraction until third use
- Remove dead code immediately

### 4. Trust Nothing, Verify Everything
- User input is hostile until proven otherwise
- External APIs will fail in unexpected ways
- Database constraints are your last line of defense
- Type systems prevent bugs, runtime checks prevent disasters

---

## Documentation structure and navigation

### Documentation organization

All repository documentation is organized under `docs/` with this structure:

```
docs/
├── INDEX.md              # START HERE - central documentation index
├── README.md            # Quick navigation guide
├── getting-started/     # Setup, quickstart guides
├── architecture/        # System design, decisions, agent rules
├── adr/                 # Architecture Decision Records (numbered)
├── operations/          # Deployment, release, operational procedures
├── testing/            # Test strategies, procedures
└── historical/         # Archived docs, old plans
```

Component-specific docs remain in component directories:
- `packages/controller/` - Controller implementation docs
- `packages/cli/` - CLI implementation docs
- `free-agent/` - Worker app docs
- `packages/worker-installer/` - Installer docs
- `packages/landing-page/` - Landing page docs

### When updating documentation

**For new docs:**
- Place in appropriate `docs/` subdirectory (getting-started, architecture, operations, testing, or adr)
- Add entry to `docs/INDEX.md` in relevant section
- Use lowercase-with-hyphens naming (e.g., `setup-guide.md`)
- For ADRs: use numbered naming (e.g., `0001-use-sqlite-for-storage.md`)

**For doc updates:**
- Update cross-references to use relative paths from `docs/` structure
- Component docs: `../../component/file.md`
- Other docs sections: `../section/file.md`
- Never use absolute paths or root-relative paths

**For code reviews:**
- Write to `plans/code-review-<description>.md` (not under `docs/historical/`)
- Active plans stay in repo root `plans/` directory
- Only move to `docs/historical/plans/` when archived

**Breaking old doc references:**
- If removing/moving docs, update all internal references
- Check component READMEs for cross-references
- Update `CLAUDE.md` symlink target if needed

### Common doc reference patterns

From component docs to central docs:
```markdown
See [Architecture](../../docs/architecture/architecture.md) for system design.
See [Setup Guide](../../docs/getting-started/setup-local.md) for local development.
```

From central docs to component docs:
```markdown
See [Controller README](../../packages/controller/README.md) for API details.
See [CLI Implementation](../../cli/README.md) for command reference.
```

Within docs/ subdirectories:
```markdown
See [Testing Guide](../testing/testing.md) for test strategies.
See [Release Process](../operations/release.md) for deployment.
```

### Architecture Decision Records (ADRs)

**REQUIRED**: All significant architectural decisions MUST be documented in `docs/adr/`.

**When to create an ADR:**

Create an ADR when making architectural decisions that:
- Change system boundaries or component responsibilities
- Introduce new technologies, frameworks, or dependencies
- Alter data models, API contracts, or storage patterns
- Impact security, performance, or scalability
- Solve non-trivial problems with multiple viable approaches
- Establish patterns that other code should follow

**Do NOT create ADRs for:**
- Bug fixes or refactoring existing patterns
- Documentation improvements
- Test additions
- Minor UI tweaks

**Structure:**

ADRs live in `docs/adr/` and follow this naming: `NNNN-title-with-hyphens.md`

```markdown
# ADR-NNNN: Title

**Status**: Proposed | Accepted | Deprecated | Superseded by ADR-XXX
**Date**: YYYY-MM-DD
**Deciders**: @username, @agent-name
**Consulted**: @username, @agent-name

## Context
What is the issue/problem we're facing? What constraints exist?

## Decision Drivers
- Performance requirements
- Security concerns
- Developer experience
- Operational complexity
- Cost implications

## Considered Options
1. **Option A**: Description
   - Pros: ...
   - Cons: ...
2. **Option B**: Description
   - Pros: ...
   - Cons: ...

## Decision
We chose Option A because [rationale].

## Consequences
### Positive
- Benefit 1
- Benefit 2

### Negative
- Trade-off 1
- Trade-off 2

### Neutral
- Change 1

## Implementation
- File/module changes required
- Migration steps if needed
- Rollback procedure

## Validation
How we'll verify this decision was correct:
- Metrics to track
- Success criteria

## References
- [Related ADR-XXX](./adr-xxx-title.md)
- [External documentation](https://...)
- [GitHub issue #123](https://...)
```

**Numbering:**
- Use next sequential number (0001, 0002, etc.)
- Never reuse numbers
- Add entry to `docs/INDEX.md` under "Architecture Decision Records"

**ADR Workflow for Agents**

**CRITICAL REQUIREMENT**: AI agents making architectural decisions MUST:

1. **Document Decision Rationale**
   - Create ADR in `docs/adr/` before implementation
   - Number sequentially: `0001-title.md`, `0002-title.md`, etc.
   - Use kebab-case for titles
   - Include detailed comparison of alternatives
   - Explain why rejected options weren't chosen

2. **Get Code Review Sign-off**
   - After creating ADR, use Task tool with `subagent_type='neckbeard-code-reviewer'`
   - Provide detailed description: "Review ADR-XXX for [architectural decision]. Focus on: [specific concerns like security, performance, maintainability]."
   - Address all feedback before proceeding
   - Update ADR based on review comments
   - Mark ADR as "Accepted" only after reviewer approval

3. **Link to Implementation**
   - Reference ADR in commit messages: "Implements ADR-042: GraphQL API"
   - Link ADR in PR description
   - Update ADR if implementation reveals new information

**Review Checklist**

Before accepting ADR:
- [ ] Clear problem statement
- [ ] ≥2 alternatives considered
- [ ] Explicit trade-offs documented
- [ ] Implementation steps defined
- [ ] Success metrics identified
- [ ] Code reviewer approved
- [ ] Links to related ADRs/issues

**Examples of ADR-worthy decisions:**
- "ADR-0001: Use SQLite + filesystem instead of S3 for prototype"
- "ADR-0002: Worker uses native tar extraction for code signing preservation"
- "ADR-0003: Controller auth via API key header instead of JWT"

---

## Golden rules (non-negotiable)

### Use Bun, keep lockfiles clean

- **Package manager/runtime**: use **Bun** (`bun install`, `bun test`, `bun run …`).
- **Do not** introduce or update `package-lock.json`, `yarn.lock`, or `pnpm-lock.yaml`.
- **Do not** suggest commands that contradict repo scripts unless you also update docs/scripts accordingly.

### Version synchronization is enforced by pre-commit

All versions must stay synchronized across:

- `package.json` (root)
- `packages/cli/package.json`
- `packages/controller/package.json`
- `packages/landing-page/package.json`
- `packages/worker-installer/package.json`
- `packages/cli/src/index.ts` (Commander `.version("…")`)
- `packages/worker-installer/src/download.ts` (`const VERSION = "…"` constant)

Checks:

- **Local**: `bun run test:versions`
- **Git hook**: `.githooks/pre-commit` runs the same check

If you bump a version, you must update **all** of the above in one change.

### macOS Gatekeeper / notarization safety (do not regress)

The worker installer must preserve the app bundle's code signature and Gatekeeper validation.

Hard rules:

- **Do not** use the npm `tar` package to extract `FreeAgent.app.tar.gz`.
  - It can create AppleDouble (`._*`) files and **break signatures**.
  - Use native `tar` (`packages/worker-installer/src/download.ts`).
- **Do not** copy `.app` bundles with generic Node filesystem copying.
  - Use `ditto` for installation (`packages/worker-installer/src/install.ts`).
- **Do not** remove or "fix" quarantine attributes on notarized apps.
  - Do **not** add `xattr -cr`, `xattr -d com.apple.quarantine`, `spctl --add`, `lsregister …` to "fix" installs.

Expected verification commands (for debugging only; don't bake risky hacks into code):

- `codesign --verify --deep --strict /Applications/FreeAgent.app`
- `spctl --assess --type execute --verbose /Applications/FreeAgent.app`
- `find /Applications/FreeAgent.app -name "._*"` (should be empty)

### Secrets & credentials never go in git

Never commit:

- API keys (`CONTROLLER_API_KEY`, `EXPO_CONTROLLER_API_KEY`)
- Apple credentials (Apple ID, app-specific passwords)
- certificates / `.p12` / provisioning profiles
- controller databases / storage artifacts

Preferred patterns:

- Read secrets from env vars (documented in `SETUP_LOCAL.md`, `SETUP_REMOTE.md`, `RELEASE.md`)
- For CLI passwords: use env var (e.g. `EXPO_APPLE_PASSWORD`) or hidden interactive prompt (never CLI args)

---

## Code Quality Standards

### Complexity Budget
- Functions: ≤50 lines (hard limit: 100)
- Files: ≤500 lines (hard limit: 1000)
- Cyclomatic complexity: ≤10 per function
- Nesting depth: ≤3 levels
- Function parameters: ≤4 (use objects for more)

### Zero Tolerance
- ❌ `any` types (use `unknown` + type guards)
- ❌ Non-null assertions (`!`) without comments
- ❌ Empty catch blocks
- ❌ Disabled linter rules without issue links
- ❌ TODO comments without owner + date
- ❌ Console.log in production code
- ❌ Commented-out code
- ❌ Magic numbers (use named constants)

### Required Patterns
- ✅ Discriminated unions for state machines
- ✅ Exhaustive switch statements (never default case for enums)
- ✅ Early returns for guard clauses
- ✅ Immutable data structures (no mutations)
- ✅ Pure functions wherever possible
- ✅ Dependency injection over singletons

---

## Architecture

### Layered Architecture
```
┌─────────────────────────────────────┐
│  Presentation (UI Components)       │
│  - No business logic                │
│  - Props in, events out             │
└─────────────────────────────────────┘
           ↓
┌─────────────────────────────────────┐
│  Application (Hooks/Controllers)    │
│  - Orchestration only               │
│  - State management                 │
└─────────────────────────────────────┘
           ↓
┌─────────────────────────────────────┐
│  Domain (Business Logic)            │
│  - Framework-agnostic               │
│  - Pure functions                   │
│  - Core algorithms                  │
└─────────────────────────────────────┘
           ↓
┌─────────────────────────────────────┐
│  Infrastructure (DB/API/Cache)      │
│  - External dependencies            │
│  - I/O operations                   │
└─────────────────────────────────────┘
```

### Module Boundaries
Each module must:
- Have a single public entry point (`index.ts`)
- Export types explicitly
- Hide implementation details
- Never import from sibling modules' internals
- Document public API with TSDoc

### Dependency Rules
1. Higher layers depend on lower layers only
2. Domain layer has zero external dependencies
3. Infrastructure implements domain interfaces
4. Circular dependencies = architectural failure

---

## React Best Practices

### Component Hierarchy
```typescript
// ❌ WRONG - Business logic in component
function UserProfile() {
  const [user, setUser] = useState(null)

  useEffect(() => {
    fetch('/api/user')
      .then(r => r.json())
      .then(setUser)
  }, [])

  return <div>{user?.name}</div>
}

// ✅ CORRECT - Logic in custom hook
function useUser() {
  const [user, setUser] = useState(null)

  useEffect(() => {
    fetch('/api/user')
      .then(r => r.json())
      .then(setUser)
  }, [])

  return user
}

function UserProfile() {
  const user = useUser()
  return <div>{user?.name}</div>
}
```

### Hook Guidelines
- Never call `useEffect` directly in components
- One hook per concern (don't combine unrelated logic)
- Hooks must be pure (no side effects except in useEffect)
- Always specify exhaustive dependencies
- Extract complex effects to custom hooks

### Performance Rules
- Memo only after profiling shows need
- Don't optimize prematurely
- `useCallback` for props passed to memoized components
- `useMemo` for expensive computations only
- Virtual scrolling for lists >100 items

---

## TypeScript Standards

### Type Safety
```typescript
// ❌ WRONG - Weak types
interface User {
  id: string
  role: string
  status: string
}

// ✅ CORRECT - Strong types
interface User {
  id: UserId  // Branded type
  role: 'admin' | 'user' | 'guest'
  status: UserStatus  // Enum or union
}

type UserId = string & { readonly __brand: 'UserId' }
```

### Branded Types
Use for:
- IDs (UserId, PostId, etc.)
- Validated strings (Email, URL)
- Units (Milliseconds, Pixels)
- Sanitized input (SafeHTML)

### Error Handling
```typescript
// ❌ WRONG - Throwing strings
throw 'Something went wrong'

// ❌ WRONG - Generic errors
throw new Error('Failed')

// ✅ CORRECT - Typed errors
class ValidationError extends Error {
  constructor(
    public field: string,
    public constraint: string
  ) {
    super(`${field} failed ${constraint}`)
    this.name = 'ValidationError'
  }
}

// ✅ BEST - Result type
type Result<T, E = Error> =
  | { ok: true; value: T }
  | { ok: false; error: E }
```

---

## Testing Requirements

### Test-First Development (Non-Negotiable)

**CRITICAL**: All fixes and features REQUIRE breaking tests first, then code.

**Workflow**:
1. Write failing test that demonstrates the bug or specifies the feature
2. Verify test fails for the right reason
3. Implement minimum code to make test pass
4. Refactor if needed (test still passing)
5. No code without failing test first

**Rationale**:
- Tests are the specification
- Proves test actually catches the bug
- Prevents "test passes because it doesn't test anything"
- Forces clarity on requirements before implementation
- Prevents scope creep

```typescript
// ✅ CORRECT workflow
// 1. Write test (fails)
it('should reject invalid email', () => {
  expect(() => validateEmail('not-an-email')).toThrow()
})

// 2. Run test → RED
// 3. Implement
function validateEmail(email: string) {
  if (!email.includes('@')) throw new Error('Invalid')
}

// 4. Run test → GREEN
```

### Coverage Targets
- Unit tests: ≥80% line coverage
- Integration tests: All critical paths
- E2E tests: Primary user flows
- No mocking in E2E tests

### Test Structure
```typescript
// ✅ CORRECT - AAA pattern
describe('UserService', () => {
  describe('createUser', () => {
    it('should create user with valid data', async () => {
      // Arrange
      const input = { email: 'test@example.com' }
      const mockDb = createMockDb()
      const service = new UserService(mockDb)

      // Act
      const result = await service.createUser(input)

      // Assert
      expect(result.ok).toBe(true)
      expect(mockDb.insert).toHaveBeenCalledWith(
        expect.objectContaining({ email: input.email })
      )
    })

    it('should reject invalid email', async () => {
      // Arrange
      const input = { email: 'invalid' }
      const service = new UserService(mockDb())

      // Act
      const result = await service.createUser(input)

      // Assert
      expect(result.ok).toBe(false)
      expect(result.error).toBeInstanceOf(ValidationError)
    })
  })
})
```

### Test Naming
- Use `should` statements
- Be specific about conditions
- One assertion per test (prefer multiple tests)
- Tests are documentation (name explains behavior)

### What to Test
✅ Test:
- Business logic (pure functions)
- Integration points
- Error conditions
- Edge cases (null, empty, boundary values)
- State transitions

❌ Don't test:
- Framework internals
- Third-party libraries
- Getters/setters
- Private methods directly

### Repo-level Testing Commands

Repo-level:

- `bun run test:all` (unit/integration + e2e script)
- `./smoketest.sh` (fast sanity)
- `./test-e2e.sh` (full flow with mock worker)

Targeted:

- Controller: `bun run test:controller`
- CLI: `bun run test:cli`
- Version sync: `bun run test:versions`

If you change an API contract, update tests to lock the behavior in.

---

## Component-specific rules

### Controller (`packages/controller`)

- **Auth**: keep API key validation behavior consistent (health endpoints may be unauthenticated; API endpoints require key).
- **Storage**: preserve storage layout and path-safety invariants.
- **Backwards compatibility**: avoid breaking API shapes used by the CLI and mock worker unless you update both + tests.
- **Performance**: prefer streaming and bounded memory use for uploads/downloads.

Run:

- `bun controller` (from repo root)
- `bun controller:dev` (auto-reload)

### Submit CLI (`cli`)

- **Never** accept Apple passwords via CLI args (shell history leak). Keep env var/prompt behavior.
- **Keep path traversal protections** for downloads (output must remain within the working directory).
- **Keep timeouts/retries/backoff** conservative and documented (don't accidentally DDOS the controller).

### Worker installer (`packages/worker-installer`)

- Treat `docs/operations/gatekeeper.md` as the source of truth for install/extract/copy behavior.
- Prefer native macOS tools when interacting with `.app` bundles.
- Log securely: **never** print API keys; redact aggressively.

### Worker app (`free-agent`)

- Treat `free-agent/release.sh` + `docs/operations/release.md` as canonical for building/signing/notarizing.
- Avoid changes that require sandbox entitlements unless you also update signing/notarization and docs.
- When changing the worker-controller protocol, update the controller endpoints and the mock worker/tests.

### Landing page (`packages/landing-page`)

- Keep it fast: avoid heavy runtime dependencies and large client bundles.
- Prefer accessible, responsive UI and simple build/deploy (Cloudflare Pages is documented in `README.md`).

---

## Database Best Practices

### Migration Strategy
```typescript
// ❌ WRONG - Destructive migration
await db.schema.dropTable('users')
await db.schema.createTable('users', ...)

// ✅ CORRECT - Additive migration
await db.schema.createTable('users_v2', ...)
// Deploy code that reads from users_v2
// Backfill data
// Switch reads to users_v2
// Drop users (separate migration)
```

### Query Patterns
```typescript
// ❌ WRONG - N+1 queries
const users = await db.select().from(users)
for (const user of users) {
  user.posts = await db.select().from(posts).where(eq(posts.userId, user.id))
}

// ✅ CORRECT - Eager loading
const users = await db
  .select()
  .from(users)
  .leftJoin(posts, eq(posts.userId, users.id))
```

### Constraints
Every table must have:
- Primary key
- Created/updated timestamps
- NOT NULL on required fields
- Foreign keys with explicit ON DELETE behavior
- Unique constraints for natural keys
- Check constraints for invariants

---

## API Design

### RESTful Endpoints
```
POST   /users              - Create
GET    /users/:id          - Read one
GET    /users              - Read many
PATCH  /users/:id          - Partial update
PUT    /users/:id          - Full replacement
DELETE /users/:id          - Delete
```

### Response Format
```typescript
// ✅ Success
{
  "data": { ... },
  "meta": {
    "requestId": "uuid",
    "timestamp": "ISO8601"
  }
}

// ✅ Error
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Human readable message",
    "details": [
      { "field": "email", "issue": "invalid_format" }
    ]
  },
  "meta": {
    "requestId": "uuid",
    "timestamp": "ISO8601"
  }
}
```

### Status Codes
- 200: Success with body
- 201: Created (return created resource)
- 204: Success without body
- 400: Client error (validation)
- 401: Unauthenticated
- 403: Unauthorized (authenticated but forbidden)
- 404: Not found
- 409: Conflict (unique constraint, optimistic lock)
- 422: Unprocessable (semantic error)
- 429: Rate limited
- 500: Server error
- 503: Service unavailable (maintenance, overload)

---

## Security Requirements

### Input Validation
```typescript
// ✅ CORRECT - Validate at boundary
export async function createUser(req: Request) {
  const input = validateCreateUserInput(await req.json())
  // input is now trusted
  const user = await userService.create(input)
  return Response.json(user)
}

// Domain layer assumes valid input
class UserService {
  create(input: ValidatedCreateUserInput) {
    // No validation needed here
  }
}
```

### Authentication
- Never roll your own crypto
- Use established libraries (Auth.js, Lucia, etc.)
- Store only hashed passwords (bcrypt, Argon2)
- Session tokens: cryptographically random, ≥128 bits
- Expire sessions (30d max, 24h for sensitive)

### Authorization
```typescript
// ✅ CORRECT - Explicit permissions
function canDeletePost(user: User, post: Post): boolean {
  return user.id === post.authorId || user.role === 'admin'
}

// Check before action
if (!canDeletePost(user, post)) {
  throw new ForbiddenError('Cannot delete post')
}
await deletePost(post.id)
```

### Common Vulnerabilities
❌ Prevent:
- SQL injection (use parameterized queries)
- XSS (escape output, CSP headers)
- CSRF (SameSite cookies, CSRF tokens)
- Mass assignment (explicit allowlists)
- Timing attacks (constant-time comparison)
- Open redirects (validate redirect URLs)

---

## Performance

### Caching Strategy
```typescript
// ✅ CORRECT - Layered caching
async function getUser(id: UserId): Promise<User> {
  // L1: In-memory (fastest)
  const cached = memoryCache.get(id)
  if (cached) return cached

  // L2: Redis (fast)
  const redisData = await redis.get(`user:${id}`)
  if (redisData) {
    const user = JSON.parse(redisData)
    memoryCache.set(id, user)
    return user
  }

  // L3: Database (slow)
  const user = await db.query.users.findFirst({
    where: eq(users.id, id)
  })

  if (user) {
    await redis.setex(`user:${id}`, 300, JSON.stringify(user))
    memoryCache.set(id, user)
  }

  return user
}
```

### Cache Invalidation
```typescript
// ✅ CORRECT - Explicit invalidation
async function updateUser(id: UserId, data: UserUpdate) {
  const user = await db.update(users)
    .set(data)
    .where(eq(users.id, id))
    .returning()

  // Invalidate all cache layers
  memoryCache.delete(id)
  await redis.del(`user:${id}`)

  return user
}
```

### Database Indexes
Create indexes for:
- Foreign keys (always)
- WHERE clause columns (frequently queried)
- ORDER BY columns
- Covering indexes for hot queries

Avoid:
- Indexes on high-cardinality columns with low selectivity
- Too many indexes (slows writes)
- Redundant indexes (covered by composite)

---

## Common Pitfalls

### Race Conditions
```typescript
// ❌ WRONG - Race condition
const count = await getCount()
await setCount(count + 1)

// ✅ CORRECT - Atomic operation
await db.update(counter).set({
  value: sql`${counter.value} + 1`
})
```

### Memory Leaks
Watch for:
- Event listeners not cleaned up
- Intervals/timeouts not cleared
- Growing caches without eviction
- Circular references in closures

### N+1 Queries
```typescript
// ❌ WRONG
const posts = await db.select().from(posts)
for (const post of posts) {
  post.author = await db.query.users.findFirst({
    where: eq(users.id, post.authorId)
  })
}

// ✅ CORRECT
const posts = await db
  .select()
  .from(posts)
  .leftJoin(users, eq(users.id, posts.authorId))
```

### Unbounded Operations
```typescript
// ❌ WRONG - No limit
const users = await db.select().from(users)

// ✅ CORRECT - Pagination
const users = await db
  .select()
  .from(users)
  .limit(pageSize)
  .offset(page * pageSize)
```

---

## Git Workflow

### Commit Messages
```
<type>(<scope>): <subject>

<body>

<footer>
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `perf`: Performance improvement
- `refactor`: Code restructuring
- `test`: Test additions/changes
- `docs`: Documentation only
- `chore`: Build, CI, dependencies

Rules:
- Subject: ≤50 chars, imperative mood, no period
- Body: Wrap at 72 chars, explain why not what
- Reference issues and ADRs in footer (e.g., "Implements ADR-042", "Refs #123")

### Pull Requests
Required:
- ≥1 approval
- CI passing
- No merge conflicts
- Branch up to date with target
- Description explains changes
- Links to issue/ticket
- Links to ADR if architectural change
- ADR approved before PR if new architectural decision

---

## Release workflow (FreeAgent.app + npm packages)

Worker app artifact:

- Local build/sign/notarize package: `free-agent/release.sh` (see `docs/operations/release.md`)
- CI release: tag `vX.Y.Z` and push to trigger GitHub Actions release workflow

After releasing a new FreeAgent.app build:

- Update `packages/worker-installer/src/download.ts` if the download URL/version logic needs changes
- Keep version synchronization intact (see "Version synchronization" above)

---

## Agent behavior expectations

- Make changes **small and reviewable**; don't refactor unrelated code.
- Prefer **boring, testable** implementations over cleverness.
- When you introduce new behavior, also update the most relevant doc (`README.md`, `docs/INDEX.md`, or appropriate docs under `docs/`) if users will trip over it.

### Documentation updates with commits

**Before committing code changes:**
- Review what documentation might be affected (README, component docs, architecture docs)
- Check if new features/APIs need documentation
- Verify cross-references still work if files moved/renamed
- Update `docs/INDEX.md` if new docs added or structure changed

**Ask user before committing if:**
- Significant new functionality added (needs docs/examples)
- API contracts changed (ROUTES.md, component READMEs)
- Architecture decisions made (create ADR in `docs/adr/`)
- Security implications (security.md)
- Breaking changes (migration guides)

**Goal**: Keep documentation synchronized with code, not as an afterthought.

---

## Refactoring Checklist

Before refactoring:
- [ ] Tests exist and pass
- [ ] Understand current behavior completely
- [ ] Have clear improvement goal
- [ ] Know stopping condition

During refactoring:
- [ ] Keep tests passing at each step
- [ ] Commit frequently (atomic changes)
- [ ] No feature additions (refactor OR new feature, never both)
- [ ] Verify performance doesn't degrade

After refactoring:
- [ ] All tests still pass
- [ ] Code coverage maintained or improved
- [ ] Documentation updated
- [ ] No observable behavior change

---

## Review Guidelines

### What Reviewers Check
1. Correctness: Does it solve the problem?
2. Security: Any vulnerabilities?
3. Performance: Any red flags?
4. Maintainability: Will we understand this in 6 months?
5. Tests: Are critical paths covered?

### Review Etiquette
- Suggest, don't demand
- Explain why, not just what
- Approve if minor nits only
- Block for security, correctness, data loss
- Respond within 24h

### Self-Review Checklist
Before requesting review:
- [ ] Ran tests locally
- [ ] Manually tested feature
- [ ] Checked for console errors
- [ ] Reviewed own diff
- [ ] Removed debug code
- [ ] Updated documentation

---

## Conclusion

When in doubt:
1. Make it work
2. Make it right
3. Make it fast

In that order. Always.
