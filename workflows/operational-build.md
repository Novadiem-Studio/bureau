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
2b. **The Conductor** — run preflight **after the human Gate, before the Mechanic acts** → `RUN_DIR/preflight.md`.
   Invoke `scripts/preflight.sh <target-dir> <RUN_DIR>` where `<target-dir>` is the target
   project/repo directory the runbook acts on. The script validates `<target-dir>/.env.example`
   keys against the live environment and writes `RUN_DIR/preflight.md` (result PASS or FAIL). A
   non-zero exit **stops the run**: the Mechanic must not act until `preflight.md` shows PASS. The
   close-out in step 4 re-checks this before accepting the run.
3. **The Mechanic** (**standard**) — run the runbook steps exactly as the skill defines them,
   stopping at the **production boundary** (below). Build/dev-deploy only; never promote,
   publish, or push toward release/prod. → build artifact or dev-deploy record + checkpoint output
4. **The Conductor** (**standard**) — close out: confirm the artifact/checkpoint is green,
   summarize what ran and what was produced, flag anything deferred → one-block summary appended
   to `RUN_DIR/log.md`, updated `state.json`. For commit-message guidance in execute-style runs,
   see `workflows/execute-plan.md` step 7. (Run accounting **last** — see the end of this step.)

   **Run accounting last.** As the *final* close-out action — after the summary and the final
   `state.json`/`log.md` updates above — run `scripts/account-run.sh <RUN_DIR>` so `accounting.json`
   reflects the run's terminal state, then set `state.json#accounting` per
   `docs/run-accounting.md` (on failure: `status: unavailable`,
   `path: null`). On an abnormal/interrupted exit, attempt accounting anyway per that convention.

   **Close-out gates (Conductor-owned).** Before accepting the run, the Conductor runs both of
   these itself — neither is delegated to The Challenger or `critic.md`. (operational-build has no
   Challenger round, so this close-out is the only home for these checks in this workflow.)
   - **Preflight PASS** — the Conductor reads `RUN_DIR/preflight.md` directly. A missing file, or
     one whose `result` field reads FAIL while the Mechanic was dispatched, is a **Blocker** / halt.
   - **External-action log** — `RUN_DIR/log.md` must carry a logged `[EXTERNAL-ACTION CHECKPOINT]`
     entry for each external action that actually fired. A fired action with no `log.md` entry is a
     **Blocker** / halt. The Conductor cross-checks the Mechanic's handoff-footer line
     `Prod/irreversible actions taken:` against the logged `[EXTERNAL-ACTION CHECKPOINT]` entries in
     `log.md`.

   ### Failure repair

   When a runbook step fails during step 3, the Conductor must, per failure:
   1. Record a failure signature in `RUN_DIR/log.md`, per `docs/conventions.md § Failure signature
      format` (cite the section by name — do NOT restate the five fields here).
   2. Identify the suspected layer and patch the durable artifact named by that layer.
   3. Run the verification case before retrying or closing out.
   4. At close-out, confirm that every failure recorded this run carries an `artifact-patched:`
      field naming a durable file — or explicitly states `none — carried` with a reason. A verbal
      assurance is not acceptable; a named file or a written deferral is the only passing form
      (this is Challenger-checkable).

   **`docs-sync-needed` (Conductor-owned Blocker).** For every script, runbook, or workflow changed this run, name the durable artifact patched — or state explicitly why none. Produce a list: one line per changed artifact, naming what was updated (e.g. `scripts/preflight.sh → docs/runbook X updated`). If no script/runbook/workflow changed this run, write the single line `docs-sync-needed: none — no script/runbook/workflow changed this run`. **An empty checkbox, a bare "done", or "docs are fine" is a Blocker** — the gate is satisfied only by the named list or the explicit no-change line. A change to `docs/conventions.md` itself satisfies the gate by naming `docs/conventions.md` as the artifact patched — the convention change IS the durable artifact; no further downstream update is implied.

   **`lessons-append` (Conductor-owned Blocker).** If a failure signature was recorded in `RUN_DIR/log.md` this run (per `docs/conventions.md § Failure signature format`), name the `output/studio/lessons.md` entry appended for it — by its `failure-signature:` slug — or state `lessons-append: none — carried` with the reason it was not appended this run (e.g. promotion deferred to a named next run). If no failure signature was recorded this run, write the single line `lessons-append: none — no failure signature recorded this run`. **An empty line, a bare "lessons updated", or "lessons.md is fine" with no named entry is a Blocker** — the gate is satisfied only by a named `lessons.md` entry (its slug), the explicit `none — carried` with a reason, or the explicit no-failure line. A failure signature in `log.md` with no corresponding `lessons.md` entry and no `none — carried` reason is a **Blocker** at close-out.

> **Production boundary — hard stop (non-negotiable).** This workflow's finish line is a
> **dev/build artifact**: an image built, an archive produced, a deploy to dev verified. It does
> NOT promote a release, publish a build to the public/store, or push toward a release/prod
> branch. Any such step is a **release step**, decided and initiated by the human, never run
> autonomously in this workflow. This is the same hard stop `execute-plan.md` carries in full —
> see its "Production boundary — hard stop" block; it is not re-documented here at length.
