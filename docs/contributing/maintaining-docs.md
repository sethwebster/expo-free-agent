# Maintaining Documentation

Guide for keeping Expo Free Agent documentation accurate, consistent, and up-to-date.

## Documentation Philosophy

**Documentation is code.** It requires the same care as source code:
- Version controlled alongside code changes
- Reviewed in pull requests
- Tested for accuracy
- Refactored when outdated

---

## Documentation Structure

### Central Documentation (`docs/`)

```
docs/
├── INDEX.md                 # Navigation hub (START HERE)
├── getting-started/         # Onboarding, quickstart
├── architecture/            # System design, decisions
├── operations/              # Deployment, maintenance
├── testing/                 # Test strategies
├── reference/               # API docs, error codes
├── contributing/            # For contributors
└── historical/              # Archived docs
```

### Component Documentation

Each component has its own README:
- `packages/controller/README.md` - Controller overview
- `cli/README.md` - CLI usage
- `free-agent/README.md` - Worker app
- `packages/worker-installer/README.md` - Installer
- `packages/landing-page/README.md` - Landing page

### When to Use Each

**Central `docs/`**: Cross-component concepts, workflows, operations
**Component README**: Component-specific implementation, API, usage

---

## When to Update Documentation

### Code Changes That Require Doc Updates

| Change Type | Required Doc Updates |
|-------------|---------------------|
| New API endpoint | `docs/reference/api.md`, component README, possibly examples |
| New CLI command | `cli/README.md`, `docs/getting-started/` if user-facing |
| New error code | `docs/reference/errors.md` |
| Architecture change | `docs/architecture/architecture.md`, possibly diagrams |
| Breaking change | All affected docs + migration guide |
| Security fix | `docs/architecture/security.md`, component SECURITY.md |
| Dependencies | Component README (if user-visible), setup guides |
| Environment variables | Setup guides, component README |
| Build/release process | `docs/operations/release.md` |

### Documentation-Only Changes

Safe to update without code changes:
- Fixing typos/grammar
- Clarifying confusing sections
- Adding examples
- Improving navigation
- Updating outdated screenshots

---

## Documentation Workflow

### For Code Changes

1. **Write code + tests**
2. **Identify affected docs** (see table above)
3. **Update docs in same PR**
4. **Run verification**: `./scripts/verify-docs.sh`
5. **Self-review**:
   - Are new features documented?
   - Are examples up-to-date?
   - Are cross-references correct?
6. **Commit** (docs in same commit or separate, both OK)

### For Doc-Only Changes

1. **Make changes**
2. **Run verification**: `./scripts/verify-docs.sh`
3. **Test examples** if you changed them
4. **Submit PR** with `docs:` prefix

---

## Documentation Quality Standards

### Essential Elements

Every guide should have:

**1. Purpose Statement**
```markdown
# Guide Title

One-sentence description of what this guide accomplishes.

**Goal**: What you'll achieve by following this guide.
```

**2. Prerequisites**
```markdown
## Prerequisites

- Required software/knowledge
- Links to setup guides if needed
```

**3. Clear Steps**
```markdown
## Step 1: Do This Thing (2 minutes)

Brief explanation of what and why.

\`\`\`bash
# Commands here
\`\`\`

**Expected output:**
\`\`\`
What you should see
\`\`\`
```

**4. Troubleshooting**
```markdown
## Troubleshooting

**Problem**: Error message

**Solution**: How to fix it
```

**5. Next Steps**
```markdown
## Next Steps

- Link to related guides
- Link to advanced topics
```

### Style Guidelines

**Voice and Tone**:
- Active voice ("Run the command" not "The command should be run")
- Direct ("You need" not "One would need")
- Conversational but professional
- Encouraging ("Great! Now you..." not "Proceed to step 4...")

**Formatting**:
- Use headings to break up content (every 2-3 paragraphs)
- Use lists for multiple items
- Use code blocks for all commands/code
- Use bold for UI elements ("Click the **Start** button")
- Use `monospace` for file paths, variables, short code snippets

**Examples**:
- Concrete, runnable examples (not `<placeholder>`)
- Show expected output
- Include error scenarios when relevant

**Links**:
- Use relative paths for internal docs
- Use descriptive link text (not "click here")
- Test all links with `./scripts/verify-docs.sh`

---

## Common Maintenance Tasks

### Adding New Documentation

1. **Choose location**:
   - Central docs: `docs/<category>/your-doc.md`
   - Component docs: `<component>/README.md` or `<component>/TOPIC.md`

2. **Create file**:
   ```bash
   # Use lowercase-with-hyphens naming
   touch docs/getting-started/new-guide.md
   ```

3. **Add to INDEX.md**:
   ```markdown
   ## Getting Started

   - [New Guide](./getting-started/new-guide.md) - Brief description
   ```

4. **Write content** (see quality standards above)

5. **Verify**:
   ```bash
   ./scripts/verify-docs.sh
   ```

### Updating Existing Documentation

1. **Read current version** thoroughly
2. **Make changes** (preserve style/voice)
3. **Update "Last Updated" footer** if present
4. **Check cross-references**:
   ```bash
   # Find files linking to this doc
   grep -r "your-doc.md" docs/
   ```
