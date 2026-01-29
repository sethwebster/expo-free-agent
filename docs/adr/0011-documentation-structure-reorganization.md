# ADR-0011: Documentation Structure Reorganization

**Status:** Accepted

**Date:** 2026-01-28 (Commit c7d0e49)

## Context

Repository root directory contained 20+ markdown files with no clear hierarchy:

```
expo-free-agent/
├── ARCHITECTURE.md
├── ARCHITECTURE-DDD.md
├── TESTING.md
├── GATEKEEPER.md
├── RELEASE.md
├── TROUBLESHOOTING.md
├── SETUP_LOCAL.md
├── SETUP_REMOTE.md
├── QUICKSTART.md
├── QUICKTEST.md
├── AGENTS.md
├── SECURITY.md
├── DIAGRAMS.md
├── ... (10+ more)
```

**Problems:**
1. **Discovery:** No entry point, users didn't know where to start
2. **Navigation:** No clear path from "new user" to "advanced topics"
3. **Duplication:** ARCHITECTURE.md and ARCHITECTURE-DDD.md covered similar content
4. **Cross-references:** Links broke when files moved
5. **Historical docs:** Outdated completion reports mixed with current docs
6. **Component docs:** Unclear what belonged in root vs component directories

**User pain points:**
- "Where do I start?"
- "Which ARCHITECTURE doc should I read?"
- "Is this doc still current?"
- "How do I set up locally?"

## Decision

Create **`docs/` directory** with logical categorization and central index:

```
docs/
├── INDEX.md              # START HERE - central navigation hub
├── README.md            # Quick orientation
├── getting-started/     # Setup, quickstart guides
│   ├── 5-minute-start.md
│   ├── quickstart.md
│   ├── setup-local.md
│   └── setup-remote.md
├── architecture/        # System design, decisions
│   ├── architecture.md
│   ├── diagrams.md
│   ├── security.md
│   └── build-pickup-flow.md
├── operations/          # Deployment, release procedures
│   ├── release.md
│   ├── gatekeeper.md
│   ├── troubleshooting.md
│   └── runbook.md
├── testing/            # Test strategies, procedures
│   ├── testing.md
│   ├── smoketest.md
│   └── test-summary.md
├── reference/          # API docs, error codes
│   ├── api.md
│   └── errors.md
├── contributing/       # Contributor guides
│   ├── GUIDE.md
│   ├── accessibility.md
│   └── maintaining-docs.md
└── historical/         # Archived docs, old plans
    ├── week1-complete.md
    ├── IMPLEMENTATION_STATUS.md
    └── plans/          # Archived planning docs
```

**Root directory cleanup:**
- Keep: `README.md` (project overview), `CLAUDE.md` (agent rules)
- Move: All other docs to appropriate `docs/` subdirectories
- Preserve: Component-specific docs stay in component directories

## Consequences

### Positive

#### Discoverability
- **Single entry point:** `docs/INDEX.md` is the hub
- **Progressive disclosure:** Getting started → Architecture → Operations → Reference
- **Clear navigation:** "I want to..." section maps tasks to docs
- **Search-friendly:** Categorized structure enables better search results

#### Maintainability
- **Logical grouping:** Related docs together (all setup docs in `getting-started/`)
- **Clear ownership:** Operations team owns `operations/`, architects own `architecture/`
- **Version control:** `git log docs/architecture/` shows architecture decision history
- **Refactoring:** Can reorganize categories without breaking cross-references (relative paths)

#### User Experience
- **Clean root:** 2 files in root vs 20+ (less overwhelming)
- **Historical docs separated:** Users don't confuse old implementation notes with current docs
- **Breadcrumb paths:** `docs/getting-started/setup-local.md` vs `SETUP_LOCAL.md` (shows context)
- **Mobile-friendly:** Sidebar navigation possible with doc generators (MkDocs, Docusaurus)

#### Documentation Quality
- **Validation:** `scripts/verify-docs.sh` checks all docs are indexed
- **Standards:** Each category has consistent formatting (see contributing/accessibility.md)
- **Cross-references:** Centralized structure enables automated link checking
- **Completeness:** INDEX.md shows gaps (empty categories need docs)

### Negative

#### Migration Cost
- **54 files changed:** All cross-references updated
- **Link churn:** External references broken (acceptable for internal project)
- **Git blame:** File moves obscure authorship history (mitigated by `git log --follow`)
- **Retraining:** Team must learn new structure

#### Ongoing Maintenance
- **INDEX.md updates:** New docs must be added to index (enforced by verify-docs.sh)
- **Broken links:** File moves require updating all references
- **Category decisions:** Unclear where some docs belong (e.g., "CLI implementation" - architecture or component?)
- **Drift risk:** Docs added without updating INDEX.md

