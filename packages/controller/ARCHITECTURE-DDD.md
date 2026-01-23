# Domain-Driven Design Principles

## Overview

The Central Controller follows Domain-Driven Design (DDD) principles to maintain clean separation of concerns, testability, and extensibility.

## Layer Architecture

```
┌─────────────────────────────────────────┐
│           CLI / Entry Point             │
│         (src/cli.ts, server.ts)         │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│          API / Routes Layer             │
│         (src/api/routes.ts)             │
│  - HTTP request handling                │
│  - Input validation                     │
│  - Response formatting                  │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│          Middleware Layer               │
│        (src/middleware/auth.ts)         │
│  - Authentication                       │
│  - Authorization                        │
│  - Request preprocessing                │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│          Domain Layer                   │
│         (src/domain/*.ts)               │
│  - Business logic                       │
│  - Value objects (Config)               │
│  - Domain models                        │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│        Service / Application Layer      │
│        (src/services/*.ts)              │
│  - JobQueue (in-memory state)           │
│  - FileStorage (file operations)        │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│        Infrastructure Layer             │
│           (src/db/*.ts)                 │
│  - Database access                      │
│  - External dependencies                │
└─────────────────────────────────────────┘
```

## Domain Layer

### Value Objects

**Config** (`src/domain/Config.ts`)
- Immutable configuration with validation
- No hard-coded values
- Default values centralized
- Validation ensures invariants

```typescript
// Good: Values come from config
const maxSize = config.maxSourceFileSize;

// Bad: Hard-coded magic number
const maxSize = 500 * 1024 * 1024;
```

### Entities

**Build** (`src/db/Database.ts:20-32`)
- Identity: `id` (nanoid)
- Lifecycle states: pending → assigned → building → completed/failed
- Business rules enforced by state transitions

**Worker** (`src/db/Database.ts:9-18`)
- Identity: `id` (nanoid)
- Status: idle → building → idle/offline
- Capabilities define build compatibility

### Aggregates

**JobQueue** (`src/services/JobQueue.ts`)
- Aggregate root for job assignment
- Maintains consistency between pending/active builds
- Encapsulates assignment logic
- Emits domain events

## Service Layer

### Application Services

**FileStorage** (`src/services/FileStorage.ts`)
- Encapsulates file system operations
- Path validation (security boundary)
- Stream abstractions
- Could be swapped for S3 without changing interfaces

**JobQueue** (`src/services/JobQueue.ts`)
- Manages build queue state
- Worker assignment logic
- Event emission for observability

## Infrastructure Layer

### Database Service

**DatabaseService** (`src/db/Database.ts`)
- Abstracts SQLite operations
- Provides typed interfaces
- Transaction support for atomicity
- Could be swapped for PostgreSQL

## Design Principles Applied

### 1. No Hard-Coded Values

**Before:**
```typescript
const upload = multer({
  limits: { fileSize: 500 * 1024 * 1024 } // Magic number!
});
```

**After:**
```typescript
const uploadSource = multer({
  limits: { fileSize: config.maxSourceFileSize }
});
```

### 2. Configuration as Value Object

**Config.ts:**
```typescript
export const DEFAULT_CONFIG = {
  apiKey: process.env.CONTROLLER_API_KEY || 'dev-insecure-key',
  maxSourceFileSize: 500 * 1024 * 1024,
  maxCertsFileSize: 10 * 1024 * 1024,
};

export function createConfig(partial: Partial<ControllerConfig>): ControllerConfig {
  const config = { ...DEFAULT_CONFIG, ...partial };

  // Validation
  if (!config.apiKey || config.apiKey.length < 16) {
    throw new Error('API key must be at least 16 characters');
  }

  return config;
}
```

### 3. Dependency Injection

**Server.ts:**
```typescript
export class ControllerServer {
  constructor(config: ControllerConfig) {
    this.config = config;
    this.db = new DatabaseService(config.dbPath);
    this.queue = new JobQueue();
    this.storage = new FileStorage(config.storagePath);

    this.setupRoutes(); // Dependencies injected
  }

  private setupRoutes() {
    // Pass dependencies to route factory
    this.app.use('/api', createApiRoutes(
      this.db,
      this.queue,
      this.storage,
      this.config
    ));
  }
}
```

