-- validators/check-naming.sql
-- Factoría Standards — catalog naming & shape enforcement gate
--
-- Fails if any table that "looks like" a catalog (fixed set of values
-- referenced by other tables) does not follow the cat_ naming convention,
-- OR if any table actually named cat_* is missing the minimum required
-- columns (code, label, is_active).
--
-- Two checks run here, catching opposite mistakes:
--   (1) A table named cat_* but missing required columns — someone created
--       the catalog but cut corners on its shape.
--   (2) A table that functions as a catalog (small, low churn, referenced
--       by FKs from multiple places) but was NOT named cat_* — someone
--       modeled a catalog without realizing that's what they were doing,
--       or worse, used an enum/free-text instead (see AGENTS.md).
--
-- Check (2) is a heuristic, not a proof — it flags candidates for human
-- judgment rather than hard-failing, since "small reference table" can
-- have legitimate exceptions. Check (1) hard-fails: no excuse for a cat_
-- table missing its required shape.
--
-- Usage:
--   psql -v ON_ERROR_STOP=1 -f validators/check-naming.sql

DO $$
DECLARE
    schema_to_check text := 'public';
    malformed_catalogs text[];
    catalog_candidates text[];
    required_columns text[] := ARRAY['code', 'label', 'is_active'];
    cat_record record;
    missing_cols text[];
BEGIN
    malformed_catalogs := '{}';
    catalog_candidates := '{}';

    -- CHECK 1 (hard fail): every table named cat_* must have the minimum
    -- required columns.
    FOR cat_record IN
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = schema_to_check
          AND tablename LIKE 'cat\_%' ESCAPE '\'
    LOOP
        SELECT array_agg(rc)
        INTO missing_cols
        FROM unnest(required_columns) AS rc
        WHERE NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = schema_to_check
              AND table_name = cat_record.tablename
              AND column_name = rc
        );

        IF missing_cols IS NOT NULL THEN
            malformed_catalogs := malformed_catalogs || format(
                '%I is missing column(s): %s',
                cat_record.tablename,
                array_to_string(missing_cols, ', ')
            );
        END IF;
    END LOOP;

    -- CHECK 2 (soft warning): tables that look like catalogs by shape —
    -- few rows expected, low column count, referenced by at least one FK
    -- from another table — but aren't named cat_*. We can't know row
    -- count pre-data reliably in an empty CI database, so this heuristic
    -- uses structure only: 2-4 columns, one of which is a text/varchar
    -- column that isn't the PK, and it IS the target of at least one FK.
    FOR cat_record IN
        SELECT c.relname AS table_name
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = schema_to_check
          AND c.relkind = 'r'
          AND c.relname NOT LIKE 'cat\_%' ESCAPE '\'
          AND (
              SELECT count(*) FROM information_schema.columns
              WHERE table_schema = schema_to_check AND table_name = c.relname
          ) BETWEEN 2 AND 4
          AND EXISTS (
              -- is referenced by at least one FK elsewhere
              SELECT 1 FROM pg_constraint con
              WHERE con.contype = 'f'
                AND con.confrelid = c.oid
          )
          AND EXISTS (
              -- has a text-like column beyond its PK (smells like a label)
              SELECT 1 FROM information_schema.columns col
              WHERE col.table_schema = schema_to_check
                AND col.table_name = c.relname
                AND col.data_type IN ('character varying', 'text', 'character')
          )
    LOOP
        catalog_candidates := catalog_candidates || cat_record.table_name;
    END LOOP;

    IF array_length(malformed_catalogs, 1) > 0 THEN
        RAISE WARNING 'Malformed cat_ tables: %', malformed_catalogs;
    END IF;

    IF array_length(catalog_candidates, 1) > 0 THEN
        RAISE WARNING 'Tables that look like catalogs but are NOT named cat_*  (review manually): %', catalog_candidates;
    END IF;

    IF array_length(malformed_catalogs, 1) > 0 THEN
        RAISE EXCEPTION 'NAMING GATE FAILED: % cat_ table(s) missing required columns (code, label, is_active). See AGENTS.md Database Rules.', array_length(malformed_catalogs, 1);
    ELSE
        RAISE NOTICE 'NAMING GATE PASSED (hard check). % possible unnamed catalog(s) flagged for manual review — see warnings.', COALESCE(array_length(catalog_candidates, 1), 0);
    END IF;
END $$;