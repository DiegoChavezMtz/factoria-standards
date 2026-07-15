# ADR-003: Strict layer separation — no business logic in the database,
no direct data access from the presentation layer

## Status
Accepted

## Context
Where should business logic and data access live? Common anti-patterns
observed across prior projects (Forge's original schema, early RestartApp
iterations) include: business logic embedded in database functions/triggers,
and UI components calling the data layer (e.g. Supabase client) directly,
bypassing any service layer.

## Decision
- The database enforces data integrity only: constraints, foreign keys,
  RLS, indexes, catalog values. It does not contain business logic
  (no complex trigger-based workflows, no business rules encoded as
  database functions beyond simple integrity checks).
- The presentation/UI layer never accesses the data layer directly. All
  data access flows through a service layer.
- A layer may only depend on the layer directly below it in the stack
  (presentation → service → data access → database). No layer-skipping.

## Rationale

**Business logic in the database is invisible to the tools that reason
about business logic.** Code review, tests, an AI agent reading the
codebase to understand a feature — none of these naturally surface a
trigger buried in a migration file the way they surface a function in
`/services`. Logic hidden in the database becomes logic nobody remembers
exists, discovered only when it fires unexpectedly. This was a concrete,
observed problem in Forge's original schema and is the direct motivation
for this rule.

**A service layer is what makes "which agent wrote this" not matter.**
If Claude Code writes a component this week and Codex writes another
next week, both calling the same service functions, the business logic
stays consistent and in one place regardless of who or what generated the
surrounding code. If instead each agent is free to call the data layer
directly from wherever it's convenient, business logic drifts and
duplicates across the codebase in ways that are hard to detect until they
disagree with each other.

**Strict downward-only dependency makes the system predictable to change.**
If presentation can only reach data through service, then changing how data
is stored or fetched never requires touching UI code — only the service
layer's implementation. This isolation is what makes it safe for an agent
to work on one layer without needing full context of the others, which
directly enables the parallel, multi-agent execution model (Claude
planning, Codex/Claude Code executing) this whole standard is built around.

**Cost we accept:** an extra layer of indirection for even simple CRUD
operations, and more files/boilerplate than "just query it inline." We
accept this because the alternative — logic scattered across whichever
layer felt convenient at generation time — is exactly the kind of
architectural drift that makes a system impossible to maintain once
multiple agents and humans are producing code in parallel, which is the
core risk this whole standards effort exists to prevent.

## Consequences
- New projects scaffold a service layer from the template
  (`factoria-template-*`) from day one; it is not optional or added later.
- Database functions/triggers are limited to integrity concerns (e.g.
  `updated_at` timestamps, simple validation) — anything resembling a
  business rule ("if status changes to X, also update Y") belongs in the
  service layer, not a trigger.
- Enforcement of the layer boundary itself is technology-specific (ESLint
  import restrictions for JS/TS, ArchUnit for Java, etc.) and lives in each
  `factoria-template-*`, not in this repo — but the *principle* is governed
  here and cannot be weakened by a template.

## Alternatives considered
- **Fat models / logic in database functions**: rejected per Rationale
  above; concrete prior failure case in Forge's original schema.
- **No enforced layer, agent discretion per task**: rejected as
  incompatible with multi-agent, multi-human parallel execution — the
  whole point of the boundary is that no one needs full-system context to
  work safely on one part of it.