---
priority: bundle-04-followup
status: idea (open)
suggested-workflow: execute-plan
suggested-run-slug: account-run-committed-regression-suite
source: Codex external review of the Bundle 04 build (P2#4), 2026-06-20
---

# 10. A committed regression suite for `account-run.sh`

## Purpose

Bundle 04 shipped `scripts/account-run.sh` to canon, but its battle-test (the 17-case
fixture suite + `setup-fixtures.sh`) lives in the run dir under `output/runs/<slug>/regression/`,
which is gitignored. So the suite is **run-local evidence**, not durable automation: a future
edit to `account-run.sh` has no committed test to re-run, and the suite can't be reproduced on
another machine after the run dir is gone.

This follow-up relocates the suite into a committed location so the script carries its own
regression coverage.

## Why this wasn't done in Bundle 04

The Bundle 04 plan deliberately scoped the battle-test as run-local (the framework's normal
model: fixtures are run artifacts, and that run declared `Promotion to canon: no`). The
external review (Codex P2#4) flagged that a new *durable* script with only run-local tests is a
gap. `setup-fixtures.sh` (added in the same run) made the suite re-runnable *while the run dir
exists* and byte-stable across runs — but it still lives in gitignored `output/`. Closing the
"travels with the script / any machine" gap is this separate piece of work.

## First implementation slice

1. Choose a committed home — e.g. `scripts/tests/account-run/` (mirrors `scripts/`), holding:
   - `setup-fixtures.sh` (already written; pin to a fixed temp root, not `/tmp/af-accounting-fixtures`
     hardcoded, so it's relocatable) — generates byte-stable inputs (the stale-snapshot polledAt is
     already a fixed far-past timestamp, no per-second drift).
   - the fixture assertions, as a runnable harness (a `run.sh` that runs setup then each case and
     reports pass/fail), not 17 prose `.md` files — prose fixtures are the run-local convention; a
     committed suite wants an executable runner.
2. Decide the relationship to the run-local fixture convention (`docs/conventions.md § Regression
   fixture file format`): the committed suite is the script's *own* tests; the run-local fixtures
   stay the per-run gate. Don't duplicate intent — name which is authoritative for `account-run.sh`.
3. Wire it so it can run in one command (`bash scripts/tests/account-run/run.sh`) and, optionally,
   from a future framework self-test entry point.

## Done when

- Editing `scripts/account-run.sh` and running one committed command re-runs the full battle-test
  (the 17 cases incl. the corrupt-file / non-object guards, two-pass ordering, run_date calendar
  validation, memory scenarios) with a clear pass/fail.
- The suite runs on a clean checkout with no surviving run dir.
- The suite stays byte-stable run to run (no time-relative inputs).

## Carried sibling follow-up (not this work)

- **Bash 3.2 `set -u` empty-array note → `novadiem-engineering` skill.** During the Bundle 04
  build the coder hit (and guarded) the trap that expanding an empty array with `${arr[*]}` /
  `${arr[@]}` under `set -u` throws "unbound variable". It's a reusable shell-portability lesson
  worth a line in the engineering skill's shell section. Small, separate; carried, not opened.

## Risks

- Don't let a committed suite and the run-local fixture convention drift into two sources of
  truth for the same behavior — name one authoritative per surface.
- Keep it Bash 3.2 / macOS portable (the script's target host); no GNU-only `date`, no `declare -A`.
