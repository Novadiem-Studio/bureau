---
priority: bundle-01b
status: idea (consolidated)
suggested-workflow: feature
suggested-run-slug: validation-safety-process-gates
source-ideas:
  - source-notes/14-regression-harness-capture.md
  - source-notes/08-representative-case-battle-test-matrix.md
---

# 01b. Validation and safety — process gates

## Purpose

After the damage preventers land, add the promotion and regression protections. These gates
preserve verification work across phases and raise the bar for promoting workflows and prompts
to canon.

## Consolidates

| Source | Role in this bundle |
|---|---|
| `14-regression-harness-capture` | Preserve accepted checks as phase-to-phase regression fixtures. |
| `08-representative-case-battle-test-matrix` | Require representative cases before promoting workflows/prompts to canon. |

## Dependency

Runs after [01a](01a-validation-safety-damage-preventers.md). The regression and battle-test
mechanisms are more useful once preflight artifacts and external-action gates are already in
place.

## What to build

1. Add a lightweight `RUN_DIR/regression/` fixture convention:
   - fixture name;
   - command;
   - expected passing signal;
   - phase introduced;
   - owner workflow/prompt.
2. Add a battle-test matrix convention for promoting framework workflows or prompts to canon.
3. Capture the original `bug-fix` repro as the first regression fixture when a fix is accepted.
4. Add a Challenger check for promotion without a representative-case matrix or explicit waiver.

## Workflow changes

- `execute-plan`: capture regression fixtures after accepted prompts; run prior fixtures before
  the next prompt when practical.
- `bug-fix`: capture the original repro as the first regression fixture when the fix is accepted.
- `docs/conventions.md`: define battle-test and regression fixture formats once.
- `critic.md`: add a check for missing representative cases when a workflow/prompt is promoted
  to canon.

## Done when

- A build phase can preserve at least one regression fixture and the next phase can re-run it.
- Promoting a workflow or prompt to canon requires a representative-case matrix or an explicit
  waiver.

## Risks

- Regression capture can become busywork if fixtures are slow, opaque, or never re-run.
- Battle-test matrices can become padded examples instead of representative cases.
