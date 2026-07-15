# ADR-002: Row-Level Security is mandatory on every multi-tenant table

## Status
Accepted

## Context
Given shared-schema multi-tenancy (ADR-001), tenant isolation has to be
enforced somewhere. The candidates are: application-code discipline (every
query manually scoped), a middleware/ORM layer that injects tenant
filtering automatically, or database-native Row-Level Security.

## Decision
Row-Level Security is mandatory on every multi-tenant table, created in the
same migration that creates the table. No table ships without it. This is
enforced by `validators/check-rls.sql` in CI and cannot be bypassed by any
agent or human without an explicit, reviewed exception.

## Rationale

**Application-level filtering is a convention, not a guarantee.** It works
exactly as well as the discipline of every person and every agent writing
every query, forever, without exception. One new endpoint, one raw query
for a report, one AI agent generating a "quick" admin script — any of these
can miss the tenant filter, and the failure mode is silent: it doesn't
crash, it just leaks another tenant's data. This is precisely the failure
mode that concerns us most about AI-generated code at speed: an agent
optimizing for "make the feature work" has no innate signal that it forgot
tenant scoping, because the query still returns valid-looking data.

**RLS moves the guarantee to a layer the application cannot forget to
apply.** Once a policy exists, every query — from the application, from a
migration script, from a human running ad-hoc SQL, from an agent debugging
in a shell — is filtered by Postgres itself before rows are returned. The
guarantee no longer depends on every call site remembering to do the right
thing.

**RLS is enforced at CREATE time, not retrofitted.** Requiring the policy
in the same migration as the table (rather than "add RLS later, it's on
the backlog") closes the actual window where leaks happen in practice: the
period between a table existing and someone remembering to secure it. In a
fast-moving, AI-assisted workflow, that window can otherwise be minutes,
and minutes are enough for the table to be queried in production.

**Cost we accept:** RLS policies add a small amount of query planning
overhead, and debugging "why did this query return zero rows" occasionally
means checking policy logic instead of just the query. We accept this
because the alternative failure mode — silent cross-tenant data exposure —
is categorically worse than a slower or momentarily confusing query.

## Consequences
- `ENABLE ROW LEVEL SECURITY` and at least one `CREATE POLICY` are required
  in the same migration file that creates any multi-tenant table.
- Policies filter by the tenant key established in ADR-001, sourced from
  session/auth context, never from a client-supplied parameter.
- CI (`check-rls.sql`) fails the build for any table missing RLS or missing
  policies, no exceptions without a documented, reviewed override.
- Disabling RLS "temporarily" outside of a strictly local environment is
  explicitly prohibited (see AGENTS.md, Prohibited Patterns).

## Alternatives considered
- **ORM-level automatic scoping** (e.g. a base repository class that always
  injects `WHERE org_id = ?`): rejected as the sole mechanism because it
  only protects queries that go through that ORM layer — raw SQL, scripts,
  and other tools bypass it entirely. Can be used as a *second*, redundant
  layer of defense, but not as a replacement for RLS.
- **Manual query discipline + code review**: rejected as insufficient given
  the scale and speed of AI-assisted development this standard is designed
  for.