-- validators/check-rls.sql
-- Factoría Standards — RLS enforcement gate
--
-- Fails (raises exception, non-zero exit via psql -v ON_ERROR_STOP=1) if any
-- table in the target schema is missing Row-Level Security or has RLS
-- enabled but zero policies attached (which is just as dangerous — it
-- either blocks all access silently or, if FORCE ROW LEVEL SECURITY isn't
-- set, does nothing at all).
--
-- Usage:
--   psql -v ON_ERROR_STOP=1 -v schema_name="'public'" -f validators/check-rls.sql
--
-- Intended to run against an ephemeral Postgres instance in CI, after all
-- migrations have been applied, before the PR can merge.

DO $$
DECLARE
    schema_to_check text := 'public';  -- override via -v schema_name if needed
    offending_tables text[];
    tables_without_rls text[];
    tables_without_policies text[];
BEGIN
    -- Tables that exist but do NOT have RLS enabled at all
    SELECT array_agg(format('%I.%I', schemaname, tablename))
    INTO tables_without_rls
    FROM pg_tables
    WHERE schemaname = schema_to_check
      AND tablename NOT IN (
          -- add any explicitly exempted infra tables here, e.g. schema_migrations
          'schema_migrations'
      )
      AND NOT EXISTS (
          SELECT 1
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE c.relname = pg_tables.tablename
            AND n.nspname = pg_tables.schemaname
            AND c.relrowsecurity = true
      );

    -- Tables that have RLS enabled but zero policies defined
    -- (silently blocks everything, or does nothing without FORCE RLS —
    -- either way it's not a real, intentional policy and must be flagged)
    SELECT array_agg(format('%I.%I', schemaname, tablename))
    INTO tables_without_policies
    FROM pg_tables t
    WHERE schemaname = schema_to_check
      AND EXISTS (
          SELECT 1
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE c.relname = t.tablename
            AND n.nspname = t.schemaname
            AND c.relrowsecurity = true
      )
      AND NOT EXISTS (
          SELECT 1
          FROM pg_policies p
          WHERE p.schemaname = t.schemaname
            AND p.tablename = t.tablename
      );

    offending_tables := COALESCE(tables_without_rls, '{}') || COALESCE(tables_without_policies, '{}');

    IF array_length(tables_without_rls, 1) > 0 THEN
        RAISE WARNING 'Tables WITHOUT RLS enabled: %', tables_without_rls;
    END IF;

    IF array_length(tables_without_policies, 1) > 0 THEN
        RAISE WARNING 'Tables with RLS enabled but NO policies: %', tables_without_policies;
    END IF;

    IF array_length(offending_tables, 1) > 0 THEN
        RAISE EXCEPTION 'RLS GATE FAILED: % table(s) violate the RLS standard (see warnings above). Every table must have RLS enabled AND at least one policy, per AGENTS.md Database Rules.', array_length(offending_tables, 1);
    ELSE
        RAISE NOTICE 'RLS GATE PASSED: all tables in schema % have RLS enabled with at least one policy.', schema_to_check;
    END IF;
END $$;