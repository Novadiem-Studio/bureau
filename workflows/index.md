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

> **Authoring a step line?** Lead with **the agent's bold cast name**, make the tier its own **standard**/**strong** token, use → for outputs. Full spec: docs/conventions/workflow-authoring.md § Workflow step-line spec.
> **Authoring a workflow or runbook?** Use docs/conventions/workflow-authoring.md § Workflow / runbook authoring quality bar:
> objective, inputs, steps, outputs, done criteria, edge cases, fallback behavior,
> and observability for unattended or externally visible work.

## Registered workflows

| Workflow | When to use | Type | Summary |
|----------|-------------|------|---------|
| [feature](feature.md) | A new feature, a new product, or any substantial change needing a fresh spec + design + build plan | plan | Full multi-agent pipeline → spec, plan, scoped prompts |
| [bug-fix](bug-fix.md) | A known defect in existing code — crash, wrong result, regression — to reproduce, locate, fix, and verify in one tight loop. No spec/plan: the bug is the spec | mixed | Analizer 2000 reproduces/minimises (captures the repro) + locates the cause + names the domain → worktree → the domain's coder (Mage/Systemsmith/Mechanic) commits the fix plus a committed regression test in the target repo's correct home → The Challenger cold-reviews the diff and red/green evidence → The Conductor adjudicates, re-runs the repro to verify, stops at the dev-verified boundary |
| [build-review-cold](build-review-cold.md) | A self-contained change in existing code you can just build — no fresh spec, no plan to decompose — where you want the speed-first third gear: build solo, then at most ONE cold diff review (always for GitHub readiness; risk-triggered for local delivery). NOT for a new feature (→ feature), a canon/framework change (→ execute-plan), or a multi-surface / high-blast-radius diff (→ escalate) | mixed | Worktree + linked draft PR for public GitHub → domain coder builds solo → silent-failure self-gate → zero-risk local close-out or ONE cold Challenger → Conductor/Robin adjudicates → GitHub/local merge and dev verification. Stops at dev; external-action gate still applies |
| [code-review](code-review.md) | Review an existing diff, branch, pull request, or uncommitted changes before human review/merge; no code edits by default | mixed | The Conductor captures the review target → The Challenger cold-reviews the diff against local standards → The Conductor adjudicates, optionally runs named checks, and returns findings-first review |
| [codebase-readiness-audit](codebase-readiness-audit.md) | An explicit opt-in Codebase Readiness Audit request using `catalog`, `full`, or `audited`, to produce sealed findings or selectable remediation-planning input; not for ordinary `feature`, `code-review`, or direct-build routing | mixed | Product intent → independent coverage → runtime evidence and quarantine → corrected audit → profile gate → immutable seal → bounded remediation-planning input |
| [upstream-contribution](upstream-contribution.md) | A genuine, narrowly scoped fix, documentation/type correction, or test improvement for an unrelated public dependency or developer tool the studio actually uses | mixed | Confirm maintainer expectations → create/claim issue → fork worktree + early draft PR → focused implementation + tests → cold review → ready upstream PR and maintainer follow-up |
| [execute-plan](execute-plan.md) | There's a written plan doc (a `plans/todo/NN-*.md`); turn it into vetted scoped prompts and (gated) build them | mixed | The Architect (fit + chunk) → The Challenger → The Spellwright → `00-index + NN-*` prompt folder beside the plan → The Challenger → **gate** → build party builds each part (Mage/Systemsmith/Mechanic), The Challenger reviews each diff, The Conductor adjudicates |
| [design-build](design-build.md) | There's a Claude Design **handoff bundle** (a `.dc.html` export + handoff md) to implement in an existing codebase — the design is the spec, no fresh requirements | mixed | The Cleric (ingest) → `design/manifest.md` → The Architect (map onto existing routes + chunk) → The Challenger → The Spellwright → prompt folder → The Challenger → **gate** → build tail per `execute-plan` (Mage builds, Cleric reviews fidelity, Challenger reviews diff), stops at dev |
| [message-framing](message-framing.md) | You're writing user-facing copy and want the framing/angle chosen for the audience up front (or audience variants) | mixed | Runs The Counselor (Voice) in frame mode (spiral-dynamics framing + house voice) → tuned draft(s) |
| [copy-review](copy-review.md) | Any user-facing text needs a voice / tone / audience check before it ships | mixed | Runs The Counselor (Voice) in review mode (humanizer + spiral-dynamics + clarity + honesty) → findings + revised copy |
| [docs-reconcile](docs-reconcile.md) | Plan/status docs drifted from code ground truth (direct commits, reverts, renumbered migrations); deliverable is updated docs, not code | mixed | Survey agent re-derives ground truth from the repo → Reconcile agent edits docs → The Challenger re-verifies cold against the repo → Conductor adjudicates, user-gated commit |
| [studio-briefing](studio-briefing.md) | Studio-wide status: what's running, blocked, stale; executive summary or digest of run logs across installs | mixed | Spawn The Witness (read-only) → `output/studio/briefing.md` / `resume.md` / digests — narrative layer above Ministry of Flow (aka Logistics) |
| [operational-build](operational-build.md) | A defined, runbook-driven build/ops task — iOS build, container image, release prep — where a skill/runbook already holds the steps and the job is to run them under a gate | execute | The Conductor loads the runbook → gate → The Mechanic runs it (stops at the production boundary) → The Conductor closes out with a build/deploy record |
| [write-article](write-article.md) | Robin wants a long-form article for devweb.org through the full pipeline: angle → outline → draft → cross-model improvement passes → humanizer → staged MDX | mixed | The Counselor frames the angle → The Scribe outlines + drafts + revises → figure-grounding → `[EXTERNAL-ACTION CHECKPOINT]` → cross-model passes (`model-pass.sh`) → Scribe promotion authority → Counselor humanizer ×2 → Scribe MDX format → publish gate → write to devweb + `npm run build` |

> Add a row here whenever a workflow is defined. This table is the single source of truth
> for triage — every workflow file must have a row.

## Triage examples

These are anchors, not rules. Apply each workflow's **When to use** / **When NOT to use**; the
table just starts the comparison. A task that's 85% similar to an example may still belong to a
different workflow — match the criteria, not the closest-looking row.

| Task | Workflow |
|------|----------|
| Fix a crash on login | `bug-fix` |
| Build a small change to existing code and only cold-review it if the diff can fail silently | `build-review-cold` |
| Review this PR before I request human review | `code-review` |
| Run an explicit Codebase Readiness Audit in `audited` mode for this repository | `codebase-readiness-audit` |
| Fix a reproducible bug in a third-party dependency we use and submit it upstream | `upstream-contribution` |
| A new feature request ("add team invitations") | `feature` |
| There's a `plans/todo/50-email-verification.md`; turn it into executable prompts and build it | `execute-plan` |
| I exported a Claude Design handoff (`.dc.html` + handoff md) for the marketing pages — build it into the app | `design-build` |
| Write a launch-announcement email to a cold enterprise audience | `message-framing` |
| The landing-page copy sounds like an AI wrote it | `copy-review` |
| Migration numbers in a `plans/todo/` README are wrong after a revert | `docs-reconcile` |
| What's running, blocked, or stale across all active runs this morning? | `studio-briefing` |
| Run an iOS archive build from the existing release runbook | `operational-build` |
| Write an article about Rust async runtimes for devweb | `write-article` |

## Types

- **plan** — produces planning artifacts (spec / plan / scoped prompts) for you to implement.
- **execute** — does the work directly (runs a build, applies a fix), usually by loading an
  existing skill/runbook and following it.
- **mixed** — plans, then executes, within the same run.
