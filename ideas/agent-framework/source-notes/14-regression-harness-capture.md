---
priority: 14
status: idea (pre-spec)
suggested-workflow: feature
suggested-run-slug: regression-harness-capture
---

# 14. Regression harness capture

## One-liner
After each accepted implementation phase, preserve the E2E and smoke checks as lasting regression fixtures — not a one-off run that gets discarded after the phase closes.

## Problem
After a build phase is accepted, the smoke or E2E checks used to verify it are often discarded or left as ad hoc commands in `log.md`. The next phase can break the previous one without a fast signal. There is no regression harness that accumulates across phases.

## Idea
1. At the close of each accepted build phase, capture the verification commands or tests used into a `regression/` directory in the run dir or the target repo.
2. Each fixture records: what it tests, the command to run it, what a passing result looks like, and which phase it was introduced in.
3. Add a step in the next phase's setup: run the regression fixtures from prior phases before starting the new build.
4. Fixtures that fail on a re-run block the next phase from starting until the regression is understood.
5. Over time, accumulate fixtures into a project-level regression suite that outlives the run.

## Likely home
`execute-plan` workflow, phase acceptance step. Regression fixtures live in `RUN_DIR/regression/` and, eventually, in the target project's test directory. The Mechanic or Spellwright captures the fixture at phase close.

## Done when
After phase 1 is accepted, running the regression suite before phase 2 starts takes less than 2 minutes and catches any regression introduced during phase 2 work. Fixtures are human-readable (not opaque scripts). A passing regression run is logged in `log.md` before phase 2 begins.

## Open questions
- Should fixtures live in the run dir, the target project, or both?
- How should the system handle fixtures that are inherently slow (full E2E browser tests)?
- Who owns fixture maintenance when a deliberate breaking change makes an old fixture wrong?
