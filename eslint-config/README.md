# @factoria/eslint-config

ESLint enforcement of AGENTS.md **Layer Boundaries [HARD]** for JS/TS
projects. This package is the tooling arm of the rule — the rule itself
lives in AGENTS.md; the rationale lives in ADR-003.

## Why this exists

A rule an agent can ignore is a suggestion. This package makes layer
violations a red CI, identical for code written by Claude Code, Codex,
Gemini, or a human.

## Install (from the standards repo, no private registry needed)

    npm install github:<org>/factoria-standards#path:eslint-config

Or with GitHub Packages, per your org setup.

## What it enforces

1. **Directory boundaries**: a layer imports only from the layer directly
   below it. No skipping, no importing upward.
2. **Data-package containment**: DB clients (Supabase, pg, Prisma...) are
   importable ONLY from the bottom layer. Which packages those are is
   decided by each template, not here.
3. **Server-only containment** (optional): packages that must never reach
   browser bundles.

## What it deliberately does NOT contain

- Style rules (quotes, semicolons) — that's Prettier's job, per template.
- Framework rules (React hooks, Next.js) — template concern.
- Any mention of a concrete technology — this package implements the
  PRINCIPLE; templates supply the concrete layers and packages.

## Layer definition contract

The `layers` array is ordered top → bottom, and order IS the dependency
rule. If your project's real structure can't be expressed as ordered
directories, that's a signal the project structure violates ADR-003 —
fix the structure, don't fight the config.