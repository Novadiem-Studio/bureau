# Agentic workflow video ledger

Running notes from outside workflow videos. This is not a source of truth for framework
mechanics; it is a holding pen for patterns worth stealing, checking against what the Bureau
already does, and either integrating or rejecting.

## Status key

- **Integrated** — already added to framework mechanics or docs.
- **Covered** — the framework already has the idea in stronger form.
- **Candidate** — worth considering in a future pass.
- **Reject** — useful for the presenter, not worth canonizing here.

---

## Merlin AI — The Agentic Engineer Workflow You Need In 2026

Useful signal:
- Bounded parallelism: run only as many active streams as can be reviewed with care.
- Tier work by effort: cheap/standard for scouts and routine work, strong/frontier for judgment.
- Use worktrees for independent implementation streams.
- Keep AI-generated diffs small enough for real review.
- Use AI review before PR, but never as a replacement for human review.
- Prefer boring CLIs for common services; use MCP/skills for specialized internal systems or docs.

Framework mapping:
- **Integrated:** parallelism budget, context hygiene, tool-fit guidance, reviewable-change-size
  gates, `Reviewability:` prompt metadata, build-party `Review size` handoffs, standalone
  `code-review` workflow.
- **Covered:** model routing, Scoot/Tally utility agents, fresh-context Challenger, worktree docs.

## Merlin AI — How to Build $10,000 Agentic Workflows

Useful signal:
- Agentic build, deterministic runtime: agents are best during construction/debugging; deployed
  workflows should be predictable.
- Battle-test automations before trusting them.
- Keep workflow / agent / tool boundaries explicit.
- Gate externally visible actions such as sends and publishes.
- Convert repeated fixes into skills/runbooks.
- Start from the business bottleneck or value metric, not the flashy requested artifact.

Framework mapping:
- **Covered:** workflow registry, Conductor, skills/tools, production boundary, runbook workflows.
- **Candidate:** generalized external-action boundary for email/Slack/customer notifications,
  representative-case test matrix, close-out prompt for reusable lessons, Analyst value metric.
- **Reject:** market-size and pricing framing as framework canon.

## Merlin AI — The Best LOCAL Agentic Coding Workflow

Useful signal:
- Local models can be useful for offline or cheap utility work, but only when capabilities match
  the task.
- Tool use / file edit / shell support is the gating capability for agent work.
- Hardware and context length should drive local routing; model names age quickly.
- Separate tiny autocomplete/read-only models from larger agent/chat models.
- Smoke-test a local runtime before trusting it.

Framework mapping:
- **Covered:** provider-neutral model routing and cheap utility roles.
- **Candidate:** future `local` runtime adapter/experiment with capability declarations and a
  local-runtime smoke test.
- **Reject:** exact model recommendations and IDE setup as framework canon.

## Merlin AI — My COMPLETE Agentic Coding Workflow to Build Anything

Useful signal:
- Reduce assumptions before writing the spec: research first, then ask a batch of clarifying
  questions, then turn the answers into the durable PRD/spec.
- Treat the PRD/spec as the surviving artifact; conversation is disposable once captured.
- Keep global rules concise and move task-specific guidance into on-demand context.
- Use a "prime" step at the start of a new session to read docs, current repo state, and git log.
- Plan / implement / validate loops work best when implementation starts in fresh context with
  only the structured plan.
- Define validation before implementation, including browser/user-journey checks when UI exists.
- Set `.env.example` / required env vars before implementation so agents do not fake validation.
- Standardized commit messages can act as useful long-term memory.
- After each phase, preserve the E2E checks as a regression harness.
- When a bug or misalignment happens, improve the AI layer and tests, not just the code.

Framework mapping:
- **Covered:** Analyst/Architect/Spellwright split, run artifacts as durable context, per-role
  input contracts, fresh-context specialists, design/browser checks, skills and local context.
- **Candidate:** explicit assumption-reduction question pass before `spec.md`, phase-level
  regression harness capture, env preflight before execution, git-log summary in resume/prime,
  close-out "AI layer lesson" review.
- **Reject:** subagents only for research. The Bureau deliberately uses implementation subagents
  with scoped prompts, worktrees, cold review, and Conductor adjudication.

## Merlin AI — AGENTIC WORKFLOWS: Build & Sell AI Automations (2026)

Useful signal:
- Separate directives, orchestration, and execution: human-readable workflow/runbook docs for
  intent and decision flow; an orchestrator for routing; deterministic scripts/tools for exact
  repeated actions.
- A good directive names objective, inputs, step process, tools, expected outputs, done criteria,
  edge cases, fallback behavior, and graceful failure.
- Use a self-improvement loop when automation fails: diagnose the error, fix the script/workflow,
  retry, then update the docs so the fix survives the session.
- Deploy hardened execution pieces, not a loose live agent. Scheduled/webhook/cloud workflows
  need logging and monitoring from the start, because the IDE reasoning trace disappears.
- Keep autonomous cloud self-fixing out of scope for now; debug locally, battle-test, then run
  predictable pieces unattended.
- Use parallel experiments only when the alternatives are isolated and the evaluation criteria
  are clear; choose one winner before canonizing anything.
- Useful subagents are often least-privilege reviewers or doc-sync agents: fresh context, narrow
  tool/input access, no recursive spawning.
- Prefer descriptive filenames and tool names so agents can infer purpose from structure.

Framework mapping:
- **Integrated:** workflow/runbook authoring quality bar, deterministic-tool boundary,
  least-privilege input reminder, operational-build runbook gate, unattended/deploy
  observability stop.
- **Covered:** Conductor/workflow registry separation, Challenger fresh-context review,
  docs-reconcile workflow, production boundary, bounded parallelism.
- **Candidate:** explicit self-annealing failure loop for automation/runbook work, approach
  bake-off workflow for uncertain implementations, doc-sync subagent pass after script/runbook
  edits, descriptive-name lint for scripts/workflows.
- **Reject:** sales funnel, wealth-transfer framing, and exact cloud/vendor setup as framework
  canon.

---

## Current candidate backlog

1. Generalized external-action boundary: gate anything externally visible, not only production.
2. Representative-case / battle-test matrix for prompts and automation workflows.
3. Close-out reusable-learning pass: skill/runbook/convention/test update when a lesson repeats.
4. Analyst value metric: name the bottleneck or outcome the work is meant to improve.
5. Local runtime experiment: capability-aware `local` adapter plus smoke test.
6. Assumption-reduction question pass before greenfield `spec.md` is finalized.
7. Env preflight before execution: required vars, `.env.example`, and no fake validation.
8. Regression harness capture after each accepted implementation phase.
9. Git-log / commit-message summary as a first-class resume signal.
10. Self-annealing failure loop for automation/runbook work: error → diagnose → fix tool or
    directive → retry → document the fix.
11. Approach bake-off workflow: isolated candidate implementations with predeclared evaluation
    criteria and one winner.
12. Doc-sync pass after script/runbook changes: read execution code, update directives/docs only.
13. Descriptive-name lint for scripts, workflows, runbooks, and temporary files.
