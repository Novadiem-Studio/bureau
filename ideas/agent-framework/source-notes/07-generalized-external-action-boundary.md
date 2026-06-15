---
priority: 07
status: idea (pre-spec)
suggested-workflow: feature
suggested-run-slug: generalized-external-action-boundary
---

# 07. Generalized external-action boundary

## One-liner
Gate any externally visible action — email, Slack, customer notifications, webhooks — behind the same human-approval boundary that production deployments already require.

## Problem
The framework has a production deployment gate, but it does not consistently apply the same discipline to other externally visible actions. An agent can send an email, post to Slack, or trigger a webhook without an explicit human gate. These actions are often irreversible and visible to people outside the Bureau. The deployment boundary covers one class of risk; this covers the rest.

## Idea
1. Define a canonical list of "external action types" — email/SMS sends, Slack/Discord posts, webhook calls to external services, customer-facing notifications, payment triggers, calendar invites.
2. Add a convention in `agents/orchestrator.md` (and relevant agent files) declaring that no external action may fire without an explicit `[CHECKPOINT] — external action pending` gate.
3. The gate must name: the action type, the target, the content or payload, and the reversibility.
4. Add a workflow step or close-out check that flags any run where an external action fired without a recorded checkpoint.
5. Consider a dry-run mode for external actions during bake-offs or early passes.

## Likely home
Convention in `agents/orchestrator.md` and any agents that can reach external services (`agents/sysadmin.md`, `agents/backend.md`). Possibly a shared `docs/external-action-boundary.md` convention doc.

## Done when
No agent can fire an externally visible action without a `[CHECKPOINT]` gate appearing in `log.md`. A close-out or Challenger check can verify this. Dry-run mode exists for at least email and Slack.

## Open questions
- Should the external action gate be a formal workflow step, or a convention enforced by agent prompts?
- How should the system handle actions that are technically reversible (e.g., draft emails) vs. truly irreversible?
- Does this overlap with or subsume the existing production deployment gate?
