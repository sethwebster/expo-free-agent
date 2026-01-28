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

If a change touches a component, also skim that component’s README:
- `packages/controller/README.md`
- `packages/worker-installer/README.md`
- `cli/README.md`
- `free-agent/README.md`

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
├── operations/          # Deployment, release, operational procedures
├── testing/            # Test strategies, procedures
└── historical/         # Archived docs, old plans
```

Component-specific docs remain in component directories:
- `packages/controller/` - Controller implementation docs
- `cli/` - CLI implementation docs
- `free-agent/` - Worker app docs
- `packages/worker-installer/` - Installer docs
- `packages/landing-page/` - Landing page docs

### When updating documentation

**For new docs:**
- Place in appropriate `docs/` subdirectory (getting-started, architecture, operations, or testing)
- Add entry to `docs/INDEX.md` in relevant section
- Use lowercase-with-hyphens naming (e.g., `setup-guide.md`)

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

---

## Golden rules (non-negotiable)

### Use Bun, keep lockfiles clean

- **Package manager/runtime**: use **Bun** (`bun install`, `bun test`, `bun run …`).
- **Do not** introduce or update `package-lock.json`, `yarn.lock`, or `pnpm-lock.yaml`.
- **Do not** suggest commands that contradict repo scripts unless you also update docs/scripts accordingly.

### Version synchronization is enforced by pre-commit

All versions must stay synchronized across:

- `package.json` (root)
- `cli/package.json`
- `packages/controller/package.json`
- `packages/landing-page/package.json`
- `packages/worker-installer/package.json`
- `cli/src/index.ts` (Commander `.version("…")`)
- `packages/worker-installer/src/download.ts` (`const VERSION = "…"` constant)

Checks:

- **Local**: `bun run test:versions`
- **Git hook**: `.githooks/pre-commit` runs the same check

If you bump a version, you must update **all** of the above in one change.

### macOS Gatekeeper / notarization safety (do not regress)

The worker installer must preserve the app bundle’s code signature and Gatekeeper validation.

Hard rules:

- **Do not** use the npm `tar` package to extract `FreeAgent.app.tar.gz`.
  - It can create AppleDouble (`._*`) files and **break signatures**.
  - Use native `tar` (`packages/worker-installer/src/download.ts`).
- **Do not** copy `.app` bundles with generic Node filesystem copying.
  - Use `ditto` for installation (`packages/worker-installer/src/install.ts`).
- **Do not** remove or “fix” quarantine attributes on notarized apps.
  - Do **not** add `xattr -cr`, `xattr -d com.apple.quarantine`, `spctl --add`, `lsregister …` to “fix” installs.

Expected verification commands (for debugging only; don’t bake risky hacks into code):

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
- **Keep timeouts/retries/backoff** conservative and documented (don’t accidentally DDOS the controller).

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

## Testing & verification (pick the smallest sufficient set)

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

## Release workflow (FreeAgent.app + npm packages)

Worker app artifact:

- Local build/sign/notarize package: `free-agent/release.sh` (see `docs/operations/release.md`)
- CI release: tag `vX.Y.Z` and push to trigger GitHub Actions release workflow

After releasing a new FreeAgent.app build:

- Update `packages/worker-installer/src/download.ts` if the download URL/version logic needs changes
- Keep version synchronization intact (see “Version synchronization” above)

---

## Agent behavior expectations

- Make changes **small and reviewable**; don’t refactor unrelated code.
- Prefer **boring, testable** implementations over cleverness.
- When you introduce new behavior, also update the most relevant doc (`README.md`, `docs/INDEX.md`, or appropriate docs under `docs/`) if users will trip over it.
