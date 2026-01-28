# Documentation Accessibility Guide

Ensuring Expo Free Agent documentation is accessible to everyone, including users with disabilities.

## Accessibility Standards

We follow **WCAG 2.1 Level AA** standards for all documentation.

Key principles:
- **Perceivable**: Information must be presentable to users in ways they can perceive
- **Operable**: Interface components must be operable by all users
- **Understandable**: Information and operation must be understandable
- **Robust**: Content must be robust enough to work with current and future technologies

---

## Markdown Accessibility

### Headings Hierarchy

✅ **Correct**: Logical heading structure

```markdown
# Page Title (H1)

## Main Section (H2)

### Subsection (H3)

#### Detail (H4)
```

❌ **Incorrect**: Skipping levels

```markdown
# Page Title (H1)

### Subsection (H3)  ← Skips H2

##### Detail (H5)    ← Skips H4
```

**Why**: Screen readers use heading structure for navigation.

### Link Text

✅ **Correct**: Descriptive link text

```markdown
Read the [Architecture documentation](../architecture/architecture.md) for system design details.
```

❌ **Incorrect**: Generic link text

```markdown
Click [here](../architecture/architecture.md) for more information.
```

**Why**: Screen readers often list all links out of context. "Click here" provides no information.

### Alternative Text for Images

✅ **Correct**: Descriptive alt text

```markdown
![Expo Free Agent build lifecycle diagram showing submission, queuing, and execution phases](../architecture/diagrams/build-lifecycle.png)
```

❌ **Incorrect**: Empty or redundant alt text

```markdown
![](../architecture/diagram.png)
![Build lifecycle diagram](../architecture/diagrams/build-lifecycle.png)  ← Redundant with filename
```

**Alt text guidelines**:
- Describe what the image conveys, not what it looks like
- Be concise (aim for <150 characters)
- Don't start with "Image of" or "Picture of"
- For complex diagrams, provide extended description in text

### Code Blocks

✅ **Correct**: Language-tagged code blocks

```markdown
\`\`\`bash
bun install
\`\`\`

\`\`\`typescript
interface BuildConfig {
  platform: 'ios' | 'android';
}
\`\`\`
```

❌ **Incorrect**: Untagged code blocks

```markdown
\`\`\`
bun install
\`\`\`
```

**Why**: Language tags enable syntax highlighting and better screen reader context.

### Tables

✅ **Correct**: Tables with headers

```markdown
| Command | Description |
|---------|-------------|
| `bun controller` | Start controller |
| `bun test` | Run tests |
```

❌ **Incorrect**: Tables without clear headers

```markdown
| `bun controller` | Start controller |
| `bun test` | Run tests |
```

**Why**: Screen readers use header cells to provide context for data cells.

---

## Content Accessibility

### Plain Language

✅ **Correct**: Clear, simple language

```markdown
## Starting the Controller

1. Open a terminal
2. Navigate to the project directory
3. Run `bun controller`
4. The controller will start on port 3000
```

❌ **Incorrect**: Unnecessarily complex

```markdown
## Controller Initialization

1. Establish a command-line interface session
2. Traverse the filesystem hierarchy to the project's root directory
3. Execute the controller initialization routine via the bun runtime
4. The HTTP daemon will commence listening on TCP port 3000
```

**Guidelines**:
- Use short sentences (aim for <25 words)
- Prefer active voice ("Run the command" not "The command should be run")
- Avoid jargon unless defining it first
- Use common words over fancy alternatives

### Structure and Formatting

✅ **Correct**: Well-structured content

```markdown
## Installation

Prerequisites:
- macOS 13.0+
- Bun 1.0+

Steps:
1. Clone the repository
2. Install dependencies
3. Start the controller

**Note**: You need 16 GB+ RAM for running workers.
```

❌ **Incorrect**: Wall of text

```markdown
## Installation

You need macOS 13.0+ and Bun 1.0+ to get started first clone the repository then install dependencies and start the controller remember you need 16 GB+ RAM if you want to run workers.
```

**Guidelines**:
- Break long content into sections with headings
- Use lists for sequential steps or multiple items
- Use bold/italic sparingly for emphasis
- Add spacing between sections

### Error Messages and Warnings

✅ **Correct**: Clear error context

```markdown
**Error:** `SQLITE_BUSY: database is locked`

**Cause:** Another process is using the database.

**Solution:**
\`\`\`bash
pkill -f controller
bun controller
\`\`\`
```

❌ **Incorrect**: Cryptic error dump

```markdown
Error: SQLITE_BUSY (see logs)
```

**Guidelines**:
- State what went wrong
- Explain why it happened
- Provide actionable steps to fix
- Link to troubleshooting docs for complex issues

---

## Interactive Elements

### Command Examples

✅ **Correct**: Copy-friendly commands

```markdown
\`\`\`bash
export EXPO_CONTROLLER_API_KEY="your-api-key"
bun controller
\`\`\`
```

