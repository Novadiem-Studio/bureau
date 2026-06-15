---
priority: bundle-01
status: idea (consolidated)
suggested-workflow: feature
suggested-run-slug: validation-and-safety-foundation
source-ideas:
  - source-notes/13-env-preflight-before-execution.md
  - source-notes/14-regression-harness-capture.md
  - source-notes/08-representative-case-battle-test-matrix.md
  - source-notes/07-generalized-external-action-boundary.md
---

# 01. Validation and safety foundation

## Purpose

Install the cheap gates that prevent preventable failures, lost verification work, and
externally visible mistakes. This bundle comes first because it reduces the risk of every
later bundle.

## Consolidates

| Source | Role in this bundle |
|---|---|
| `13-env-preflight-before-execution` | Fail fast before build-party or runbook execution starts. |
| `14-regression-harness-capture` | Preserve accepted checks as phase-to-phase regression fixtures. |
| `08-representative-case-battle-test-matrix` | Require representative cases before promoting workflows/prompts to canon. |
| `07-generalized-external-action-boundary` | Add a human gate for email, Slack, webhooks, notifications, payments, and other irreversible external actions. |

## Why first

These ideas are not speculative. They are guardrails around work the framework already does:
execute plans, run operations, promote prompts, and stop at production boundaries. They can be
implemented incrementally, mostly through workflow text, a small script, and conventions.

## Phase 1a - damage preventers

Ship the highest-blast-radius guardrails first:

1. Add a canonical `docs/external-action-boundary.md`.
2. Teach `agents/orchestrator.md`, `agents/sysadmin.md`, and `workflows/execute-plan.md` that
   external actions require an `[EXTERNAL-ACTION CHECKPOINT]` gate.
3. Add `scripts/preflight.sh` with a narrow v1:
   - reads `.env.example` when present;
   - rejects missing required values;
   - rejects obvious placeholders such as `your-key-here`, `changeme`, and empty values;
   - prints an explicit "no `.env.example` found - nothing to validate" line and exits 0
     when no env example exists;
   - writes or prints a result that the Conductor can copy to `RUN_DIR/preflight.md`.

Do not build a full service reachability framework in v1. Token validation, pings, and
provider-specific probes can come after the basic preflight path is used in real runs.

### Phase 1a workflow changes

- `execute-plan`: run preflight after the gate/worktree boundary and before the build party
  starts.
- `operational-build`: run preflight after loading the runbook and before the Mechanic acts.
- `critic.md`: add a check for missing external-action gates where a workflow/prompt performs
  an outward irreversible action.

### Phase 1a done when

- A missing, empty, or placeholder env var fails before any build-party agent starts.
- Running preflight without `.env.example` exits 0 but prints an explicit "nothing to validate"
  line; it does not produce a silent green.
- No externally visible action is allowed without a logged checkpoint naming the target,
  payload/content, reversibility, and human approval.

## Phase 1b - process gates

After Phase 1a lands, add the promotion and regression protections:

1. Add a lightweight `RUN_DIR/regression/` fixture convention:
   - fixture name;
   - command;
   - expected passing signal;
   - phase introduced;
   - owner workflow/prompt.
2. Add a battle-test matrix convention for promoting framework workflows or prompts to canon.
3. Capture the original `bug-fix` repro as the first regression fixture when a fix is accepted.
4. Add a Challenger check for promotion without a representative-case matrix or explicit waiver.

### Phase 1b workflow changes

- `execute-plan`: capture regression fixtures after accepted prompts; run prior fixtures before
  the next prompt when practical.
- `bug-fix`: capture the original repro as the first regression fixture when the fix is accepted.
- `docs/conventions.md`: define battle-test and regression fixture formats once.
- `critic.md`: add a check for missing representative cases when a workflow/prompt is promoted
  to canon.

## Done when

- Phase 1a damage-preventer tests pass.
- A build phase can preserve at least one regression fixture and the next phase can re-run it.
- Promoting a workflow or prompt to canon requires a representative-case matrix or an explicit
  waiver.

## Risks

- Preflight can become fake safety if it passes on placeholders or vague checks.
- Regression capture can become busywork if fixtures are slow, opaque, or never re-run.
- Battle-test matrices can become padded examples instead of representative cases.
- External-action gates must cover non-deploy actions without weakening the existing
  production boundary.
