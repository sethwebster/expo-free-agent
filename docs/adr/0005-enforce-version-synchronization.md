# ADR-0005: Enforce Version Synchronization Across All Components

**Status:** Accepted

**Date:** 2026-01-27 (Commit 3d769f1)

## Context

Monorepo contains multiple publishable packages:
- CLI (`packages/cli/package.json`) - published to npm as `@sethwebster/expo-free-agent`
- Controller (`packages/controller-elixir/`) - Elixir/Phoenix backend, not published
- Worker Installer (`packages/worker-installer/package.json`) - published to npm
- Landing Page (`packages/landing-page/package.json`) - deployed to Cloudflare Pages
- Worker App (`free-agent/`) - Swift app, uses version from Info.plist

Version numbers also embedded in TypeScript constants and plist files:
- `packages/cli/src/index.ts` - Commander `.version("X.Y.Z")`
- `packages/worker-installer/src/download.ts` - `const VERSION = "X.Y.Z"`
- `free-agent/Info.plist` - `CFBundleShortVersionString`

**Problem:** Versions drifted out of sync, causing:
- CLI reporting v0.1.4 while package.json said v0.1.5
- Installer downloading v0.1.11 app but npm published v0.1.12
- Users confused about which versions are compatible
- GitHub releases referencing wrong versions

## Decision

**Enforce version synchronization** via pre-commit hooks and CI:

1. All `package.json` files must have identical version
2. TypeScript version constants must match package.json
3. Git hook blocks commits with mismatched versions
4. CI fails PRs with version drift
5. Manual verification command: `bun run test:versions`

**Synchronized locations (7 total):**
- `package.json` (root)
- `packages/cli/package.json`
- `packages/landing-page/package.json`
- `packages/worker-installer/package.json`
- `packages/cli/src/index.ts` (`.version("...")`)
- `packages/worker-installer/src/download.ts` (`const VERSION = "..."`)
- `free-agent/Info.plist` (`CFBundleShortVersionString`)

## Consequences

### Positive

- **Prevents drift:** Impossible to commit mismatched versions
- **Clear errors:** Script prints exactly which files are out of sync
- **Fast feedback:** Pre-commit hook catches issues before push
- **CI protection:** PRs blocked if version check bypassed locally
- **Documentation:** `CLAUDE.md` codifies this as mandatory rule
- **Audit trail:** Version bumps show up clearly in git history

### Negative

- **Every bump touches 7 files:** More merge conflicts on concurrent feature branches
- **Pre-commit overhead:** Adds ~200ms to every commit (acceptable)
- **Cannot version independently:** All components must stay synchronized
- **No semantic versioning per component:** Patch to CLI bumps controller version too
- **Manual updates:** No automation for bumping versions (must edit files manually)

### Tight Coupling Implications

**Pros:**
- Clear compatibility: v0.1.16 CLI works with v0.1.16 worker
- Simplified release process: Single version number for entire system
- Easy to document: "Install v0.1.20" vs "Install CLI v0.1.4 + worker v0.1.12"

**Cons:**
- Controller version bumps even when unchanged
- Landing page version bumps for backend changes
- Version numbers don't reflect semantic changes per component

## Implementation

**Validation script:** `scripts/check-versions.ts`
- Parses `package.json` files (JSON.parse)
- Extracts TypeScript constants (regex: `\.version\(['"]([^'"]+)['"]\)` and `const VERSION = ['"]([^'"]+)['"]`)
- Compares all extracted versions
- Exits with code 1 if any mismatch

**Pre-commit hook:** `.githooks/pre-commit`
```bash
#!/bin/bash
bun run test:versions
if [ $? -ne 0 ]; then
  echo "Version sync check failed. Update all versions to match."
  exit 1
fi
```

**Git configuration:** `git config core.hooksPath .githooks`

## Alternative Considered: Independent Versioning

**Approach:** Each component maintains its own semantic version.

**Pros:**
- True semantic versioning (patch changes don't bump unrelated components)
- Smaller diffs (only changed components bump version)
- Standard monorepo practice (Lerna, Changesets)

**Cons:**
- Compatibility matrix complexity: "CLI v2.3.1 works with controller v1.4.2 and worker v0.5.8"
- Installation instructions become complex
- Version management tools required (Lerna/Changesets)
- Release coordination harder

**Rejected because:** Prototype benefits from simplicity. Version sync overhead is acceptable for current scale.

## Future Migration Path

When project matures and releases stabilize:
- Adopt Changesets for independent versioning
- Maintain compatibility matrix in documentation
- Keep core version (e.g., "Expo Free Agent v1.0.0") as marketing version
- Individual component versions for semantic changes

## References

- Check script: `scripts/check-versions.ts`
- Pre-commit hook: `.githooks/pre-commit`
- Agent rules: `CLAUDE.md` (Version Synchronization section)
- CI integration: `.github/workflows/test.yml` (if exists)
