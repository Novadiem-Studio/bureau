---
priority: bundle-01a
status: idea (consolidated)
suggested-workflow: feature
suggested-run-slug: validation-safety-damage-preventers
source-ideas:
  - source-notes/13-env-preflight-before-execution.md
  - source-notes/07-generalized-external-action-boundary.md
---

# 01a. Validation and safety — damage preventers

## Purpose

Ship the highest-blast-radius guardrails first. A missing env var or an ungated external
action can cause irreversible damage on the very next run. These two mechanisms are cheap to
add and reduce the risk of every later bundle.

## Consolidates

| Source | Role in this bundle |
|---|---|
| `13-env-preflight-before-execution` | Fail fast before build-party or runbook execution starts. |
| `07-generalized-external-action-boundary` | Add a human gate for email, Slack, webhooks, notifications, payments, and other irreversible external actions. |

## Why first

These are guardrails around work the framework already does: execute plans, run operations,
and stop at production boundaries. They can be implemented incrementally, mostly through
workflow text, a small script, and conventions.

## What to build

1. Add a canonical `docs/external-action-boundary.md` that enumerates the taxonomy of
   external actions: email, Slack, webhooks, notifications, payments, DNS changes, and any
   outbound POST with side effects. Include a default rule: **when unsure, treat as external
   and gate it.** The boundary is not self-evident — concrete enumeration prevents
   inconsistent application.
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

## Workflow changes

- `execute-plan`: run preflight after the gate/worktree boundary and before the build party
  starts.
- `operational-build`: run preflight after loading the runbook and before the Mechanic acts.
- `critic.md`: add a check for missing external-action gates where a workflow/prompt performs
  an outward irreversible action.

## Done when

- A missing, empty, or placeholder env var fails before any build-party agent starts.
- Running preflight without `.env.example` exits 0 but prints an explicit "nothing to validate"
  line; it does not produce a silent green.
- No externally visible action is allowed without a logged checkpoint naming the target,
  payload/content, reversibility, and human approval.

## Risks

- Preflight can become fake safety if it passes on placeholders or vague checks.
- External-action gates must cover non-deploy actions without weakening the existing
  production boundary.
