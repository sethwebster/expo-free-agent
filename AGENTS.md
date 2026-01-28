Below is a polished, internally consistent, React-correct, DDD-safe rewrite of your AGENTS.md.
Tone is tightened, redundancies removed, contradictions resolved (notably the direct DB query vs DDD rule conflict), and language made more enforceable without losing urgency.

⸻

BuiltIn — Agent Behavior & Requirements

This document defines mandatory operating rules for all automated agents (ChatGPT, Claude, codegen agents, internal tools, etc.) when generating code, documentation, designs, or architectural decisions for BuiltIn.

Failure to comply with this document is considered invalid output.

⸻

Required Reading (MANDATORY)

Agents must read and comply with ALL documents below before producing ANY output:
	1.	docs/VISION-MISSION-STRATEGY-GOALS.md
Product vision, mission, and long-term strategy
	2.	docs/PRINCIPLES.md
Engineering philosophy, UX principles, and non-negotiables
	3.	docs/ROADMAP.md
Active development phases and priorities
	4.	Plan file:
/Users/sethwebster/.claude/plans/toasty-nibbling-stearns.md
Domain-Driven Design (DDD) architecture and data abstraction layer

These documents govern product intent, engineering rules, UX decisions, and architectural constraints.
If there is a conflict, these documents override all agent assumptions.

⸻

Core Requirements

Architecture & Tech Stack
	•	Mobile-first, RSC-first
	•	Design for mobile before desktop
	•	Optimize for Server Components and streaming by default
	•	Server Components by default
	•	Client Components ONLY for interactivity (forms, messaging, realtime UI)
	•	Push "use client" as far to the leaves as possible
	•	Tech Stack (Non-Negotiable)
	•	Runtime: Bun
	•	Framework: Next.js 16 (RSC-first)
	•	Styling: Tailwind CSS v4 (token-driven)
	•	Database: Postgres
	•	ORM: Drizzle
	•	Cross-platform ready
	•	APIs and domain logic must support future native iOS / Android clients
	•	No web-only architectural shortcuts

⸻

Design System Rules
	•	NO hard borders
	•	❌ border, border-2, etc.
	•	✅ shadows, soft backgrounds, subtle separators
	•	Design tokens everywhere
	•	No hard-coded colors, spacing, or radii
	•	Use CSS variables only (var(--background), var(--primary), etc.)
	•	Theme-aware
	•	Must support dynamic theming
	•	Use @media (prefers-color-scheme: dark) for system switching
	•	Visual language
	•	Light, airy, warm, community-focused
	•	Avoid harsh contrast or heavy UI density
	•	shadcn/ui usage
	•	Always add components via:

bunx shadcn@latest add <component>


	•	❌ Never manually create or edit shadcn component files

⸻

Code Quality Rules
	•	NO direct useEffect in components
	•	Always wrap logic in custom hooks
	•	Hooks must be DRY and reusable
	•	React best practices
	•	Clear component boundaries
	•	Predictable state ownership
	•	Proper prop typing and composition
	•	DDD is MANDATORY
	•	ALL data access goes through use cases and repositories
	•	❌ Never call db.query directly from:
	•	Pages
	•	Layouts
	•	Components (Server or Client)
	•	Error handling
	•	❌ Do NOT throw "NOT_FOUND" errors manually
	•	✅ Use notFound() from next/navigation
	•	URL-based UI state (Preferred)
	•	When secure and appropriate, store UI state in URL search params
	•	Enables:
	•	Shareable links
	•	Back/forward navigation
	•	Refresh persistence
	•	Deep linking
Examples:
	•	Modal open state
	•	Selected items
	•	Filters
	•	Pagination
	•	Lightbox index
Implementation:
	•	useSearchParams()
	•	router.push(..., { scroll: false })

⸻

Component Patterns

Page Structure & Suspense

Async pages are allowed. Unbounded async is the problem.

Suspension is controlled by Suspense boundaries, not by whether a page is async.

✅ Correct Patterns

// Async page with scoped suspension
export default async function Page() {
  const critical = await getCriticalData() // Fast, blocks initial render

  return (
    <div>
      <Hero data={critical} />
      <Suspense fallback={<Skeleton />}>
        <SlowSection />
      </Suspense>
    </div>
  )
}

// Cheap query, no Suspense needed
export default async function Page() {
  const data = await getCheapData()
  return <Content data={data} />
}

// Parallel fetches
export default async function Page() {
  const [users, posts] = await Promise.all([
    getUsers(),
    getPosts(),
  ])

  return <Dashboard users={users} posts={posts} />
}

❌ Anti-Pattern (Waterfall)

export default async function Page() {
  const a = await slowA()
  const b = await slowB()
  const c = await slowC()
  return <Content a={a} b={b} c={c} />
}

When to Use Suspense
	•	Slow or expensive operations
	•	Non-critical content
	•	Streaming UX improvements

When to Just Await
	•	Cheap queries (few ms)
	•	Critical data
	•	When skeletons harm UX more than a brief delay

⸻

Server Data Fetching (DDD-Correct)

Server Components may fetch data — but ONLY via use cases and repositories.

// Use case layer
export async function getUserPosts(userId: string) {
  const posts = await postRepository.findByAuthor(userId)

  return posts.map(post => ({
    ...post,
    createdAt: post.createdAt.toISOString(),
  }))
}

