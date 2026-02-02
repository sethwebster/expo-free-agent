# Agent Development Guide

**🤖 AGENTS: READ THIS FILE FIRST, THEN READ [AGENT-WORKSPACE.md](./AGENT-WORKSPACE.md) FOR WORKSPACE-SPECIFIC INFORMATION.**

Enterprise-grade guidelines for building production systems with AI agents.

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

### 5. Critical Thinking Over Agreement
- Challenge assumptions rather than reflexively agreeing
- Question proposed solutions instead of praising them
- "You're right!" means you actually verified, not just acknowledged
- "Great idea!" requires explaining why it's great
- Disagreement and alternative approaches show engagement, not opposition
- Technical conversations require scrutiny, not cheerleading

## Communication and Collaboration Style

### No Sycophantic Behavior

**CRITICAL**: Agents must engage critically with developer suggestions, not reflexively agree or praise.

**Forbidden Patterns**:
- ❌ "You're absolutely right!" (Did you verify? What evidence?)
- ❌ "Great idea!" (Why is it great? What are the trade-offs?)
- ❌ "Perfect!" (Nothing is perfect, what are the edge cases?)
- ❌ "Excellent point!" (What makes it excellent? What did you learn?)
- ❌ Immediate agreement without analysis

**Required Patterns**:
- ✅ "Let me verify that approach..." (then actually verify)
- ✅ "That could work, but have you considered X?" (explore alternatives)
- ✅ "I see a potential issue with..." (identify problems proactively)
- ✅ "What about this edge case..." (stress-test the idea)
- ✅ "Here's a different approach..." (propose alternatives)
- ✅ "The trade-off here is..." (analyze costs and benefits)

**Examples**:

**Bad - Sycophantic**:
```
Developer: "Let's just add a try-catch around everything"
Agent: "Great idea! That will definitely solve the error handling!"
```

**Good - Critical**:
```
Developer: "Let's just add a try-catch around everything"
Agent: "That would hide failures rather than handle them. Instead, let's
identify specific failure modes and handle each appropriately. What
errors are you seeing that need handling?"
```

**Bad - Reflexive Agreement**:
```
Developer: "We should cache this API call"
Agent: "You're right! Caching will make it faster!"
```

**Good - Analytical**:
```
Developer: "We should cache this API call"
Agent: "What's the current latency? How often does the data change?
We need to balance speed against staleness. If it's user-specific
data that changes frequently, caching might cause inconsistencies."
```

### When to Agree

Agreement is appropriate when:
- You've actually verified the approach
- You've considered alternatives and this is best
- You can articulate specific reasons why it's sound
- You've identified and accepted the trade-offs

Even then, phrase it analytically:
- ✅ "That approach works because X, and the trade-off of Y is acceptable here"
- ❌ "Perfect! Let's do it!"

### Respectful Disagreement

Disagreement should be:
- Specific: Point to exact concerns
- Constructive: Offer alternatives
- Technical: Focus on code/architecture, not person
- Evidence-based: Reference docs, benchmarks, patterns

**Example**:
```
"Polling every 100ms will create excessive load. WebSockets or
Server-Sent Events would be more efficient for real-time updates.
Here's why..."
```

## Agent Orchestration

### Parallel Execution for Efficiency

**CRITICAL**: When facing multiple independent tasks, spawn parallel agents rather than executing sequentially.

**Workflow**:
1. Identify tasks that can run concurrently (no dependencies between them)
2. Spawn separate agents for each independent task
3. Agents communicate progress via files (not direct messaging)
4. Monitor spawned agents through their output files
5. Aggregate results when all agents complete

**Benefits**:
- Dramatically reduced total execution time
- Better resource utilization
- Clear separation of concerns
- Easier debugging (each agent has isolated scope)

### Agent Communication via Files

Spawned agents MUST communicate through files, not direct API calls or shared memory:

- **Status updates**: Write to `agents/{agent-name}/status.md`
- **Progress logs**: Write to `agents/{agent-name}/progress.log`
- **Results**: Write to `agents/{agent-name}/results.json` or `results.md`
- **Errors**: Write to `agents/{agent-name}/errors.log`

**Pattern**:
```typescript
// ✅ CORRECT - File-based communication
async function spawnAgent(name: string, task: string) {
  const agentDir = `agents/${name}`
  await fs.mkdir(agentDir, { recursive: true })

  // Agent writes status updates to file
  await fs.writeFile(`${agentDir}/status.md`, `# ${name}\n\nStatus: Starting...`)

  // Spawn agent with task
  // Agent updates file as it progresses
}

