# Workflow Registry

The Orchestrator reads this file **first, on every task**, to triage: classify the
incoming task, pick the matching workflow, and run it. Each workflow has its own file in
this folder with the full step definition.

## How triage works

1. Read the task.
2. Match it against the **When to use** column below. Pick the best fit.
3. State the chosen workflow and why, in one line, before running it.
4. If nothing fits, invoke the **define-workflow** skill to create a new workflow, then run it.
5. If the task is mixed (e.g. "fix these bugs AND add a feature"), split it and run each
   part through its own workflow.

> **Authoring a step line?** Lead with **the agent's bold cast name**, make the tier its own **standard**/**strong** token, use → for outputs. Full spec: docs/conventions.md § Workflow step-line spec.

## Registered workflows

| Workflow | When to use | Type | Summary |
|----------|-------------|------|---------|
| [feature](feature.md) | A new feature, a new product, or any substantial change needing a fresh spec + design + build plan | plan | Full multi-agent pipeline → spec, plan, scoped prompts |
| [bug-fix](bug-fix.md) | A known defect in existing code — crash, wrong result, regression — to reproduce, locate, fix, and verify in one tight loop. No spec/plan: the bug is the spec | mixed | Analizer 2000 reproduces (captures the repro) + locates the cause + names the domain → worktree → the domain's coder (Mage/Systemsmith/Mechanic) fixes it → The Challenger cold-reviews the diff → The Conductor adjudicates, re-runs the repro to verify, stops at the dev-verified boundary |
| [execute-plan](execute-plan.md) | There's a written plan doc (a `plans/todo/NN-*.md`); turn it into vetted scoped prompts and (gated) build them | mixed | The Architect (fit + chunk) → The Challenger → The Spellwright → `00-index + NN-*` prompt folder beside the plan → The Challenger → **gate** → build party builds each part (Mage/Systemsmith/Mechanic), The Challenger reviews each diff, The Conductor adjudicates |
| [message-framing](message-framing.md) | You're writing user-facing copy and want the framing/angle chosen for the audience up front (or audience variants) | mixed | Runs The Counselor (Voice) in frame mode (spiral-dynamics framing + house voice) → tuned draft(s) |
| [copy-review](copy-review.md) | Any user-facing text needs a voice / tone / audience check before it ships | mixed | Runs The Counselor (Voice) in review mode (humanizer + spiral-dynamics + clarity + honesty) → findings + revised copy |
| [docs-reconcile](docs-reconcile.md) | Plan/status docs drifted from code ground truth (direct commits, reverts, renumbered migrations); deliverable is updated docs, not code | mixed | Survey agent re-derives ground truth from the repo → Reconcile agent edits docs → The Challenger re-verifies cold against the repo → Conductor adjudicates, user-gated commit |
| [studio-briefing](studio-briefing.md) | Studio-wide status: what's running, blocked, stale; executive summary or digest of run logs across installs | mixed | Spawn The Witness (read-only) → `output/studio/briefing.md` / `resume.md` / digests — narrative layer above Ministry of Flow (aka Logistics) |
| [operational-build](operational-build.md) | A defined, runbook-driven build/ops task — iOS build, container image, release prep — where a skill/runbook already holds the steps and the job is to run them under a gate | execute | The Conductor loads the runbook → gate → The Mechanic runs it (stops at the production boundary) → The Conductor closes out with a build/deploy record |

> Add a row here whenever a workflow is defined. This table is the single source of truth
> for triage — every workflow file must have a row.

## Triage examples

These are anchors, not rules. Apply each workflow's **When to use** / **When NOT to use**; the
table just starts the comparison. A task that's 85% similar to an example may still belong to a
different workflow — match the criteria, not the closest-looking row.

| Task | Workflow |
|------|----------|
| Fix a crash on login | `bug-fix` |
| A new feature request ("add team invitations") | `feature` |
| There's a `plans/todo/50-email-verification.md`; turn it into executable prompts and build it | `execute-plan` |
| Write a launch-announcement email to a cold enterprise audience | `message-framing` |
| The landing-page copy sounds like an AI wrote it | `copy-review` |
| Migration numbers in a `plans/todo/` README are wrong after a revert | `docs-reconcile` |
| What's running, blocked, or stale across all active runs this morning? | `studio-briefing` |
| Run an iOS archive build from the existing release runbook | `operational-build` |

## Types

- **plan** — produces planning artifacts (spec / plan / scoped prompts) for you to implement.
- **execute** — does the work directly (runs a build, applies a fix), usually by loading an
  existing skill/runbook and following it.
- **mixed** — plans, then executes, within the same run.
