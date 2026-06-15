# Agentic workflow candidates

Best follow-up candidates pulled out of the video ledger. These are not framework mechanics yet;
they are the shortlist for a deliberate improvement pass.

## Use this note

Promote one candidate at a time. Before integrating, check whether the pattern has shown up in
real Bureau runs, then add the smallest workflow/persona/script change that would have helped.

---

## 1. Self-annealing failure loop for automation/runbook work

**Problem:** when an automation or runbook fails, the fix often lives in chat or the immediate
code diff, not in the reusable AI layer.

**Idea:** after a failed operational run, use a structured loop:

1. Capture the failure signature and exact command/tool/runbook step.
2. Diagnose whether the fault is in the execution script, workflow directive, env/preflight,
   external service assumption, or target code.
3. Patch the tool, script, runbook, or workflow directive.
4. Retry the smallest representative case.
5. Update docs/runbook/tests so the fix survives the session.

**Likely home:** `operational-build`, a new `runbook-repair` workflow, or a close-out subsection
in `agents/sysadmin.md`.

**Done when:** `RUN_DIR/log.md` records the failure/fix, the reusable artifact is updated, and a
smoke/regression command exists for the next run.

## 2. Approach bake-off workflow

**Problem:** for uncertain implementation strategy, the framework currently tends to pick one
path and iterate. Sometimes two or three isolated attempts would reveal the right solution faster.

**Idea:** run a bounded experiment:

1. Define the question, constraints, and evaluation criteria before building.
2. Spawn two or three independent approaches in separate worktrees or prompt tracks.
3. Test/review each with the same criteria.
4. Choose one winner, discard losers, and canonize only the winning pattern.

**Guardrails:** max three tracks, no production/external side effects, no merging partial losers,
and no bake-off without predeclared evaluation criteria.

**Likely home:** new `approach-bakeoff` workflow, or an optional branch inside `feature` /
`execute-plan` when The Architect flags high uncertainty.

**Done when:** there is a workflow with explicit criteria, per-track artifacts, Challenger review
of each candidate, and a Conductor decision log explaining the winner.

## 3. Doc-sync pass after script/runbook changes

**Problem:** execution code and runbooks drift. Agents then follow stale instructions even when
the underlying script is correct.

**Idea:** add a least-privilege documentation sync pass after meaningful script/runbook changes.
The sync agent reads execution scripts/tests and writes only directive docs/runbooks. A fresh
Challenger then verifies the docs against the executable ground truth.

**Likely home:** `docs-reconcile` variant first; only create a new persona if the pattern repeats
often enough to deserve one.

**Done when:** changed scripts and their matching runbooks agree on inputs, commands, outputs,
done criteria, failure behavior, and observability.

## 4. Descriptive-name lint

**Problem:** generic names make agentic navigation worse. Files named vaguely are cheap for a
human who remembers context, but expensive for fresh agents.

**Idea:** add a warning-only check for vague or misleading script/workflow/runbook names, plus
temporary files that should be under a temp path or deleted.

**Likely home:** optional warning section in `check-framework.sh`, possibly backed by a small
script in `scripts/`.

**Done when:** the framework can flag obvious low-signal names without blocking legitimate legacy
files, and the warning points to a better naming pattern.

---

## Lower priority candidates still in the ledger

The broader backlog remains in `ideas/agentic-workflow-video-ledger.md`: external-action gates,
representative-case matrices, env preflight, regression harness capture, git-log resume signals,
local-runtime experiments, and Analyst value metrics.
