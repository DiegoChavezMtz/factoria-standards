#!/usr/bin/env bash
# validators/check-migrations.sh
# Factoría Standards — migration hygiene gate
#
# Validates three rules from AGENTS.md (Database Rules):
#   1. SEQUENTIAL NUMBERING: migration filenames start with a numeric
#      prefix, unique and strictly increasing, no duplicates, no gaps*.
#      (*gaps produce a warning, not a failure — deleted/squashed history
#      can legitimately leave gaps; duplicates always fail.)
#   2. NO EDITING MERGED MIGRATIONS: any migration file that already exists
#      on the base branch (e.g. main) must be byte-identical in this PR.
#      New files are fine; modified or deleted existing ones fail.
#   3. BASIC IDEMPOTENCY SIGNALS: heuristic check that CREATE/ALTER
#      statements use guards (IF NOT EXISTS / IF EXISTS / OR REPLACE).
#      Warning only — true idempotency can't be proven by grep, and the
#      real test is db-gate applying all migrations from scratch.
#
# Usage:
#   ./validators/check-migrations.sh <migrations_path> [base_ref]
#   e.g. ./validators/check-migrations.sh ./supabase/migrations origin/main
#
# Exit codes: 0 = pass, 1 = hard failure.
# Requires: git history available (fetch-depth: 0 in CI checkout).

set -euo pipefail

MIGRATIONS_PATH="${1:?Usage: check-migrations.sh <migrations_path> [base_ref]}"
BASE_REF="${2:-origin/main}"

FAILURES=0
WARNINGS=0

fail() { echo "::error::$1"; FAILURES=$((FAILURES + 1)); }
warn() { echo "::warning::$1"; WARNINGS=$((WARNINGS + 1)); }
note() { echo "$1"; }

if [ ! -d "$MIGRATIONS_PATH" ]; then
  fail "Migrations path '$MIGRATIONS_PATH' does not exist."
  exit 1
fi

# Collect migration files, sorted
mapfile -t MIGRATION_FILES < <(find "$MIGRATIONS_PATH" -maxdepth 1 -name "*.sql" -type f | sort)

if [ "${#MIGRATION_FILES[@]}" -eq 0 ]; then
  note "No migration files found in $MIGRATIONS_PATH — nothing to check."
  exit 0
fi

# ---------------------------------------------------------------
# CHECK 1: Sequential numbering
# ---------------------------------------------------------------
note "── Check 1: sequential numbering ──"

declare -A SEEN_NUMBERS
PREV_NUM=-1

for filepath in "${MIGRATION_FILES[@]}"; do
  filename=$(basename "$filepath")

  # Must start with a numeric prefix followed by a separator
  if [[ ! "$filename" =~ ^([0-9]+)[_-] ]]; then
    fail "Migration '$filename' does not start with a numeric prefix (expected e.g. '0042_add_users.sql')."
    continue
  fi

  num=$((10#${BASH_REMATCH[1]}))  # 10# forces base-10 (avoids octal on leading zeros)

  if [[ -n "${SEEN_NUMBERS[$num]:-}" ]]; then
    fail "Duplicate migration number $num: '${SEEN_NUMBERS[$num]}' and '$filename'. Two agents/branches likely created migrations in parallel — renumber one."
  fi
  SEEN_NUMBERS[$num]="$filename"

  if [ "$num" -le "$PREV_NUM" ] && [ "$PREV_NUM" -ne -1 ]; then
    fail "Migration numbering not strictly increasing at '$filename' (got $num after $PREV_NUM)."
  elif [ "$PREV_NUM" -ne -1 ] && [ "$num" -ne $((PREV_NUM + 1)) ]; then
    warn "Gap in migration numbers: $PREV_NUM → $num (OK if history was squashed; verify it's intentional)."
  fi

  PREV_NUM=$num
done

# ---------------------------------------------------------------
# CHECK 2: No editing of already-merged migrations
# ---------------------------------------------------------------
note "── Check 2: merged migrations are immutable ──"

if git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then

  # Files that existed on base and were MODIFIED in this branch
  while IFS= read -r changed; do
    [ -z "$changed" ] && continue
    fail "Migration '$changed' already exists on $BASE_REF but was MODIFIED. Never edit a merged migration — write a new one (AGENTS.md, Database Rules)."
  done < <(git diff --name-only --diff-filter=M "$BASE_REF"...HEAD -- "$MIGRATIONS_PATH/*.sql" 2>/dev/null || true)

  # Files that existed on base and were DELETED in this branch
  while IFS= read -r deleted; do
    [ -z "$deleted" ] && continue
    fail "Migration '$deleted' exists on $BASE_REF but was DELETED in this branch. Merged migrations are immutable history."
  done < <(git diff --name-only --diff-filter=D "$BASE_REF"...HEAD -- "$MIGRATIONS_PATH/*.sql" 2>/dev/null || true)

else
  warn "Base ref '$BASE_REF' not found — skipping immutability check. In CI, ensure checkout uses fetch-depth: 0."
fi

# ---------------------------------------------------------------
# CHECK 3: Idempotency signals (heuristic, warnings only)
# ---------------------------------------------------------------
note "── Check 3: idempotency signals (heuristic) ──"

for filepath in "${MIGRATION_FILES[@]}"; do
  filename=$(basename "$filepath")

  # CREATE TABLE without IF NOT EXISTS
  if grep -qiE 'CREATE[[:space:]]+TABLE[[:space:]]+(?!IF[[:space:]]+NOT[[:space:]]+EXISTS)' "$filepath" 2>/dev/null; then
    if grep -qiE 'CREATE[[:space:]]+TABLE' "$filepath" && ! grep -qiE 'CREATE[[:space:]]+TABLE[[:space:]]+IF[[:space:]]+NOT[[:space:]]+EXISTS' "$filepath"; then
      warn "'$filename': CREATE TABLE without IF NOT EXISTS — re-running this migration will fail."
    fi
  fi

  # CREATE INDEX without IF NOT EXISTS
  if grep -qiE 'CREATE[[:space:]]+(UNIQUE[[:space:]]+)?INDEX' "$filepath" && ! grep -qiE 'CREATE[[:space:]]+(UNIQUE[[:space:]]+)?INDEX[[:space:]]+(CONCURRENTLY[[:space:]]+)?IF[[:space:]]+NOT[[:space:]]+EXISTS' "$filepath"; then
    warn "'$filename': CREATE INDEX without IF NOT EXISTS — re-running this migration will fail."
  fi

  # DROP without IF EXISTS
  if grep -qiE 'DROP[[:space:]]+(TABLE|INDEX|POLICY|FUNCTION|TYPE)[[:space:]]' "$filepath" && ! grep -qiE 'DROP[[:space:]]+(TABLE|INDEX|POLICY|FUNCTION|TYPE)[[:space:]]+IF[[:space:]]+EXISTS' "$filepath"; then
    warn "'$filename': DROP without IF EXISTS — re-running this migration will fail."
  fi
done

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
if [ "$FAILURES" -gt 0 ]; then
  echo "::error::MIGRATION GATE FAILED: $FAILURES hard failure(s), $WARNINGS warning(s)."
  exit 1
else
  echo "MIGRATION GATE PASSED: 0 failures, $WARNINGS warning(s)."
  exit 0
fi