// Server Component
export default async function Page({ params }) {
  const posts = await getUserPosts(params.userId)
  return <PostList posts={posts} />
}


⸻

Client Component Props Pattern
	•	Parents own state
	•	Children notify via callbacks

interface SectionProps {
  initialData: DataType
  onUpdate: (data: Partial<DataType>) => void
}

export function Section({ initialData, onUpdate }: SectionProps) {
  const [localState, setLocalState] = useState(initialData)

  function handleChange(value) {
    setLocalState(value)
    onUpdate({ field: value })
  }

  return <Card />
}


⸻

Data Serialization (MANDATORY)

Dates
	•	❌ Never pass Date objects to Client Components
	•	✅ Serialize immediately after fetching

export async function getData() {
  const items = await repository.findAll()

  return items.map(item => ({
    ...item,
    createdAt: item.createdAt.toISOString(),
    updatedAt: item.updatedAt.toISOString(),
  }))
}


⸻

Prohibited Behaviors

Agents must NOT:
	•	Use hard borders
	•	Hard-code colors or spacing
	•	Use useEffect directly
	•	Bypass the DDD layer
	•	Use unstable_cache
	•	Introduce web-only assumptions
	•	Produce mobile-hostile UI
	•	Suggest dark patterns, growth hacks, or addictive mechanics
	•	Add SEO tricks that conflict with the community mission
	•	Include ANY AI attribution anywhere

⸻

Database Migrations — MORAL IMPERATIVE

Breaking migrations breaks production. This is NOT negotiable.

Iron Rules
	1.	EVERY schema change requires a migration
	•	Modify schema.ts → immediately run:

bun db:generate


	2.	ABSOLUTELY NEVER use db:push
	•	db:push has been REMOVED from package.json
	•	If you need it, you're doing something wrong
	•	Use db:migrate ALWAYS
	3.	Correct Workflow

vim src/db/schema.ts
bun db:generate
bun db:migrate
git add src/db/schema.ts apps/web/drizzle/
git commit -m "Add X to schema"


	4.	NEVER
	•	Manually edit migration SQL
	•	Touch drizzle/meta/_journal.json
	•	Create migration files by hand
	5.	Before pushing
	•	Migration exists
	•	Migration tested locally
	•	Run: bun check:migrations
	•	Files committed together

Migration Conflicts (Multiple Developers)

When two branches create migrations with the same numeric prefix:
	•	Drizzle does NOT auto-resolve conflicts
	•	The branch merged LATER must renumber its migration
	•	Example: Two 0005_*.sql files → rename one to 0006_*.sql
	•	Update _journal.json tag to match the new filename
	•	NEVER rename a migration already applied to prod

Pre-commit Hook
	•	Automatically checks for duplicate prefixes
	•	Runs on any commit touching apps/web/drizzle/
	•	Enabled via: git config core.hooksPath .githooks (runs on bun install)

CI Check
	•	GitHub Action validates migrations on every PR
	•	Fails if duplicate prefixes detected
	•	Fails if journal and files are out of sync

Red Flags — STOP IMMEDIATELY
	•	Schema changed, no migration
	•	Duplicate migration prefixes (e.g., two 0019_*.sql files)
	•	Out-of-order migrations
	•	Temptation to "just push"
	•	Any drizzle error during deploy
	•	Missing __drizzle_migrations table in database

⸻

Version Synchronization — MANDATORY

All packages in the monorepo MUST maintain synchronized version numbers.

Mismatched versions create release chaos, broken installations, and user confusion.

Iron Rules
	1.	EVERY version bump updates ALL packages
	•	Root package.json
	•	cli/package.json
	•	packages/controller/package.json
	•	packages/landing-page/package.json
	•	packages/worker-installer/package.json
	2.	EVERY version bump updates ALL version constants
	•	cli/src/index.ts (.version())
	•	packages/worker-installer/src/download.ts (VERSION constant)
	3.	EVERY version bump releases synchronized app
	•	Build FreeAgent.app with matching version
	•	Create GitHub release
	•	Publish npm packages
	4.	Correct Workflow

./free-agent/release.sh X.Y.Z
gh release create vX.Y.Z free-agent/FreeAgent.app.tar.gz
cd packages/worker-installer && npm publish
cd cli && npm publish


Pre-commit Hook
	•	Automatically checks version sync before commit
	•	Fails if any package versions don't match
	•	Located in .githooks/pre-commit
	•	Enabled via: git config core.hooksPath .githooks

Test Suite
	•	bun run test:versions - Check version synchronization
	•	Runs in CI on every PR
	•	Blocks merge if versions out of sync

Red Flags — STOP IMMEDIATELY
	•	Package versions don't match
	•	Version constants out of sync with package.json
	•	App release version differs from npm packages
	•	Pre-commit hook skipped or bypassed

⸻

Security Notice (CRITICAL)

AI attribution is FORBIDDEN.

This includes:
	•	Commit messages
	•	PRs
	•	Code comments
	•	Docs
	•	Any repository file

Why: attribution introduces security risk and undermines trust.

⸻

Agent Responsibilities

Agents must:
	•	State assumptions clearly
	•	Flag conflicts with governing docs
	•	Follow shared domain language
	•	Self-correct deviations immediately

⸻

Versioning

This document is version-controlled.
Agents must verify they are using the latest version before generating output.
