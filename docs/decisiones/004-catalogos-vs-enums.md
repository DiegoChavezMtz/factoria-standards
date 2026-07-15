# ADR-004: Catalog tables instead of native enums or free-text values

## Status
Accepted

## Context
Fixed sets of values (status, role, document type, etc.) need to be modeled
somehow in the schema. The three common approaches are:

1. A native database enum type (e.g. Postgres `CREATE TYPE ... AS ENUM`).
2. A free-text or varchar column, optionally with a CHECK constraint.
3. A separate catalog table, referenced via foreign key.

## Decision
We use option 3, catalog tables, for every fixed set of values. Catalog
tables are prefixed `cat_` and minimally include: primary key, `code`
(stable, machine-readable), `label` (human-readable), and `is_active`.

## Rationale

**Native enums are expensive to change.** In Postgres, adding a value to an
enum type is possible but altering or removing one is not straightforward —
it typically requires recreating the type entirely, which means recreating
every column that uses it. In practice this means `ALTER TYPE ... ADD VALUE`
cannot run inside a transaction block with other changes in most Postgres
versions, and any deeper change (renaming, removing, reordering) requires a
maintenance-window-level migration with table locks. For a business rule
that legitimately changes over time — a new order status, a new document
type — this cost is disproportionate to how often "the business changes its
mind" actually happens, which is often.

**Free-text/CHECK constraints push logic into the schema without giving
anything back.** A CHECK constraint listing valid strings has the same
rigidity problem as an enum (changing it is still a schema migration) but
without even the type-safety benefit. It also can't carry metadata — you
can't mark a status "deprecated but keep historical rows," can't add a
display order, can't add a translated label, without further schema
changes.

**Catalog tables make "the business changed its mind" a data change, not a
schema change.** Adding a new order status is an `INSERT`. Deprecating one
without deleting historical references is an `UPDATE ... SET is_active =
false`. This aligns with the Layer Boundaries principle in AGENTS.md: the
set of valid values is business data, not database structure, and treating
it as structure blurs that boundary.

**Catalog tables extend naturally.** Once `cat_status` exists as a real
table, adding `sort_order`, `color`, `description`, or a translations table
keyed to it are all additive changes that don't touch existing data or
require migrations on the referencing tables.

**Cost we accept:** an extra JOIN for anything that wants the human-readable
label, and marginally more setup for a small, truly-never-changing set of
values (e.g. ISO country codes might reasonably be a catalog seeded once and
never touched — still a catalog, for consistency, but low-maintenance).
This cost is consistently smaller than the cost of a locked ALTER TYPE in
production or a CHECK constraint migration under time pressure.

## Consequences
- Every fixed set of values in a new schema is modeled as a `cat_*` table,
  enforced by `validators/check-naming.sql` in CI.
- Referencing tables use a FK to the catalog's primary key.
- Seed data for catalogs ships as part of the migration that creates the
  table (an INSERT immediately following the CREATE TABLE), so the catalog
  is never merged empty.
- Existing enums in legacy schemas are not retroactively migrated unless
  the table they belong to is otherwise being modified — this ADR governs
  new schema design, not a mandatory backfill.

## Alternatives considered
- **Native Postgres enums**: rejected for migration cost, see above.
- **JSONB config document with fixed keys**: rejected — worse than free
  text, since it's neither queryable via FK nor enforces referential
  integrity at all.