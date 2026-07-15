-- validators/check-fk-indexes.sql
-- Factoría Standards — FK index enforcement gate
--
-- Fails if any foreign key column does not have a supporting index.
-- An FK without an index causes two concrete problems in production:
-- (1) every DELETE/UPDATE on the referenced (parent) table triggers a full
--     table scan on the child table to check for dependent rows, and
-- (2) joins on that FK column are slow at any real data volume.
-- Postgres does NOT create this index automatically — unlike a PRIMARY KEY
-- or UNIQUE constraint, an FK constraint alone creates no index.
--
-- Usage:
--   psql -v ON_ERROR_STOP=1 -f validators/check-fk-indexes.sql
--
-- Intended to run against an ephemeral Postgres instance in CI, after all
-- migrations have been applied, before the PR can merge.

DO $$
DECLARE
    unindexed_fks text[];
    fk_record record;
    is_indexed boolean;
BEGIN
    unindexed_fks := '{}';

    FOR fk_record IN
        SELECT
            con.conname AS constraint_name,
            nsp.nspname AS schema_name,
            rel.relname AS table_name,
            att.attname AS column_name,
            con.conrelid AS table_oid,
            con.conkey AS column_positions
        FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
        JOIN pg_attribute att ON att.attrelid = rel.oid
                               AND att.attnum = ANY(con.conkey)
        WHERE con.contype = 'f'  -- 'f' = foreign key
          AND nsp.nspname = 'public'
    LOOP
        -- Check whether an index exists on this table where the FK column
        -- is the LEADING (first) column of the index — a composite index
        -- with the FK column buried in position 2+ doesn't help the
        -- lookups this rule cares about.
        SELECT EXISTS (
            SELECT 1
            FROM pg_index idx
            WHERE idx.indrelid = fk_record.table_oid
              AND idx.indkey[0] = (
                  SELECT attnum FROM pg_attribute
                  WHERE attrelid = fk_record.table_oid
                    AND attname = fk_record.column_name
              )
        ) INTO is_indexed;

        IF NOT is_indexed THEN
            unindexed_fks := unindexed_fks || format(
                '%I.%I.%I (constraint: %s)',
                fk_record.schema_name,
                fk_record.table_name,
                fk_record.column_name,
                fk_record.constraint_name
            );
        END IF;
    END LOOP;

    IF array_length(unindexed_fks, 1) > 0 THEN
        RAISE WARNING 'Foreign keys WITHOUT a supporting index: %', unindexed_fks;
        RAISE EXCEPTION 'FK INDEX GATE FAILED: % foreign key(s) missing an index (see warnings above). Every FK column needs an explicit index, per AGENTS.md Database Rules.', array_length(unindexed_fks, 1);
    ELSE
        RAISE NOTICE 'FK INDEX GATE PASSED: all foreign keys have a supporting index.';
    END IF;
END $$;