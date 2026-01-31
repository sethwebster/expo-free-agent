# ADR-001: Monorepo Structure - Swift App at Root

**Status**: Accepted
**Date**: 2026-01-30
**Deciders**: @sethwebster

## Context

Expo Free Agent combines multiple language ecosystems:
- Swift/macOS worker application (Xcode + Swift Package Manager)
- JavaScript/TypeScript packages (Bun workspace)
- Elixir controller (Mix)

Need to organize codebase to prevent build tool conflicts while maintaining monorepo benefits.

## Decision Drivers

- Swift Package Manager incompatible with Bun workspaces
- Xcode expects traditional Swift package structure
- Bun workspace config (`package.json#workspaces`) cannot include Swift code
- Need clear separation between language ecosystems
- Avoid cross-contamination of build artifacts
- Support independent build processes (SwiftPM vs Bun vs Mix)

## Considered Options

### Option A: All Code in packages/ (Flat Workspace)

```
expo-free-agent/
└── packages/
    ├── free-agent/          # Swift app
    ├── controller-elixir/   # Elixir
    ├── cli/                 # TypeScript
    └── landing-page/        # React
```

**Pros:**
- Consistent with typical monorepo conventions
- All packages at same directory level
- Simpler mental model

**Cons:**
- Bun workspace attempts to process Swift files
- Xcode confused by sibling JavaScript packages in workspace
- Build tool conflicts (SPM and Bun compete)
- Swift build artifacts (`.build/`, `.swiftpm/`) mixed with `node_modules/`
- `package.json#workspaces` would need complex exclude patterns

### Option B: Swift App at Root (CHOSEN)

```
expo-free-agent/
├── free-agent/          # Swift (isolated)
└── packages/            # Bun workspace
    ├── controller-elixir/
    ├── cli/
    ├── landing-page/
    └── worker-installer/
```

**Pros:**
- Clean separation of build systems
- Xcode finds Swift Package at expected location
- Bun workspace only processes JS/TS/Elixir
- No build tool conflicts
- Swift artifacts stay isolated from Node ecosystem
- Scales to future native components (Android worker)
- Simple workspace config: `["packages/*"]`

**Cons:**
- Non-standard monorepo structure
- Requires documentation (this ADR)
- Naming asymmetry (`free-agent/` vs `packages/*`)

### Option C: Separate Repositories

**Pros:**
- Complete build system isolation
- Independent deployment cycles

**Cons:**
- Loses version synchronization
- Harder to make cross-component changes
- Split documentation
- More complex CI/CD
- Loses monorepo benefits

## Decision

Use **Option B**: Swift app at root, JavaScript/TypeScript/Elixir in `packages/`.

**Rationale:**
- Build systems operate independently without interference
- Clear mental model: native code at root, managed packages in workspace
- `package.json#workspaces: ["packages/*"]` explicitly excludes Swift
- Xcode "just works" with standard Swift package layout
- Future-proof for additional native components
- Elixir in `packages/` works because Mix doesn't conflict with Bun

## Consequences

### Positive
- Zero build tool conflicts between SPM and Bun
- Xcode opens `free-agent/` without warnings
- Bun workspace doesn't attempt to parse Swift files
- Clear language ecosystem boundaries
- Swift build artifacts isolated from Node ecosystem
- Independent versioning possible (though currently synchronized)

### Negative
- Violates typical monorepo conventions
- New contributors need this ADR to understand structure
- Documentation burden to explain separation
- Root-level scripts need path handling for both structures

### Neutral
- Version synchronization handled by pre-commit hook (all components share version)
- Tests span both root and packages (see `test-e2e.sh`)
- CI workflows separate by ecosystem (Swift vs Node vs Mix)

## Implementation

**File Organization:**
```
expo-free-agent/
├── free-agent/                  # Swift Package Manager
│   ├── Package.swift
│   ├── Sources/
│   │   ├── FreeAgent/          # macOS app
│   │   ├── BuildVM/            # VM management
│   │   └── WorkerCore/         # Worker logic
│   └── Tests/
├── packages/                     # Bun workspace
│   ├── controller-elixir/       # Mix project (Phoenix)
│   ├── cli/                     # Bun package
│   ├── landing-page/            # Vite + Bun
│   └── worker-installer/        # Bun package
├── package.json                 # Root: workspaces: ["packages/*"]
└── scripts/
    └── check-versions.ts        # Enforces version sync
```

**Build Scripts:**
- `bun controller` → `cd packages/controller-elixir && mix phx.server`
- `bun test:controller` → Mix test (Elixir)
- `bun test:cli` → Bun test (JavaScript)
- Swift tests: `cd free-agent && swift test` (not in Bun)

**Migration:** N/A (structure established at project inception)

## Validation

**Success Criteria:**
- [x] Bun workspace installs without errors
- [x] Xcode opens `free-agent/` without warnings
- [x] No build artifact cross-contamination
- [x] Version sync enforced (check-versions.ts passes)
- [x] E2E tests pass (test-e2e.sh)

**Monitoring:**
- Pre-commit hook prevents version drift
- CI fails if structure violated
- No Swift files in `packages/`, no `package.json` in `free-agent/`

## References

- [Bun Workspaces Documentation](https://bun.sh/docs/install/workspaces)
- [Swift Package Manager Guide](https://www.swift.org/package-manager/)
- Related: Future ADR for Android worker (if native Android component added)
