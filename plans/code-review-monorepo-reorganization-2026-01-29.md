# Monorepo Architecture Review & Reorganization Proposal

**Date:** 2026-01-29
**Reviewer:** Code Review Agent
**Scope:** Full repository structure analysis

---

## Executive Summary

The Expo Free Agent monorepo has **fundamental organizational flaws** that create cognitive load, complicate builds, and will cause migration pain as the project scales. The problems are fixable but require surgical intervention now rather than after more code accretes.

**Verdict: Reorganization warranted, but with caveats.**

The current structure isn't catastrophic---it's a prototype that grew organically. However, the inconsistencies will compound. The key question is whether to reorganize now (while the codebase is ~14k lines across all TypeScript/Swift/Elixir) or accept technical debt for velocity.

---

## Current Structure Analysis

```
expo-free-agent/
+-- package.json              # Bun workspace root
+-- CLAUDE.md -> docs/architecture/agents.md
+-- README.md
+
+-- cli/                      # @sethwebster/expo-free-agent (OUTSIDE packages/)
|   +-- package.json
|   +-- src/
|
+-- free-agent/               # Swift macOS app (OUTSIDE packages/)
|   +-- Package.swift
|   +-- Sources/
|   +-- release.sh
|
+-- packages/
|   +-- controller/           # @expo-free-agent/controller (TS, 4158 LOC)
|   +-- controller_elixir/    # Elixir replacement (3744 LOC) - IN packages/ despite not being TS
|   +-- landing-page/         # @expo-free-agent/landing-page (React/Vite)
|   +-- worker-installer/     # @sethwebster/expo-free-agent-worker
|
+-- docs/                     # Centralized docs
+-- examples/                 # Usage examples
+-- scripts/                  # Utility scripts
+-- test/                     # E2E test fixtures
+-- vm-setup/                 # VM image scripts
```

### Code Size Summary

| Component | LOC | Language | Published |
|-----------|-----|----------|-----------|
| Controller (TS) | 4,158 | TypeScript | No |
| Controller (Elixir) | 3,744 | Elixir | No |
| CLI | 2,785 | TypeScript | Yes (npm) |
| Worker App | 5,490 | Swift | Yes (release) |
| Worker Installer | 1,432 | TypeScript | Yes (npm) |
| Landing Page | ~2,000 | TypeScript/React | Yes (CF Pages) |
| **Total** | ~19,609 | Mixed | - |

---

## Critical Issues

### 1. Inconsistent Component Placement

**Problem:** CLI at root, controller in `packages/`, Swift app at root.

```
cli/                          # WHY HERE?
packages/controller/          # OK
free-agent/                   # WHY HERE?
```

**Impact:**
- Workspace scripts assume `packages/*` but must special-case `cli/`
- Version sync script hardcodes paths: `cli/package.json`, `packages/controller/package.json`
- New contributors confused about where things go
- Bun workspace (`"workspaces": ["packages/*"]`) doesn't include CLI

**Evidence from `package.json`:**
```json
{
  "workspaces": ["packages/*"]  // CLI excluded!
}
```

The CLI has its own `node_modules` and `bun.lock`, violating monorepo principles.

**Severity:** High (causes install/test fragmentation)

---

### 2. Elixir Controller in TypeScript Package Directory

**Problem:** `packages/controller_elixir/` contains Elixir code but lives in `packages/`.

**Impact:**
- `packages/` implies Bun workspace member, but Elixir isn't
- Inconsistent with "packages = TypeScript workspaces" mental model
- Has 25+ markdown files duplicating concepts from `docs/`
- Not included in version sync (no `package.json`)

**Severity:** Medium (conceptual confusion, doc duplication)

---

### 3. Swift App Disconnected from Package Structure

**Problem:** `free-agent/` at root, uses Swift Package Manager, not connected to Bun tooling.

**Why it matters:**
- Release workflow (`release.sh`) lives inside `free-agent/`
- GitHub Actions reference `free-agent/` with hardcoded paths
- No versioning tied to package.json (unlike everything else)
- Documentation structure different from other components