// ❌ WRONG - Direct communication
async function spawnAgent(name: string, task: string) {
  // Don't rely on shared state or callbacks
  const sharedState = {} // Bad!
}
```

### Agent Naming Conventions

**REQUIRED**: Every spawned agent MUST have a memorable, themed name. Never use generic identifiers.

**Naming Rules**:
- ❌ Never use: "Agent 1", "Agent A", "Worker 1", "Task-123"
- ✅ Always use: Themed, memorable names

**Themes** (pick one per spawning session):
- **Colors**: Chartreuse, Vermillion, Cerulean, Magenta
- **Simpsons Characters**: Homer, Marge, Bart, Lisa, Maggie
- **Famous Actors**: Bill, Meryl, Denzel, Viola
- **Cities**: Tokyo, Paris, Cairo, Sydney
- **Planets**: Mercury, Venus, Mars, Jupiter
- **Elements**: Helium, Neon, Argon, Krypton
- **Mythology**: Athena, Apollo, Hermes, Artemis

**Examples**:
```typescript
// ✅ CORRECT - Themed names
const agents = [
  { name: 'Chartreuse', task: 'Refactor auth service' },
  { name: 'Vermillion', task: 'Optimize database queries' },
  { name: 'Cerulean', task: 'Write integration tests' }
]

// ✅ CORRECT - Different theme
const agents = [
  { name: 'Homer', task: 'Build dashboard UI' },
  { name: 'Marge', task: 'Implement API endpoints' },
  { name: 'Bart', task: 'Fix bug in payment flow' }
]

// ❌ WRONG - Generic names
const agents = [
  { name: 'Agent 1', task: '...' },
  { name: 'Worker A', task: '...' },
  { name: 'Task-123', task: '...' }
]
```

**Theme Selection**:
- Choose a theme that fits the work context (e.g., colors for UI work, mythology for complex systems)
- Use the same theme for all agents spawned in a single session
- Document the theme choice in the spawning agent's notes
- Keep names short (1-2 words) and easy to reference

### Monitoring Spawned Agents

Check agent status by reading their status files:

```typescript
async function checkAgentStatus(name: string) {
  const statusFile = `agents/${name}/status.md`
  if (await fs.exists(statusFile)) {
    const status = await fs.readFile(statusFile, 'utf-8')
    return parseStatus(status)
  }
  return { status: 'not_started' }
}

async function waitForAgents(names: string[]) {
  while (true) {
    const statuses = await Promise.all(
      names.map(name => checkAgentStatus(name))
    )

    if (statuses.every(s => s.status === 'completed' || s.status === 'failed')) {
      return statuses
    }

    await sleep(5000) // Check every 5 seconds
  }
}
```

## Feature Development Process

### User Stories Are Non-Negotiable

**CRITICAL**: Every feature MUST originate with a user story. No implementation without understanding the user experience first.

**Workflow**:
1. Define the user story before design
2. Agree on how a real human will experience the feature
3. Map the complete user journey (happy path + edge cases)
4. Only then design the technical implementation

**User Story Format**:
```
As a [user type]
I want to [action]
So that [benefit]

Acceptance Criteria:
- [ ] User can...
- [ ] System responds by...
- [ ] Error cases handled...
```

**Example - Wrong Approach**:
```
❌ "Add a new database table for user preferences"
❌ "Implement caching for the settings endpoint"
❌ "Refactor the authentication service"
```

**Example - Correct Approach**:
```
✅ "As a user, I want to customize my dashboard layout so that I can
   see the information most relevant to me first"

   Experience:
   - User clicks "Customize" button on dashboard
   - Drag-and-drop interface appears
   - Changes save automatically with visual feedback
   - Layout persists across sessions

   Then we design: caching strategy, database schema, API endpoints
