# AGENTS.md — Factoría Standards

## Purpose
This file defines non-negotiable rules for any AI agent (Claude Code, Codex,
Gemini CLI, or other) working on projects governed by this standard. These
rules apply on top of any tech-specific AGENTS.md in the project template.
When in conflict, the project-level file may add rules but MUST NOT override
rules marked [HARD] here.

## Stack & Scope
This document is technology-agnostic. It governs architecture principles and
workflow, not syntax. Tech-specific implementation lives in the project's own
AGENTS.md (inherited from a factoria-template-*).

## Layer Boundaries [HARD]
- Business logic NEVER lives in the database. The database enforces data
  integrity (constraints, RLS, FKs) and nothing else. (ADR-003)
- UI/presentation layer NEVER calls the data layer directly. All data access
  goes through a service layer. (ADR-003)
- A layer may only depend on the layer directly below it. No skipping layers.
- If a task requires violating a layer boundary to be "faster," stop and flag
  it for human review instead of proceeding.

## Database Rules [HARD]
- Every multi-tenant table includes a tenant key (e.g. `org_id`) and a
  Row-Level Security policy created in the SAME migration that creates the
  table. No table ships without RLS. (ADR-001, ADR-002)
- Every foreign key column has an explicit index created alongside it.
- Every column that should be unique has an explicit UNIQUE constraint —
  never enforced only in application code.
- Fixed sets of values are NEVER modeled as native enum types (e.g. Postgres
  ENUM) or as free-text/check-constraint strings. They are modeled as a
  catalog table. (ADR-004)
  - Catalog tables are prefixed `cat_` (e.g. `cat_status`, `cat_role`,
    `cat_document_type`).
  - Referencing tables use a FK to the catalog's primary key, never a raw
    string or magic value.
  - A catalog table minimally includes: primary key, `code` (stable,
    machine-readable), `label` (human-readable), and `is_active`.
  - Adding or deactivating a value is a data change (INSERT/UPDATE), never a
    schema migration.
- No unbounded JSONB arrays for data that grows with usage. If data grows
  over time, it gets its own table with proper relations.
- Tenant identifiers are never denormalized redundantly across tables when a
  join or view can derive them.
- Migrations are numbered sequentially and idempotent (safe to re-run).
  Never edit a migration that has already been merged to main — write a new
  one.
- Schema changes are proposed by the agent but require explicit human
  approval before the migration is merged. No exceptions.

## Workflow
- Every unit of work starts as a GitHub Issue using the `actividad` or
  `epica` template. No issue, no work.
- One branch per issue: `type/issue-number-short-description`
  (e.g. `feat/42-user-onboarding-flow`).
- Every PR references its issue (`closes #N`) and stays within that issue's
  declared scope. Scope creep goes into a new issue, not the same PR.
- CI must pass (lint, typecheck, tests, db-gate) before merge. No merging on
  red CI, no exceptions, no "I'll fix it after."
- Before finishing a task, the agent runs the project's lint and test
  commands locally/in-sandbox and fixes failures it caused.

## Human Gates [HARD]
The following ALWAYS require human review and approval, regardless of which
agent generated the change:
- Any file under `/migrations` or equivalent schema-change directory.
- Any file under `/services/auth` or equivalent authentication/authorization
  logic.
- Any change to this file (AGENTS.md) or any file in the standards repo.
- Any change to RLS policies.
- Any dependency addition to package.json/pom.xml/etc. that isn't already
  in the project's approved list.
CODEOWNERS in each project enforces this automatically via required reviews.

## Prohibited Patterns
- Do not write raw SQL string concatenation for queries with user input.
- Do not disable RLS "temporarily" for debugging in any environment that
  isn't strictly local.
- Do not model a fixed set of values as an enum type or a bare string —
  use a catalog table (`cat_*`), per Database Rules above.
- Do not introduce a new architectural pattern (state management library,
  ORM, auth approach) without a corresponding ADR in docs/decisiones/.
- Do not commit secrets, API keys, or credentials, even in comments or
  example files.
- Do not mark a task complete if tests were skipped, commented out, or
  weakened to pass.

## Reference
Full rationale for each [HARD] rule is documented in docs/decisiones/ (ADRs).
Agents do not need to read these; humans onboarding to the team should.