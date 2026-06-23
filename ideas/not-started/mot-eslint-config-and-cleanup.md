# M.O.T.: commit an ESLint config + drop an unused import

**Priority:** low — small cleanup. Makes `npm run lint` a usable, non-interactive gate.
**Scope:** `mot/` web app only. Config + one-line source fix.

## Context — why do this

Surfaced by the Rheo Memory Track 3 run (`20260622-rheo-memory-track3`). The integration gate
couldn't run `npm run lint` as a clean check: **the repo ships no committed ESLint config**
(`.eslintrc*` / `eslint.config.*` absent and untracked on every branch), so `next lint` drops
into interactive first-time setup. That makes lint unrunnable in CI/automation and skipped by
the build gate today.

Separately, with a strict config applied ad hoc, the only error in MOT's own code is **one
unused import** in `components/FilterChips.tsx` (the `Status` import, ~line 14). Both predate
Track 3 and were left untouched per the run's "surface, don't fix unrelated pre-existing
failures" rule.

## What to do (MVP)

1. Add a committed ESLint config appropriate for a Next.js 14 / TypeScript-strict project
   (the `next/core-web-vitals` + `@typescript-eslint` baseline `next lint` would scaffold), so
   `npm run lint` runs non-interactively and exits cleanly.
2. Remove the unused `Status` import from `components/FilterChips.tsx`.
3. Confirm `npm run lint` exits 0 on a clean tree; wire it into the check gate if not already.

## Out of scope
- A repo-wide lint-and-fix sweep. Land the config + the one known error; broader lint debt is a
  separate pass if it surfaces.

## Workflow
`bug-fix` (or a quick direct cleanup) — tiny, self-contained; stop at dev.