**Mitigating factor:** Swift apps genuinely can't participate in npm workspaces. The disconnect is somewhat inevitable. But the NAME is wrong---"free-agent" is the product name, not a component name. The actual binary is "FreeAgent.app", the menu bar product.

**Severity:** Medium (naming confusion, acceptable for Swift isolation)

---

### 4. Naming Inconsistencies

| Component | Directory | npm Package Name | Binary Name |
|-----------|-----------|------------------|-------------|
| Controller | `packages/controller` | `@expo-free-agent/controller` | `expo-controller` |
| CLI | `cli` | `@sethwebster/expo-free-agent` | `expo-free-agent` |
| Worker Installer | `packages/worker-installer` | `@sethwebster/expo-free-agent-worker` | `expo-free-agent-worker` |
| Worker App | `free-agent` | N/A | `FreeAgent.app` |

**Problems:**
1. Mixed npm scopes: `@expo-free-agent/` vs `@sethwebster/`
2. "worker-installer" vs "worker" (installer INSTALLS the worker)
3. Directory `cli` vs package name `expo-free-agent` (should match)
4. Directory `free-agent` vs binary `FreeAgent` (case mismatch)

**Severity:** Medium (user confusion, docs inconsistency)

---

### 5. Version Synchronization Script Hardcodes Paths

**File:** `scripts/check-versions.ts`

```typescript
const locations: VersionLocation[] = [
  { path: 'package.json', ... },
  { path: 'cli/package.json', ... },
  { path: 'packages/controller/package.json', ... },
  { path: 'packages/landing-page/package.json', ... },
  { path: 'packages/worker-installer/package.json', ... },
  { path: 'cli/src/index.ts', ... },
  { path: 'packages/worker-installer/src/download.ts', ... },
];
```

**Problem:** Any reorganization requires updating this hardcoded list.

**Severity:** Low (easily fixed during migration)

---

### 6. Documentation Duplication

**Central docs:** `docs/` (comprehensive, well-organized)

**Component docs scattered:**
- `cli/README.md`, `cli/USAGE.md`, `cli/SECURITY.md`
- `free-agent/README.md`, `free-agent/QUICK_START.md`, `free-agent/DISTRIBUTION.md`
- `packages/controller_elixir/` has 15+ markdown files (ARCHITECTURE.md, API.md, MIGRATION.md, etc.)

**Impact:**
- Elixir controller has its own parallel documentation universe
- Hard to know which docs are canonical
- ADRs in `docs/adr/` but implementation details in component dirs

**Severity:** Medium (maintenance burden, staleness risk)

---

## Architecture Concerns

### A. Two Controllers Coexisting

Per ADR-0009, the Elixir controller is the future. But:
- TypeScript controller still in `packages/controller/` (4158 LOC)
- Test scripts exist for both (`test-e2e.sh` vs `test-e2e-elixir.sh`)
- No clear deprecation path

**Question:** When does TypeScript controller get deleted?

**Recommendation:** After Elixir reaches feature parity, delete `packages/controller/` entirely. Don't maintain two.

### B. Workspace Isolation is Incomplete

CLI has its own `bun.lock` (28KB). This means:
- Dependency versions can drift between CLI and other packages
- `bun install` at root doesn't update CLI dependencies
- CI must run `bun install` in multiple directories

**Evidence:**
```
cli/bun.lock                  # 28KB
packages/controller/          # No bun.lock (uses root)
packages/landing-page/        # No bun.lock (uses root)
packages/worker-installer/    # No bun.lock (uses root)
```

CLI is the outlier. It should be in `packages/`.

### C. Test Infrastructure Fragmented

```
test/                         # Fixtures only
.test-e2e-integration/        # Hidden directory
.manual-test/                 # Hidden directory
.mock-worker/                 # Hidden directory
packages/controller/src/__tests__/    # Unit tests
cli/src/__tests__/            # Unit tests
```

No unified test structure. Hidden directories (`.test-*`) shouldn't contain production test code.

---

## DRY Opportunities

### 1. Duplicate CLI Scaffolding

Both `cli/` and `packages/worker-installer/` use:
- `commander` for CLI parsing
- `chalk` + `ora` for terminal output
- Similar config loading patterns

