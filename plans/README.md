# Plans Directory

This directory contains **active** planning documents, code reviews, and work-in-progress analysis. Completed or obsolete plans are archived to `docs/historical/plans/`.

## Current Active Plans

### Code Reviews
- **code-review-2026-01-29-elixir-migration.md** - Code review of Elixir controller migration + worker token rotation (Jan 29, 2026)
  - Status: Active - identifies critical issues that need fixing
  - RED issues: FileStorage API mismatch, missing auth checks
  - YELLOW issues: Token rotation overhead, race conditions
  - Use this to track fixes before Elixir migration is merged

### Implementation Summaries
- **race-condition-fixes-summary.md** - Summary of race condition fixes in Elixir controller (Jan 28, 2026)
  - Status: Complete - documents fixes made
  - Keep for reference on transaction boundaries, QueueManager data loss fixes
  - Includes test verification steps

- **race-condition-fixes-before-after.md** - Before/after comparison for race condition fixes (Jan 28, 2026)
  - Status: Complete - companion to summary above
  - Shows exact code changes for each fix
  - Useful for understanding what changed and why

### Testing & Verification
- **e2e-elixir-verification.md** - E2E test verification report for Elixir controller (Jan 28, 2026)
  - Status: Blocked - waiting for test suite fixes
  - Documents API compatibility (all pass)
  - Keep until E2E tests verified working

### Documentation Projects
- **webby-quality-docs.md** - Comprehensive documentation improvement plan (Jan 28, 2026)
  - Status: 80% complete (8/10 stages)
  - Deferred: Stage 4 (interactive site), Stage 6 (videos)
  - Keep for tracking remaining doc improvements

## Archived Plans

See `docs/historical/plans/` for:
- Completed PR reviews (PR2, PR3, PR4)
- PR comment drafts
- Obsolete planning documents

## Naming Conventions

### Active Plans
Use descriptive, date-stamped names:
- `code-review-YYYY-MM-DD-description.md` - Code reviews
- `plan-YYYY-MM-DD-feature.md` - Implementation plans
- `summary-YYYY-MM-DD-topic.md` - Summaries of completed work
- `verification-YYYY-MM-DD-component.md` - Test/verification reports

### When to Archive
Move to `docs/historical/plans/` when:
- PR is merged (code reviews)
- Plan is fully implemented (implementation plans)
- Work is abandoned (obsolete plans)
- Content is superseded by newer version

## File Organization Rules

Per `CLAUDE.md`:
- Active plans stay in `plans/` (repo root)
- Only move to `docs/historical/plans/` when archived
- Use lowercase-with-hyphens naming
- Include dates in filenames for chronological sorting

## Quick Reference

| File | Purpose | Status | Next Action |
|------|---------|--------|-------------|
| code-review-2026-01-29-elixir-migration.md | Review Elixir migration | Active | Fix RED issues before merge |
| race-condition-fixes-summary.md | Document race condition fixes | Complete | Reference only |
| race-condition-fixes-before-after.md | Show before/after code | Complete | Reference only |
| e2e-elixir-verification.md | E2E test verification | Blocked | Run tests after suite fixed |
| webby-quality-docs.md | Documentation roadmap | 80% done | Complete stages 4 & 6 later |

## Usage for Agents

When working on tasks:
1. Check this directory for relevant active plans
2. Create new plan documents for non-trivial work
3. Update status in plan files as work progresses
4. Move to `docs/historical/plans/` when complete
5. Update this README if adding/removing files

## Git Workflow

All files in `plans/` are tracked by git. Use `git mv` when archiving:
```bash
# Archive a completed plan
git mv plans/plan-name.md docs/historical/plans/

# Rename for clarity
git mv plans/old-name.md plans/new-name.md
```

## History

- **2026-01-29**: Reorganized plans directory, moved 7 files to historical
  - Consolidated duplicate PR reviews
  - Renamed files for clarity
  - Created this README
- **2026-01-28**: Created race condition fix docs, E2E verification report
- **2026-01-28**: Started Webby-quality docs initiative (80% complete)