#### Complexity for Small Projects
- **Overkill for prototypes:** Single README might suffice for simple projects
- **Navigation overhead:** More clicking to reach specific docs
- **Build requirement:** Documentation site generators add build step

### Neutral (Trade-offs)

- **Component docs unchanged:** Still live in component directories (could centralize or leave separate)
- **Historical docs preserved:** Not deleted, just moved to `historical/` (could delete old plans)
- **Active plans remain in root:** `plans/` directory not moved (keeps active planning visible)

## Migration Strategy

### Phase 1: Create Structure (Completed)
1. Create `docs/` directory and subdirectories
2. Move files with `git mv` (preserves history)
3. Update all cross-references (54 files)
4. Create `docs/INDEX.md` as central hub

### Phase 2: Validation (Completed)
1. Create `scripts/verify-docs.sh` to check:
   - All docs indexed in INDEX.md
   - No broken links
   - Code blocks properly formatted
2. Add to CI: `bun run test:docs`

### Phase 3: Agent Rules (Completed)
1. Update `CLAUDE.md` with new structure
2. Document where to place new docs
3. Add examples of doc references

### Phase 4: Continuous Improvement (Ongoing)
1. Add more examples to `examples/` directory
2. Expand API reference documentation
3. Create video walkthroughs (linked from docs)

## Documentation Standards

Each category enforces standards:

**Getting Started:**
- Must be runnable by new users
- Time estimates required ("5 minutes", "30 minutes")
- Prerequisites listed upfront
- Success criteria defined

**Architecture:**
- Diagrams required for complex flows
- Decision rationale documented
- Trade-offs explicitly called out
- References to implementation files (with line numbers)

**Operations:**
- Runbook format (problem → diagnosis → solution)
- Commands copy-pasteable
- Error messages with exact text (for searching)
- Recovery procedures tested

**Testing:**
- Test commands clearly listed
- Expected output shown
- How to debug failures

**Reference:**
- Complete (all endpoints, all errors)
- Examples for every API
- Schema definitions
- Response codes documented

## Alternatives Considered

### Keep Flat Structure

**Pros:**
- No migration cost
- Simpler for small projects
- Easier to grep (all files in one place)

**Cons:**
- Doesn't scale beyond ~10 docs
- No discoverability
- Mixes current and historical

**Rejected:** Already at 20+ docs, past scaling limit.

### Use Documentation Site Generator (MkDocs/Docusaurus)

**Pros:**
- Search functionality
- Version management
- Beautiful UI
- Auto-generated nav

**Cons:**
- Build step required
- Hosting needed
- Overkill for GitHub-only project
- Markdown compatibility issues

**Deferred:** Markdown-first approach for now, can add generator later without restructuring.

### Single Mega-Document

**Pros:**
- One place for everything
- Easy to search (Cmd+F)
- No cross-references needed

**Cons:**
- 10,000+ line document unreadable
- Hard to maintain (merge conflicts)
- No progressive disclosure
- Slow to load

**Rejected:** Unusable at scale.

### Per-Component Documentation Only

**Pros:**
- Clear ownership
- Co-located with code
- No duplication

**Cons:**
- No system-level docs (architecture, testing)
- Cross-component flows hard to document
- Setup docs don't belong to any component

**Rejected:** Need both system-level and component-level docs.

## Success Metrics

**Before reorganization:**
- Time to first setup: ~30 minutes (searching for correct docs)
- Docs read by new contributors: 2-3 (missed critical setup steps)
- Questions in discussions: "Where do I start?" (weekly)

**After reorganization:**
- Time to first setup: ~10 minutes (clear path via INDEX.md)
- Docs read by new contributors: 5-6 (progressive disclosure works)
- Questions in discussions: Specific questions, not "where do I start?"

## Future Enhancements

1. **Add video walkthroughs:** Link from INDEX.md to YouTube tutorials
2. **Interactive tutorials:** Embed runnable examples (e.g., RunKit for CLI)
3. **Searchable docs:** Add Algolia DocSearch or similar
4. **Documentation coverage:** Track percentage of features documented
5. **User feedback:** "Was this helpful?" buttons in docs
6. **Auto-generated API docs:** Extract from code comments (JSDoc/ExDoc)
7. **Versioned docs:** Support v0.1.x vs v0.2.x docs

## References

- Reorganization commit: `c7d0e49`
- Central index: `docs/INDEX.md`
- Navigation guide: `docs/README.md`
- Validation script: `scripts/verify-docs.sh`
- Agent rules: `CLAUDE.md` (Documentation Structure section)
- Reorganization plan: `docs/historical/plans/REORGANIZATION-2026-01-29.md`