❌ **Incorrect**: Prompts in commands

```markdown
\`\`\`bash
$ export EXPO_CONTROLLER_API_KEY="your-api-key"
$ bun controller
\`\`\`
```

**Why**: Including `$` prompt prevents direct copy-paste.

### File Paths

✅ **Correct**: Absolute paths with context

```markdown
Edit the controller configuration:

\`\`\`
/Users/sethwebster/Development/expo/expo-free-agent/packages/controller/.env
\`\`\`

Or relative to the project root:

\`\`\`
packages/controller/.env
\`\`\`
```

❌ **Incorrect**: Ambiguous paths

```markdown
Edit `.env`
```

**Why**: Users need to know exactly where the file is located.

---

## Visual Design Considerations

### Color Usage

❌ **Don't**: Rely solely on color

```markdown
<span style="color: red">This is an error</span>
<span style="color: green">This is a success</span>
```

✅ **Do**: Use icons/text + color

```markdown
❌ **Error**: Build failed
✅ **Success**: Build completed
```

**Why**: Color-blind users and screen readers can't distinguish colors alone.

### Contrast

For any visual elements (screenshots, diagrams):
- Text on background: 4.5:1 contrast minimum
- Large text (18pt+): 3:1 contrast minimum

Use [WebAIM Contrast Checker](https://webaim.org/resources/contrastchecker/) to verify.

### Animations

For animated GIFs/videos:
- Provide static alternative or text description
- Don't flash more than 3 times per second (seizure risk)
- Include controls to pause/stop animation

---

## Testing for Accessibility

### Manual Testing

**Screen Reader Testing**:

macOS VoiceOver:
```bash
# Enable VoiceOver
Cmd + F5

# Navigate documentation
- Ctrl + Option + →  (Next heading)
- Ctrl + Option + Cmd + H  (List headings)
- Ctrl + Option + U  (Open rotor for navigation)
```

Test these scenarios:
1. Navigate by headings - can you understand page structure?
2. Navigate by links - are link texts meaningful out of context?
3. Access code blocks - is the content announced clearly?
4. Access tables - are headers announced before data?

**Keyboard Navigation**:

Test without mouse:
- Tab through all interactive elements
- Links should be reachable and visually focused
- No keyboard traps (can exit all elements)

**Mobile Testing**:

View docs on mobile device:
- Text is readable without zooming
- Links/buttons have adequate touch targets (44×44px minimum)
- Horizontal scrolling not required
- Code blocks don't overflow

### Automated Testing

Run verification script:
```bash
./scripts/verify-docs.sh
```

Checks:
- Broken links
- Missing alt text
- Code blocks without language tags
- Heading hierarchy
- Required sections

---

## Accessibility Checklist

Before submitting documentation PR:

- [ ] Logical heading hierarchy (H1 → H2 → H3, no skipping)
- [ ] Descriptive link text (no "click here")
- [ ] Alt text for all images/diagrams
- [ ] Code blocks have language tags
- [ ] Tables have header row
- [ ] Plain language (short sentences, active voice)
- [ ] Broken into sections with headings
- [ ] Commands copy-pasteable (no `$` prompts)
- [ ] Error messages include cause + solution
- [ ] Color not sole indicator (use icons/text)
- [ ] Tested with screen reader
- [ ] Tested with keyboard only
- [ ] Verified on mobile
- [ ] Runs `./scripts/verify-docs.sh` without errors

---

## Common Mistakes

### 1. Overusing Emphasis

❌ **Bad**: **Every** _other_ **word** _emphasized_

✅ **Good**: Use emphasis **sparingly** for truly important terms

### 2. ASCII Art Without Alternative

❌ **Bad**: Complex ASCII diagram with no description

✅ **Good**: ASCII diagram + text description of flow

### 3. Assuming Visual Context

❌ **Bad**: "As you can see in the screenshot above..."

✅ **Good**: "The screenshot shows the controller dashboard with 4 active workers and 2 pending builds."

### 4. Technical Jargon Without Definition

❌ **Bad**: "Use the DAG to optimize your CI pipeline"

✅ **Good**: "Use the directed acyclic graph (DAG) - a flowchart showing task dependencies - to optimize your CI pipeline"

---

## Resources

- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [WebAIM: Writing Accessible Documentation](https://webaim.org/articles/)
- [Plain Language Guidelines](https://www.plainlanguage.gov/guidelines/)
- [Markdown Accessibility](https://www.markdownguide.org/hacks/#underline)
- [VoiceOver User Guide](https://support.apple.com/guide/voiceover/welcome/mac)

---

## Getting Help

Questions about documentation accessibility?

- Check [WebAIM Knowledge Base](https://webaim.org/articles/)
- Test with real users (accessibility community forums)
- Use automated checkers (but manual review still essential)

---

**Last Updated:** 2026-01-28
**Maintained by:** Documentation Team