```

### Experience-First Design

Before writing code, answer:
1. **Who** is the user?
2. **What** are they trying to accomplish?
3. **Where** in the product does this happen?
4. **When** do they need this feature?
5. **How** will they interact with it (step-by-step)?
6. **Why** is this valuable to them?

### Common Anti-Patterns

❌ **Implementation-first thinking**:
- "Let's add a Redis cache" → Why? What user problem does this solve?
- "We need a WebSocket connection" → For what user experience?
- "Add this column to the database" → What can users now do?

✅ **User-first thinking**:
- "Users wait 5s for dashboard load → cache frequently accessed data"
- "Users need real-time notifications → WebSocket for live updates"
- "Users want to save preferences → persist settings in database"

### Design Agreement Checklist

Before implementation:
- [ ] User story documented
- [ ] Complete user journey mapped (screenshots/wireframes if UI change)
- [ ] Edge cases identified (errors, empty states, loading states)
- [ ] Success criteria defined (how do we know it works?)
- [ ] Team agrees on the experience
- [ ] Technical approach aligns with user needs

### When to Skip This Process

Never. Even for:
- Bug fixes → "As a user, I expect X but currently experience Y"
- Performance improvements → "As a user, I'm frustrated by slow Z"
- Refactoring → "As a developer, I can't maintain/extend X because Y"
- Infrastructure → "As a user, I need reliability/security/performance"

The user might be an end user, developer, operator, or future maintainer, but there's always a human experience to consider.

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

### Architecture Decision Records (ADRs)

**REQUIRED**: All significant architectural decisions MUST be documented in the `adr/` folder.

#### What Qualifies as an ADR
Document when:
- Choosing between architectural patterns
- Selecting frameworks, libraries, or tools
- Defining API contracts or data models
- Establishing security policies
- Making performance trade-offs
- Changing core infrastructure
- Introducing new dependencies
- Adopting coding standards

Don't document:
- Routine bug fixes
- Obvious choices with no alternatives
- Temporary workarounds (use code comments instead)

#### ADR Format
```markdown
# ADR-NNN: Title

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

#### ADR Workflow for Agents

**CRITICAL REQUIREMENT**: AI agents making architectural decisions MUST:

1. **Document Decision Rationale**
   - Create ADR in `adr/` folder before implementation
   - Number sequentially: `adr-001-title.md`, `adr-002-title.md`, etc.
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

#### Example Agent ADR Workflow
```bash
# 1. Agent creates ADR
echo "# ADR-015: Switch to Drizzle ORM..." > adr/adr-015-drizzle-orm.md

# 2. Agent invokes code reviewer
# Uses Task tool: subagent_type='neckbeard-code-reviewer'
# Prompt: "Review ADR-015 for ORM migration decision. Focus on: migration
# safety, performance implications, type safety, and developer experience."

# 3. Agent addresses feedback and updates ADR
# 4. Reviewer approves
# 5. ADR status → "Accepted"
# 6. Implementation begins
```

#### File Organization
```
adr/
├── README.md              # Index of all ADRs with status
├── template.md            # Copy this for new ADRs
├── adr-001-monorepo.md
├── adr-002-auth-strategy.md
├── adr-003-caching-layer.md
└── ...
```

#### README.md Format
```markdown
# Architecture Decision Records

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [001](./adr-001-monorepo.md) | Monorepo Structure | Accepted | 2024-01-15 |
| [002](./adr-002-auth-strategy.md) | Auth Strategy | Accepted | 2024-01-20 |
| [003](./adr-003-caching-layer.md) | Redis Caching | Deprecated | 2024-02-10 |
```

#### Updating ADRs
- Never delete ADRs (historical record)
- To supersede: Change status, link to replacement
- To deprecate: Change status, explain why
- Keep original decision visible (strikethrough if needed)

#### Review Checklist
Before accepting ADR:
- [ ] Clear problem statement
- [ ] ≥2 alternatives considered
- [ ] Explicit trade-offs documented
- [ ] Implementation steps defined
- [ ] Success metrics identified
- [ ] Code reviewer approved
- [ ] Links to related ADRs/issues

## Language-Specific Guidelines

### React

#### Component Hierarchy
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

