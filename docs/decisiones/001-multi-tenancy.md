# ADR-001: Shared-schema multi-tenancy with tenant key + RLS

## Status
Accepted

## Context
A platform serving multiple clients/organizations needs to decide how
tenant data is isolated. The three common approaches are:

1. Database-per-tenant (fully isolated physical databases).
2. Schema-per-tenant (one Postgres schema per tenant, shared database).
3. Shared schema, shared tables, with a tenant key column on every table
   and row-level isolation enforced by the database itself.

## Decision
We use option 3: shared schema, shared tables, every multi-tenant table
carries a tenant key column (e.g. `org_id`), and isolation is enforced via
Row-Level Security (see ADR-002), not by application code alone.

## Rationale

**Database-per-tenant and schema-per-tenant both fail to scale
operationally**, independent of data volume. Every migration has to run N
times instead of once. Every schema change has to be verified against every
tenant's copy. Connection pooling gets harder as tenant count grows — each
schema/database needs its own connections or a much more complex routing
layer. For a consultancy building multiple client platforms with a small
team, this operational multiplication is the real cost, not disk space or
query performance.

**Shared schema keeps the system as one thing to reason about, migrate, and
monitor.** One set of migrations, one CI pipeline, one place to look for
"what does the schema look like." This directly supports the goal of a
small team producing multiple products without the maintenance burden
scaling linearly with tenant count.

**Isolation must live in the database, not only in application code.**
Relying on "every query includes `WHERE org_id = ?`" as an application-level
convention is a single missed WHERE clause away from a cross-tenant data
leak — and that mistake is exactly the kind an AI agent under time pressure
can make without noticing. RLS (ADR-002) makes the database itself refuse
to return rows outside the current tenant context, regardless of what the
application layer forgot to filter.

**Cost we accept:** shared-schema multi-tenancy means a single noisy
tenant can affect performance for others without careful indexing (tenant
key must be part of most indexes), and a catastrophic bug in RLS policy
logic is a bigger blast radius than a single tenant's isolated database.
We accept this because rigorous RLS + FK indexing (ADR-002, this repo's
`check-fk-indexes.sql`) directly mitigates both risks, and the operational
cost of the alternatives is worse for our scale and team size.

## Consequences
- Every multi-tenant table has a tenant key column, non-nullable, indexed.
- Every multi-tenant table has RLS enabled with a policy that filters by
  tenant key, enforced by `validators/check-rls.sql`.
- Tenant key is set from the authenticated session context, never accepted
  as a client-supplied value.
- If a table is later found to be shared across tenants by design (e.g. a
  true global catalog), it is explicitly exempted from the tenant-key
  requirement and documented as such, not silently missing the column.

## Alternatives considered
- **Database-per-tenant**: rejected for migration/operational overhead
  at our team scale.
- **Schema-per-tenant**: rejected for the same reason, with the added
  complexity of schema-qualified queries and per-schema permissions.