Could share a `@expo-free-agent/cli-utils` package:
```typescript
// packages/cli-utils/src/index.ts
export { createProgram } from './commander-wrapper';
export { createSpinner, colorize } from './terminal';
export { loadConfig, saveConfig } from './config';
```

**Savings:** ~200 lines, reduced dependency management

### 2. API Client Duplication (Potential)

Both CLI and worker-installer communicate with controller. Currently:
- `cli/src/api-client.ts` (417 lines)
- `packages/worker-installer/src/download.ts` (212 lines, partial client)

Should extract shared HTTP client:
```typescript
// packages/api-client/
export class ControllerClient {
  submitBuild(): Promise<Build>;
  getBuildStatus(): Promise<Status>;
  downloadArtifact(): Promise<Stream>;
  registerWorker(): Promise<Token>;
  // ...
}
```

---

## Maintenance Improvements

### A. Hidden Directories Should Be Visible

```
.test-e2e-integration/
.manual-test/
.mock-worker/
```

These contain real test code but are hidden. Move to `test/` subdirectories.

### B. Root-Level Markdown Pollution

```
CPU_SNAPSHOT_IMPLEMENTATION.md
FILESTORAGE_IMPLEMENTATION.md
MIGRATION_ORCHESTRATION.md
MIGRATION_PATH_PARITY.md
```

These belong in `docs/historical/` or `docs/architecture/`. Root should only have `README.md`, `CLAUDE.md`, `LICENSE`, `CONTRIBUTING.md`.

### C. Multiple Logo Files

```
logo.png                      # 145KB
expo-free-agent-logo-white.png  # 145KB
```

Should be in `assets/` or `docs/assets/`.

---

## Proposed Reorganization

### Option A: Minimal Fix (Recommended)

Move CLI into packages, clean up root, don't touch Swift.

```
expo-free-agent/
+-- package.json              # workspaces: ["packages/*", "apps/*"]
+-- README.md
+-- CONTRIBUTING.md           # NEW: extracted from CLAUDE.md
+-- LICENSE                   # NEW: add MIT license file
+
+-- apps/
|   +-- worker/               # RENAMED: free-agent -> apps/worker
|       +-- Package.swift
|       +-- Sources/
|       +-- release.sh
|
+-- packages/
|   +-- cli/                  # MOVED: cli/ -> packages/cli
|   +-- controller/           # UNCHANGED (until Elixir ready)
|   +-- controller-elixir/    # RENAMED: controller_elixir (underscores bad)
|   +-- landing-page/         # UNCHANGED
|   +-- worker-installer/     # UNCHANGED
|   +-- api-client/           # NEW: shared HTTP client
|
+-- docs/                     # UNCHANGED
+-- scripts/                  # UNCHANGED
+-- test/
|   +-- e2e/                  # MOVED: hidden dirs consolidated
|   +-- fixtures/
|   +-- mocks/
```

**Migration effort:** ~4 hours
**Breaking changes:** Import paths, version sync script, GitHub Actions

### Option B: Full Restructure (Alternative)

Separate by concern: apps vs libraries vs infrastructure.

```
expo-free-agent/
+-- apps/
|   +-- cli/                  # User-facing CLI
|   +-- worker/               # macOS worker app
|   +-- controller/           # Backend server (Elixir)
|   +-- landing-page/         # Marketing site
|
+-- packages/
|   +-- api-client/           # Shared HTTP client
|   +-- cli-utils/            # Shared CLI utilities
|   +-- types/                # Shared TypeScript types
|
+-- infra/
|   +-- worker-installer/     # Install script (not an app)
|   +-- vm-setup/             # VM image scripts
```

**Migration effort:** ~8 hours
**Breaking changes:** Everything moves, major disruption

### Option C: Keep As-Is (Status Quo)

Accept the inconsistencies, document them explicitly.

**Pros:**
- Zero migration risk
- No velocity loss
- "If it ain't broke, don't fix it"

**Cons:**
- Technical debt compounds
- New contributors confused
- Dual controller maintenance burden

---

## Migration Risks

### 1. Version Sync Script Must Update

```typescript
// scripts/check-versions.ts - MUST UPDATE PATHS
const locations: VersionLocation[] = [
  { path: 'packages/cli/package.json', ... },  // WAS: cli/package.json
  // ...
];
```

