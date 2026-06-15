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

## First implementation slice

Build only the minimum useful foundation:

1. Add a canonical `docs/external-action-boundary.md`.
2. Teach `agents/orchestrator.md`, `agents/sysadmin.md`, and `workflows/execute-plan.md` that
   external actions require a `[CHECKPOINT] - external action pending` gate.
3. Add `scripts/preflight.sh` with a narrow v1:
   - reads `.env.example` when present;
   - rejects missing required values;
   - rejects obvious placeholders such as `your-key-here`, `changeme`, and empty values;
   - writes or prints a result that the Conductor can copy to `RUN_DIR/preflight.md`.
4. Add a lightweight `RUN_DIR/regression/` fixture convention:
   - fixture name;
   - command;
   - expected passing signal;
   - phase introduced;
   - owner workflow/prompt.
5. Add a `battle-test.md` convention for promoting framework workflows or prompts to canon.

Do not build a full service reachability framework in v1. Token validation, pings, and
provider-specific probes can come after the basic preflight path is used in real runs.

## Workflow changes

- `execute-plan`: run preflight before the build party starts; capture regression fixtures
  after accepted prompts; run prior fixtures before the next prompt when practical.
- `operational-build`: run preflight after loading the runbook and before the Mechanic acts.
- `bug-fix`: capture the original repro as the first regression fixture when the fix is
  accepted.
- `docs/conventions.md`: define battle-test and regression fixture formats once.
- `critic.md`: add checks for missing external-action gates and missing representative cases
  when a workflow/prompt is being promoted.

## Done when

- A missing or placeholder env var fails before any build-party agent starts.
- A build phase can preserve at least one regression fixture and the next phase can re-run it.
- Promoting a workflow or prompt to canon requires a representative-case matrix or an explicit
  waiver.
- No externally visible action is allowed without a logged checkpoint naming the target,
  payload/content, reversibility, and human approval.

## Risks

- Preflight can become fake safety if it passes on placeholders or vague checks.
- Regression capture can become busywork if fixtures are slow, opaque, or never re-run.
- Battle-test matrices can become padded examples instead of representative cases.
- External-action gates must cover non-deploy actions without weakening the existing
  production boundary.