### 4. Single Responsibility

Each layer has one reason to change:

- **Routes** - HTTP protocol changes
- **Middleware** - Authentication/authorization changes
- **Domain** - Business rules change
- **Services** - Application logic changes
- **Database** - Data persistence changes

### 5. Domain Events

**JobQueue emits events:**
```typescript
this.emit('job:assigned', build, worker);
this.emit('job:completed', build, worker);
this.emit('job:failed', build, worker);
```

**Server listens to events:**
```typescript
this.queue.on('job:assigned', (build, worker) => {
  console.log(`Build ${build.id} assigned to worker ${worker.name}`);
});
```

### 6. Ubiquitous Language

Terms used consistently across codebase:

- **Build** - A compilation request
- **Worker** - A machine that executes builds
- **Queue** - Pending builds awaiting assignment
- **Assignment** - Worker-build pairing
- **Source** - Input code to build
- **Certs** - Signing credentials
- **Result** - Output artifact (IPA/APK)

### 7. Encapsulation

**Bad:**
```typescript
// Direct queue manipulation
queue.pendingBuilds.shift();
queue.activeAssignments.set(build.id, assignment);
```

**Good:**
```typescript
// Encapsulated through method
const build = queue.assignToWorker(worker);
```

## Testing Strategy

### Unit Tests

Test domain logic in isolation:

```typescript
// FileStorage.test.ts
test('should reject path traversal', () => {
  expect(() => {
    storage.createReadStream('/etc/passwd');
  }).toThrow('Path traversal attempt blocked');
});
```

### Integration Tests

Test full request flow:

```typescript
// integration.test.ts
test('API endpoints require authentication', async () => {
  const response = await fetch('/api/builds/status');
  expect(response.status).toBe(401);
});
```

## Future Enhancements (DDD-Aligned)

### 1. Domain Services

Extract complex business logic:

```typescript
// src/domain/BuildAssignmentService.ts
export class BuildAssignmentService {
  canAssignToWorker(build: Build, worker: Worker): boolean {
    // Complex capability matching logic
    const capabilities = JSON.parse(worker.capabilities);
    return capabilities.platforms.includes(build.platform);
  }
}
```

### 2. Specifications Pattern

For complex queries:

```typescript
// src/domain/specifications/PendingBuildSpec.ts
export class PendingBuildSpecification {
  isSatisfiedBy(build: Build): boolean {
    return build.status === 'pending';
  }
}
```

### 3. Repository Pattern

Abstract data access:

```typescript
// src/domain/repositories/BuildRepository.ts
export interface BuildRepository {
  findById(id: string): Build | undefined;
  findPending(): Build[];
  save(build: Build): void;
}

// src/infrastructure/SqliteBuildRepository.ts
export class SqliteBuildRepository implements BuildRepository {
  // SQLite implementation
}
```

### 4. Value Objects for Build States

```typescript
// src/domain/BuildStatus.ts
export class BuildStatus {
  private constructor(private readonly value: string) {}

  static pending() { return new BuildStatus('pending'); }
  static assigned() { return new BuildStatus('assigned'); }

  canTransitionTo(next: BuildStatus): boolean {
    // State transition validation
  }
}
```

## Anti-Patterns Avoided

### ❌ Anemic Domain Model

Don't use domain objects as data bags:

```typescript
// Bad
interface Build {
  id: string;
  status: string;
}

function updateBuildStatus(build: Build, status: string) {
  build.status = status; // Logic outside domain
}
```

### ❌ Service Layer Bypass

Don't access infrastructure from routes:

```typescript
// Bad
router.get('/builds', (req, res) => {
  const builds = db.query('SELECT * FROM builds'); // Direct DB access
  res.json(builds);
});
```

### ❌ God Objects

Don't create objects that know too much:

```typescript
// Bad
class Controller {
  handleRequest() { }
  validateAuth() { }
  queryDatabase() { }
  sendResponse() { }
  // ... 50 more methods
}
```

## References

- Domain-Driven Design (Eric Evans)
- Clean Architecture (Robert C. Martin)
- AGENTS.md (project guidelines)
