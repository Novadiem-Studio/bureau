---
priority: 01
status: idea (pre-spec)
suggested-workflow: feature
suggested-run-slug: self-annealing-failure-loop
---

# 01. Self-annealing failure loop

## One-liner
After a failed operational or runbook run, capture the failure, patch the reusable artifact, retry the smallest representative case, and update docs so the fix survives the session.

## Problem
When an automation or runbook fails, the fix often lives in chat or the immediate code diff — not in the reusable AI layer. The next run hits the same failure. Nothing learns.

## Idea
1. Capture the failure signature and the exact command, tool, or runbook step that failed.
2. Diagnose whether the fault is in the execution script, workflow directive, env/preflight assumption, external service contract, or target code.
3. Patch the right artifact: the tool, script, runbook section, or workflow directive.
4. Retry the smallest representative case to confirm the fix.
5. Update docs, runbook, and/or tests so the fix is durable beyond this session.

## Guardrails
Must not attempt automated retry of steps with external side effects (writes to production, email sends, deploys) without a human gate.

## Likely home
`operational-build` workflow close-out section, a new `runbook-repair` workflow, or a failure-handling subsection in `agents/sysadmin.md`.

## Done when
`RUN_DIR/log.md` records the failure signature and the fix applied. The patched artifact (script, runbook, workflow directive, or doc) is updated. A smoke or regression command exists for the next run. The fix is not buried in `log.md` — it is in the reusable layer.

## Open questions
- Should the loop live as a workflow step, a sysadmin agent sub-task, or a standalone `runbook-repair` workflow?
- How should the framework distinguish transient external failures (network blip) from structural ones worth patching?
