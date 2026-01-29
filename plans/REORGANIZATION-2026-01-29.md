# Plans Directory Reorganization - 2026-01-29

## Summary

Cleaned up and organized the `plans/` directory, moving completed/obsolete items to `docs/historical/plans/` and renaming files for clarity.

## Changes Made

### Files Moved to Historical (7 total)

| Original | Destination | Reason |
|----------|-------------|--------|
| code-review-PR3.md | docs/historical/plans/ | Superseded by updated version |
| code-review-PR3-updated.md | docs/historical/plans/ | PR3 merged, review complete |
| code-review-PR2-updated.md | docs/historical/plans/ | PR2 merged, review complete |
| code-review-PR4-docs-reorg-2026-01-28.md | docs/historical/plans/ | PR4 merged, review complete |
| pr2-review-comment.md | docs/historical/plans/ | Draft comment, no longer needed |
| pr3-comment.md | docs/historical/plans/ | Draft comment, no longer needed |
| code-review-2025-01-28.md | docs/historical/plans/code-review-2025-01-28-pre-pr3.md | Generic review, renamed for context |

### Files Renamed (2 total)

| Old Name | New Name | Reason |
|----------|----------|--------|
| before-after-comparison.md | race-condition-fixes-before-after.md | More descriptive, groups with related file |
| e2e-test-verification-report.md | e2e-elixir-verification.md | Shorter, clearer purpose |

### Files Kept in Active Plans (5 total)

| File | Status | Keep Reason |
|------|--------|-------------|
| code-review-2026-01-29-elixir-migration.md | Active | Current work, critical issues to fix |
| race-condition-fixes-summary.md | Complete | Reference for recent fixes |
| race-condition-fixes-before-after.md | Complete | Companion to summary, shows code changes |
| e2e-elixir-verification.md | Blocked | Waiting for test suite fixes |
| webby-quality-docs.md | 80% Complete | Ongoing doc improvement project |

### New Files Created (2 total)

1. **plans/README.md** - Directory guide explaining structure, conventions, and current status
2. **plans/REORGANIZATION-2026-01-29.md** - This file, documenting the reorganization

## Rationale

### Archived Files

**PR Code Reviews (4 files)**: All PRs (2, 3, 4) are merged. Code reviews served their purpose and are now historical record.

**PR Comment Drafts (2 files)**: Draft comments that were posted to PRs. No longer needed in active directory.

**Generic Review**: The `code-review-2025-01-28.md` was a pre-PR3 general review. Renamed to provide context and archived.

### Renamed Files

**Race Condition Fixes**: Original `before-after-comparison.md` was too generic. New name clearly indicates it's related to race condition fixes and groups it with the summary file.

**E2E Verification**: Original `e2e-test-verification-report.md` was verbose. New name is shorter and clearly indicates Elixir controller E2E testing.

### Active Plans

**Elixir Migration Review**: Most recent and active work. Contains critical RED issues that must be fixed before merge.

**Race Condition Documentation**: Completed work but valuable reference. Shows what was fixed and why. Includes test verification procedures.

**E2E Verification**: Blocked waiting for test suite fixes but will be needed soon. Comprehensive API compatibility analysis shows no breaking changes.

**Webby Docs Plan**: Long-term documentation improvement initiative. 8/10 stages complete (80%). Stages 4 and 6 deferred pending infrastructure.

## Directory Structure

```
plans/
├── README.md                                    # NEW: Directory guide
├── REORGANIZATION-2026-01-29.md                 # NEW: This file
├── code-review-2026-01-29-elixir-migration.md   # Active review
├── race-condition-fixes-summary.md              # Complete reference
├── race-condition-fixes-before-after.md         # RENAMED from before-after-comparison.md
├── e2e-elixir-verification.md                   # RENAMED from e2e-test-verification-report.md
└── webby-quality-docs.md                        # 80% complete project

docs/historical/plans/
├── code-review-PR3.md                           # MOVED
├── code-review-PR3-updated.md                   # MOVED
├── code-review-PR2-updated.md                   # MOVED
├── code-review-PR4-docs-reorg-2026-01-28.md     # MOVED
├── pr2-review-comment.md                        # MOVED
├── pr3-comment.md                               # MOVED
├── code-review-2025-01-28-pre-pr3.md            # MOVED + RENAMED
└── [other historical files...]
```

## Benefits

1. **Clear Active vs Historical Separation**: Active directory now contains only relevant, in-progress work
2. **Eliminated Duplicates**: Consolidated multiple PR3 reviews into historical archive
3. **Descriptive Names**: Renamed files clearly indicate their purpose and content
4. **Documentation**: README provides guidance for future work and agent usage
5. **Maintainability**: Clear rules for when to archive and how to name files

## Guidelines for Future Work

### When to Create Plans

- Complex/multi-step implementations
- Code reviews for PRs
- Verification/testing reports
- Documentation initiatives

### Naming Conventions

- `code-review-YYYY-MM-DD-description.md`
- `plan-YYYY-MM-DD-feature.md`
- `summary-YYYY-MM-DD-topic.md`
- `verification-YYYY-MM-DD-component.md`

### When to Archive

- PR is merged (code reviews)
- Plan is fully implemented
- Work is abandoned/obsolete
- Content superseded by newer version

### Using README

Update `plans/README.md` when:
- Adding new active plans
- Changing file status
- Archiving completed work
- Adding new conventions

## Implementation Notes

All file movements used `git mv` to preserve history. Renaming maintains commit history via `git log --follow`.

## Next Actions

1. Continue fixing RED issues in Elixir migration review
2. Run E2E tests once test suite fixed
3. Consider completing Webby docs stages 4 & 6 when infrastructure available
4. Archive this reorganization doc once changes reviewed/merged
