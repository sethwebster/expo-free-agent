# Code Review: free-agent/ Directory Placement

**Date**: 2026-01-30
**Reviewer**: Architecture Review
**Subject**: Placement of Swift Package Manager project at repository root vs packages/

---

## Executive Summary

**Verdict: The current structure is architecturally sound.** The decision to place `free-agent/` at the repository root rather than inside `packages/` follows established polyglot monorepo conventions. The separation is correct, but there are minor improvements to consider for consistency and discoverability.

---

## 1. Critical Issues

None identified. The architectural decision is defensible.

---

## 2. Architecture Concerns

### 2.1 Naming Asymmetry (Minor)

**Location**: Repository root
**Problem**: `free-agent/` naming doesn't match `packages/*` pattern, creating cognitive load.

**Current**:
```
expo-free-agent/
  free-agent/           # Singular, different convention
  packages/
    controller-elixir/  # Plural pattern
    cli/
    landing-page/
    worker-installer/
```

**Impact**: Developers must remember two naming conventions. New contributors may wonder why Swift isn't in `packages/`.

**Alternatives Considered**:

1. **Keep as-is** (Recommended)
   - Pro: Build system boundaries are clear
   - Pro: Bun workspaces only see JS/TS packages
   - Con: Naming asymmetry

2. **Move to `apps/free-agent/`**
   - Pro: Clear "apps" vs "packages" separation
   - Pro: Common pattern in Turborepo/Nx monorepos
   - Con: Adds another top-level directory
   - Con: Elixir controller is also an "app" but lives in packages

3. **Move to `native/free-agent/`**
   - Pro: Platform-specific designation
   - Con: Creates yet another convention

4. **Move to `packages/free-agent-swift/`**
   - Pro: All code in one place
   - Con: Bun workspaces would try to process it
   - Con: Requires `.npmignore` or `package.json` exclusions

**Recommendation**: Keep current structure. The asymmetry is justified by build system isolation. Document the rationale in README.

### 2.2 Build System Isolation Verification

**Location**: `/package.json` workspaces config
**Current**:
```json
"workspaces": ["packages/*"]
```

**Analysis**: This correctly excludes `free-agent/` from Bun workspace resolution. The Swift package is invisible to the JS toolchain.

**Verification**:
- No `free-agent/package.json` exists (correct)
- No symlinks in `node_modules/` to Swift code (correct)
- `.gitignore` properly handles `free-agent/.build/` (correct)

**Status**: Correct implementation.

### 2.3 Mixed Paradigm in packages/

**Location**: `packages/controller-elixir/`
**Observation**: Elixir (via Mix) is also a different build system, yet it lives inside `packages/`.

**Analysis**:
- Elixir's `mix.exs` is analogous to `package.json` (dependency manifest)
- Mix doesn't interfere with Bun workspaces (Bun ignores directories without `package.json`)
- No `packages/controller-elixir/package.json` exists

**Conclusion**: The pattern is consistent. Both Elixir and Node packages coexist because neither interferes with the other. Swift could theoretically live in `packages/` too, but:
1. Swift produces a GUI macOS app (fundamentally different artifact)
2. Swift build artifacts (`.build/`, `.swiftpm/`) are larger and more complex
3. CI workflows treat it completely separately

**Status**: Defensible but worth documenting explicitly.

---

## 3. DRY Opportunities

### 3.1 Version Synchronization

**Location**: Multiple files
**Problem**: Version `0.1.23` appears in:
- `/package.json`
- `packages/cli/package.json`
- `packages/landing-page/package.json`
- `packages/worker-installer/package.json`

**Note**: `free-agent/` versions differently (via `Info.plist`, managed by `release.sh`).

**Impact**: Version drift between components. No single source of truth for JS packages.

**Recommendation**:
- Use workspace protocol or `bun link` for cross-package version
- Or use a monorepo versioning tool (changesets already mentioned in CLAUDE.md)
- Document that Swift app versions independently (this is correct for macOS apps)

### 3.2 Duplicate CI Workflows

**Location**: `.github/workflows/build-free-agent.yml` and `.github/workflows/release-worker.yml`
**Problem**: Both workflows build the Swift app with similar patterns but different approaches.

**Observation**:
- `build-free-agent.yml`: Full code signing + notarization
- `release-worker.yml`: Simpler build, skips signing (TODO comments)

**Impact**: Maintenance burden, potential drift.

**Recommendation**: Consolidate into single workflow with signing as optional input parameter.

---

## 4. Maintenance Improvements

### 4.1 Documentation Gap

**Location**: Repository root
**Problem**: No explicit documentation explaining why `free-agent/` lives at root.

**Recommendation**: Add to `README.md` or create `docs/architecture/repository-structure.md`:

```markdown
## Repository Structure

This is a polyglot monorepo containing multiple build systems:

- **packages/**: JavaScript/TypeScript packages (Bun workspaces)
  - `cli/` - Build submission CLI
  - `landing-page/` - Marketing site
  - `worker-installer/` - Worker installation CLI
  - `controller-elixir/` - Phoenix API server

- **free-agent/**: Swift Package Manager (macOS native app)
  - Lives at root to prevent Bun workspace contamination
  - Versioned independently via Info.plist
  - Built separately via `swift build`

This separation ensures:
1. `bun install` only processes JS packages
2. Swift build artifacts don't pollute node_modules
3. CI workflows can run independently
```

### 4.2 Missing Root Scripts for Swift

**Location**: `/package.json`
**Problem**: No convenience scripts for Swift builds.

**Current**: Controller has scripts, landing-page has scripts, but Swift requires manual `cd`.

**Recommendation**: Add to root `package.json`:
```json
"scripts": {
  "free-agent:build": "cd free-agent && swift build -c release",
  "free-agent:dev": "cd free-agent && swift build && open .build/debug/FreeAgent.app"
}
```

### 4.3 Inconsistent README Locations

**Location**: Various
**Observation**:
- `free-agent/README.md` exists
- `free-agent/QUICK_START.md` exists
- `packages/cli/` has no README
- `packages/controller-elixir/` uses standard Phoenix structure

**Impact**: Inconsistent onboarding experience per package.

---

## 5. Nitpicks

### 5.1 Build Artifacts in free-agent/

**Location**: `free-agent/FreeAgent.app.tar.gz`, `free-agent/FreeAgent.app.zip`
**Problem**: Release artifacts committed to repo or left in working directory.

**Observation**: `.gitignore` has these patterns:
```
free-agent/FreeAgent.app.tar.gz
free-agent/FreeAgent.app.zip
```

The files still appear in `ls -la`. If they're gitignored correctly, this is just local developer debris.

**Recommendation**: Verify these aren't tracked: `git ls-files free-agent/*.tar.gz`

### 5.2 Orphan .claude Directories

**Location**: `free-agent/.claude/`, various
**Problem**: IDE/tooling metadata scattered.

**Impact**: Minimal, already gitignored.

---

## 6. Strengths

### 6.1 Clean Build System Boundaries

The separation achieves its stated goal: Swift and Node toolchains don't interfere. `bun install` runs in ~1s because it doesn't traverse Swift code.

### 6.2 CI Workflow Isolation

`build-free-agent.yml` and `release-worker.yml` can run completely independently. No shared state or dependencies between macOS signing and npm publishing.

### 6.3 Correct Gitignore Patterns

`.gitignore` handles both ecosystems properly:
- Node: `node_modules/`, `dist/`
- Swift: `free-agent/.build/`, `free-agent/FreeAgent.app/`

### 6.4 Pragmatic Elixir Placement

Placing `controller-elixir/` inside `packages/` despite being non-JS is pragmatic:
- It's a server component, not a distributable package
- Mix isolation works fine (no `package.json` in that directory)
- Keeps the "packages" directory as "everything that runs server-side or is distributed"

---

## 7. Comparison with Industry Standards

### 7.1 Similar Projects

**Expo (expo/expo)**:
- Uses `packages/` for npm-publishable packages
- Uses `apps/` for example apps
- Native code lives within packages (`ios/`, `android/` directories)

**React Native (facebook/react-native)**:
- Monorepo with `packages/`
- Native code embedded in package directories
- Different pattern (native is part of the framework, not standalone)

**Turborepo Templates**:
- `apps/` for deployable applications
- `packages/` for shared libraries
- Would suggest `apps/free-agent/` pattern

### 7.2 Assessment

Your pattern (`free-agent/` at root) is non-standard but defensible for these reasons:
1. Swift app is a standalone product, not a shared library
2. No tooling integration between Swift and JS builds
3. Release process is completely separate

The `apps/free-agent/` pattern would be more conventional, but gains nothing practical.

---

## 8. Verdict

### Keep Current Structure

The placement of `free-agent/` at the repository root is **architecturally correct**. The rationale is sound:
- Build system isolation prevents tooling conflicts
- Independent versioning matches macOS app distribution model
- CI workflows benefit from clear separation

### Recommended Improvements

1. **Document the decision** in README or architecture docs
2. **Add root scripts** for Swift build convenience
3. **Consolidate CI workflows** to reduce duplication
4. **Verify build artifacts** aren't accidentally tracked

### Not Recommended

- Moving `free-agent/` into `packages/` (would cause Bun confusion)
- Adding `apps/` directory (overengineering for one app)
- Restructuring for structure's sake

---

## 9. Open Questions

1. Should `controller-elixir/` also live at root given it's a different build system?
   - **Answer**: No. It doesn't produce local developer artifacts and doesn't interfere with Bun.

2. Should we add a `native/` directory if future iOS/Android native components are added?
   - **Answer**: Cross that bridge when reached. Current structure works for macOS-only.

3. Is the version drift between `free-agent/` and JS packages intentional?
   - **Likely yes**: macOS app versions often diverge from backend versions. Document this.