5. **Verify**:
   ```bash
   ./scripts/verify-docs.sh
   ```

### Archiving Obsolete Documentation

1. **Move to `docs/historical/`**:
   ```bash
   git mv docs/topic/old-doc.md docs/historical/
   ```

2. **Add note at top**:
   ```markdown
   > **⚠️ Historical Documentation**
   > This document is archived and may be outdated.
   > See [current docs](../INDEX.md) for up-to-date information.
   ```

3. **Remove from `docs/INDEX.md`**

4. **Update references**:
   ```bash
   # Find all references
   grep -r "old-doc.md" docs/

   # Update them to point to new location or alternative
   ```

### Fixing Broken Links

1. **Run verification**:
   ```bash
   ./scripts/verify-docs.sh
   ```

2. **Fix each broken link**:
   - Update path if file moved
   - Remove link if file deleted
   - Add archived note if file archived

3. **Verify again**:
   ```bash
   ./scripts/verify-docs.sh
   ```

---

## Documentation Review Checklist

### Content Review

- [ ] Technically accurate (test all examples)
- [ ] Up-to-date (no obsolete information)
- [ ] Complete (covers all aspects of topic)
- [ ] Appropriate depth (matches audience expertise)
- [ ] Logical flow (information in right order)

### Style Review

- [ ] Clear headings (descriptive, hierarchical)
- [ ] Short paragraphs (3-5 sentences max)
- [ ] Active voice
- [ ] Consistent terminology
- [ ] Code blocks have language tags
- [ ] Examples are concrete and runnable

### Structure Review

- [ ] Purpose statement at top
- [ ] Prerequisites listed
- [ ] Steps are clear and numbered
- [ ] Expected outputs shown
- [ ] Troubleshooting section
- [ ] Next steps / related docs

### Accessibility Review

- [ ] Logical heading hierarchy (no skipping levels)
- [ ] Descriptive link text
- [ ] Alt text for images
- [ ] Plain language (short sentences, common words)
- [ ] Color not sole indicator (use icons/text)

### Technical Review

- [ ] All commands tested and work
- [ ] File paths correct
- [ ] Cross-references valid
- [ ] No broken links
- [ ] Passes `./scripts/verify-docs.sh`

---

## Documentation Automation

### Verification Script

Run before every commit:
```bash
./scripts/verify-docs.sh
```

Checks:
- All indexed files exist
- No broken internal links
- Required sections present
- Code blocks tagged
- Terminology consistent
- Examples have README

### Git Hooks

Pre-commit hook runs verification automatically:
```bash
# .githooks/pre-commit
./scripts/verify-docs.sh || exit 1
```

### CI Integration

GitHub Actions runs doc checks on PRs:
```yaml
- name: Verify documentation
  run: ./scripts/verify-docs.sh
```

---

## Handling Breaking Changes

### Process

1. **Document the change**:
   ```markdown
   ## Breaking Changes in v2.0.0

   ### API Endpoint Renamed

   **Old**: `POST /api/submit`
   **New**: `POST /api/builds/submit`

   **Migration**:
   Update your CLI scripts from:
   \`\`\`bash
   curl -X POST $URL/api/submit
   \`\`\`

   To:
   \`\`\`bash
   curl -X POST $URL/api/builds/submit
   \`\`\`
   ```

2. **Update all affected docs**:
   - API reference
   - Examples
   - Guides
   - Component READMEs

3. **Add migration guide** if complex

4. **Keep old docs available** for one version:
   ```markdown
   > **Note**: Looking for v1.x docs? See [archived docs](../historical/).
   ```

---

## Documentation Debt

### What is Documentation Debt?

Like technical debt, documentation debt accumulates when:
- Docs not updated with code changes
- Examples become outdated
- Links break as files move
- New features go undocumented

### Reducing Documentation Debt

**Quarterly audit**:
1. Run `./scripts/verify-docs.sh`
2. Review all warnings
3. Test all examples
4. Update outdated screenshots
5. Archive obsolete docs

**Per-feature checklist**:
- [ ] Feature documented before merge
- [ ] Examples added
- [ ] API reference updated
- [ ] Tests include doc validation

---

## Documentation Metrics

### Key Metrics to Track

**Completeness**:
- % of features documented
- % of API endpoints in reference
- % of error codes cataloged

**Quality**:
- Broken links count (should be 0)
- Average time to find information
- User feedback scores

**Maintenance**:
- Days since last update per doc
- Number of outdated docs
- Documentation debt backlog

---

## Resources

- [Documentation Verification Script](../../scripts/verify-docs.sh)
- [Accessibility Guide](./accessibility.md)
- [Contributing Guide](./GUIDE.md)
- [Style Guide](https://developers.google.com/style) (external reference)

---

## Getting Help

**Questions about documentation?**

- Check existing docs for examples
- Review [Contributing Guide](./GUIDE.md)
- Ask in GitHub Discussions
- Tag `@docs-team` in PR for review

**Found outdated docs?**

- Open an issue with `documentation` label
- Submit a PR to fix (preferred!)
- Tag maintainers if urgent

---

**Last Updated:** 2026-01-28
**Maintained by:** Documentation Team