### 2. GitHub Actions Hardcode Paths

```yaml
# .github/workflows/build-free-agent.yml
working-directory: free-agent   # MUST CHANGE
run: cd free-agent && ./release.sh  # MUST CHANGE
```

### 3. Import Path Updates

Any cross-package imports must update:
```typescript
// Before
import { something } from '../../cli/src/api-client';
// After
import { something } from '@expo-free-agent/api-client';
```

### 4. Documentation References

Many docs reference `cli/`, `free-agent/`. Find-and-replace needed.

### 5. npm Package Names

If changing package locations, npm package names should probably update:
- `@sethwebster/expo-free-agent` -> `@expo-free-agent/cli`
- `@sethwebster/expo-free-agent-worker` -> `@expo-free-agent/worker-installer`

This requires republishing with deprecation notices on old packages.

---

## Should This Even Be a Monorepo?

### Arguments for Monorepo (Current Approach)

1. **Version sync:** All components release together
2. **Atomic commits:** Change CLI + controller in one commit
3. **Shared tooling:** Bun, TypeScript config, test infrastructure
4. **Discovery:** Everything in one place

### Arguments Against (Separate Repos)

1. **Swift app is foreign:** Doesn't share any code with TypeScript
2. **Elixir controller is foreign:** Different ecosystem entirely
3. **Landing page is independent:** Could be its own repo, deployed separately
4. **CI complexity:** macOS + Linux + multiple runtimes

### Verdict: Monorepo is Correct

Despite mixed languages, the components are tightly coupled:
- CLI talks to controller (API contract)
- Worker talks to controller (polling protocol)
- Worker-installer downloads worker app (version match)
- All versions must synchronize

Separate repos would require:
- Cross-repo version pinning
- Separate CI for each
- Coordination overhead for breaking changes

The monorepo tax (mixed tooling) is less than the polyrepo tax (coordination).

---

## Recommendations

### Immediate (This Week)

1. **Move CLI to packages/** - Eliminate the outlier
2. **Rename `controller_elixir` to `controller-elixir`** - Consistent naming
3. **Clean up root** - Move `*.md` files to `docs/historical/`
4. **Consolidate hidden test dirs** - Move to `test/`

### Short-Term (This Month)

5. **Delete TypeScript controller** when Elixir reaches parity
6. **Extract shared API client** - `packages/api-client`
7. **Standardize npm scopes** - All `@expo-free-agent/*`

### Long-Term (Post-Prototype)

8. **Adopt Turborepo or nx** - Better build caching, task orchestration
9. **Consider Changesets** - If independent versioning becomes needed
10. **Separate examples repo** - If examples grow significantly

---

## Unresolved Questions

1. **npm scope ownership:** Who owns `@expo-free-agent` on npm? Currently using `@sethwebster`.
2. **Elixir parity date:** When can TypeScript controller be deleted?
3. **Landing page independence:** Should it track main version or deploy independently?
4. **Swift versioning:** How to include Swift app in version sync without package.json?
5. **Worker app naming:** Keep `FreeAgent` or rename to match directory?

---

## Strengths (What Works)

1. **Version synchronization (ADR-0005):** Enforced via pre-commit hook, prevents drift
2. **Documentation structure:** `docs/` is well-organized with INDEX.md navigation
3. **ADR practice:** Key decisions documented with context and consequences
4. **Agent guidelines (CLAUDE.md):** Clear, comprehensive, enforced
5. **Gatekeeper compliance:** Native tar/ditto usage preserves code signatures
6. **Test infrastructure:** Smoketest + E2E + unit tests cover critical paths

---

## Appendix: File Counts by Component

```
packages/controller/src/         12 files, 4158 LOC
packages/controller_elixir/lib/  ~30 files, 3744 LOC
cli/src/                         19 files, 2785 LOC
free-agent/Sources/              22 files, 5490 LOC
packages/worker-installer/src/   10 files, 1432 LOC
packages/landing-page/src/       ~20 files, ~2000 LOC
```

Total: ~113 source files, ~19,609 LOC (excluding tests, docs, config)

---

**End of Review**