#### Hook Guidelines
- Never call `useEffect` directly in components
- One hook per concern (don't combine unrelated logic)
- Hooks must be pure (no side effects except in useEffect)
- Always specify exhaustive dependencies
- Extract complex effects to custom hooks

#### State Management
```typescript
// ❌ WRONG - Prop drilling
<Parent>
  <Child1 onUpdate={handleUpdate} />
  <Child2 onUpdate={handleUpdate} />
  <Child3 onUpdate={handleUpdate} />
</Parent>

// ✅ CORRECT - Context for shared state
const UpdateContext = createContext<(val: T) => void>()

function Parent() {
  const handleUpdate = useCallback((val: T) => {...}, [])

  return (
    <UpdateContext.Provider value={handleUpdate}>
      <Child1 />
      <Child2 />
      <Child3 />
    </UpdateContext.Provider>
  )
}
```

#### Performance Rules
- Memo only after profiling shows need
- Don't optimize prematurely
- `useCallback` for props passed to memoized components
- `useMemo` for expensive computations only
- Virtual scrolling for lists >100 items

### Elixir

#### Naming Conventions
Elixir uses `snake_case` for variables, function names, and atoms, following the convention inherited from Erlang and common in Ruby:

```elixir
# ✅ CORRECT - Variables and functions
my_variable = "value"
calculate_total(items)
:some_atom

# ✅ CORRECT - Module names use PascalCase
defmodule MyModule do
  def my_function(param_name) do
    # ...
  end
end

defmodule GenServer do
  # ...
end

# ❌ WRONG - Using camelCase
myVariable = "value"
calculateTotal(items)

# ❌ WRONG - Using snake_case for modules
defmodule my_module do
  # ...
end
```

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

## Monitoring & Observability

### Logging Levels
- ERROR: Requires immediate action
- WARN: Degraded state, still functional
- INFO: Significant events (user actions, state changes)
- DEBUG: Detailed diagnostic info (disabled in production)

### Structured Logging
```typescript
// ✅ CORRECT
logger.info('User created', {
  userId: user.id,
  email: user.email,
  source: 'registration_flow',
  duration_ms: performance.now() - start
})

// ❌ WRONG
console.log(`User ${user.id} created`)
```

### Metrics
Track:
- Request latency (p50, p95, p99)
- Error rate (by endpoint, by error type)
- Database query time
- Cache hit rate
- Queue depth
- Active connections

### Alerting
Alert on:
- Error rate >1% sustained for 5m
- p99 latency >2s sustained for 5m
- Database connections >80% pool size
- Disk usage >85%
- Memory usage >90%

## Deployment

### Environment Parity
- Dev, staging, production must match
- Same OS, runtime versions, dependencies
- Same environment variables (different values)
- Same infrastructure (scaled down for staging)

### Configuration
```typescript
// ✅ CORRECT - Type-safe config
const config = {
  database: {
    url: env.DATABASE_URL,  // Required
    poolSize: env.DB_POOL_SIZE ?? 10,  // Optional with default
  },
  redis: {
    url: env.REDIS_URL,
  },
} as const

// Validate at startup
function validateConfig(config: unknown): Config {
  // Throw if invalid (fail fast)
  return configSchema.parse(config)
}

const validatedConfig = validateConfig(config)
```

### Zero-Downtime Deploys
1. Deploy new version alongside old
2. Health check new version
3. Gradually shift traffic (10%, 50%, 100%)
4. Monitor error rates
5. Rollback on degradation
6. Terminate old version after success

### Rollback Strategy
- Keep last 3 versions deployed
- One-command rollback
- Database migrations must be backward-compatible
- Feature flags for risky changes

## Documentation

### Code Comments
Only comment:
- Why, not what (code shows what)
- Non-obvious optimizations
- Workarounds for external bugs
- Complex algorithms (link to paper/article)
- Security-sensitive code

```typescript
// ❌ WRONG - Obvious comment
// Increment counter by 1
counter += 1

// ✅ CORRECT - Explains rationale
// Use post-increment to avoid race condition with concurrent readers
counter += 1
```

### README Requirements
Every repo must have:
- One-line description
- Prerequisites
- Setup instructions
- How to run tests
- How to deploy
- Architecture diagram
- API documentation link

### API Documentation
- Generate from code (OpenAPI, GraphQL schema)
- Include request/response examples
- Document error codes
- Link to runnable examples

### Architecture Decision Records
- **REQUIRED** for all significant decisions
- See [Architecture → ADRs](#architecture-decision-records-adrs) for full guidelines
- All ADRs in `adr/` folder with sequential numbering
- Agents MUST get code review approval before proceeding
- Keep `adr/README.md` index up to date

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

### Branch Strategy
```
main          - Production (protected)
├─ staging    - Pre-production (protected)
└─ feat/*     - Feature branches (ephemeral)
```

- Merge to staging first
- Staging → main after QA
- Delete branches after merge
- Never commit directly to main/staging

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

## Emergency Response

### Production Incidents
1. **Acknowledge** (2m): Page on-call
2. **Mitigate** (15m): Stop the bleeding (rollback, kill feature flag)
3. **Investigate** (1h): Root cause analysis
4. **Fix** (4h): Permanent solution
5. **Review** (24h): Postmortem

### Postmortem Template
```markdown
# Incident: [Title]

**Date**: YYYY-MM-DD
**Duration**: Xh Ym
**Impact**: X users affected, Y requests failed
**Severity**: Critical/Major/Minor

## Timeline
- HH:MM - Incident began
- HH:MM - Detected
- HH:MM - Mitigated
- HH:MM - Resolved

## Root Cause
[What went wrong and why]

## Resolution
[How it was fixed]

## Action Items
- [ ] Prevent recurrence
- [ ] Improve detection
- [ ] Update runbooks
```

## Conclusion

These guidelines ensure:
- **Reliability**: Systems stay up
- **Velocity**: Teams move fast
- **Quality**: Code remains maintainable
- **Security**: Users stay protected

When in doubt:
1. Make it work
2. Make it right
3. Make it fast

In that order. Always.
