# Workflow: operational-build

**When to use:** a defined, runbook-driven build or ops task where the steps are already known
and the job is execution, not design — an iOS archive build, a container image build, release
prep, a scripted deploy-to-dev. There is an existing skill or runbook that holds the procedure
and meets docs/conventions.md § Workflow / runbook authoring quality bar; this workflow loads it
and runs it under a gate.

**When NOT to use:** there is NO runbook/skill yet and the procedure has to be designed —
that needs `feature` (to design it) or a `define-workflow` pass (to author the runbook) first.
NOT for turning a written plan doc into code — that's `execute-plan` (it decomposes a plan into
reviewed prompts and builds them part by part; this workflow runs an already-defined procedure
with no decomposition). NOT for anything that crosses the production boundary autonomously
(see the hard stop below).

**Type:** execute

**Inputs:** the skill or runbook that holds the procedure (named or discoverable in the
project's `.claude/skills/`); the target (which app/image/release); any params the runbook needs.

**Outputs:** a build artifact or a dev-deploy record, plus a one-block run summary appended to
`RUN_DIR/log.md`. No spec/plan/prompts.

**Leans on skills:** whatever runbook skill the task names (e.g. `ios`, `docker`). Load the
skill and follow it; do not duplicate its steps here.

## Steps

1. **The Conductor** (**standard**) — load the runbook: find the skill/runbook that holds the
   procedure (`.claude/skills/`, or the project's documented build runbook). Confirm it names the
   objective, inputs, ordered steps, expected outputs, done criteria, edge/fallback behavior, and
   observability for unattended/dev-deploy work. If none exists or the runbook is too vague to
   run from written context alone, STOP — this is the wrong workflow (see "When NOT to use"). →
   confirmed runbook + the exact target and params
2. **Gate** — show the human the runbook, the target, and what running it will touch; get a go
   before anything executes. `[CHECKPOINT]`.
3. **The Mechanic** (**standard**) — run the runbook steps exactly as the skill defines them,
   stopping at the **production boundary** (below). Build/dev-deploy only; never promote,
   publish, or push toward release/prod. → build artifact or dev-deploy record + checkpoint output
4. **The Conductor** (**standard**) — close out: confirm the artifact/checkpoint is green,
   summarize what ran and what was produced, flag anything deferred → one-block summary appended
   to `RUN_DIR/log.md`, updated `state.json`

> **Production boundary — hard stop (non-negotiable).** This workflow's finish line is a
> **dev/build artifact**: an image built, an archive produced, a deploy to dev verified. It does
> NOT promote a release, publish a build to the public/store, or push toward a release/prod
> branch. Any such step is a **release step**, decided and initiated by the human, never run
> autonomously in this workflow. This is the same hard stop `execute-plan.md` carries in full —
> see its "Production boundary — hard stop" block; it is not re-documented here at length.
