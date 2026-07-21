# Workflow: bug-fix

**When to use:** a known defect in code that already exists — a crash, a wrong result, a
regression, a broken interaction — where the job is to reproduce it, find the cause, fix it, and
verify the fix, in one tight loop. The most common task. There is no new capability to design and
no plan to decompose: the bug itself is the spec.

**When NOT to use:** a new capability that needs requirements or architecture before anyone can
build it — that's `feature` (the bug-fix has no spec because the bug IS the spec; a feature has
to write one). A job that decomposes an already-written plan doc into prompts — that's
`execute-plan` (bug-fix has no plan doc and no prompt folder; it fixes one located cause
directly). A runbook-driven ops task — an image build, a release prep, a scripted deploy — that's
`operational-build` (bug-fix is a code defect, not a procedure to run). A "bug" whose fix needs a
new design surface, or spans two coders' domains, is not a bug fix: it stops at a `[CHECKPOINT]`
where the human decides between splitting it into two `bug-fix` runs or escalating to `feature`
(the two-domain case surfaces in step 1 if it's visible up front, or at step 3 if the coder only
discovers it on opening the cause).

**Type:** mixed (scopes lightly — reproduce + locate — then fixes in a worktree and verifies, in
one run. No spec.md, no plan.md, no design checkpoint, no prompt folder.)

**Inputs:** the bug report or symptom (inline); the target repo / sub-app; in existing projects,
the workspace orientation (see "Existing-project mode" in `agents/orchestrator.md`) and the
per-sub-app skills the affected surface needs.

**Outputs:** under `RUN_DIR` (see `docs/run-protocol.md`): `log.md`, `state.json`, and
`repro.md` — the captured repro + located cause that step 1 records and step 4 re-runs. `repro.md`
is its own artifact (separate from `log.md`) so the Conductor can hand it to the cold Challenger
without the run log; it is what keeps the review cold. `repro.md` is also the single home for
the regression-test record: test path, pre-fix red evidence, post-fix green evidence, or the
explicit no-correct-seam finding. The fix itself lands as a reviewed diff in this run's **git
worktree**, merged to the dev/integration branch at close-out. No `spec.md`, no `plan.md`, no
`prompts.md`.

**Leans on skills:** `docs/conventions/diagnosing-bugs.md` (red-capable feedback loop,
minimise, hypothesise/instrument, regression-test seam/home rule) + **novadiem-engineering**
(cross-project coding standards — loaded by the coder and The Challenger so the fix and its
review hold the same bar) + the project's `testing` skill, if it has one, for the verify step
(reuse its run commands; don't reinvent them) + the per-sub-app skills the affected surface
needs. Load the skill, don't duplicate its runbook.

## Steps

Run these as spawned subagents (see "How to spawn an agent" and "Model routing" in
`agents/orchestrator.md`). Sequential — wait for each handoff before the next. Pass `RUN_DIR` as
an absolute path in every spawn prompt; build/fix spawns also get `WORKTREE`.

1. **Analizer 2000** (Reproduce, **standard**) — load
   `docs/conventions/diagnosing-bugs.md`. Reproduce the bug FIRST, before anything is touched
   (don't fix blind); capture a red-capable feedback loop as the failing command / test / steps
   so it becomes the acceptance test; minimise the repro; then locate the root cause (file +
   symbol + why) and name the affected sub-app / domain and the coder who owns it →
   `RUN_DIR/repro.md` (captured repro + minimised scenario + located cause + affected domain +
   candidate regression seam) — a separate artifact from `log.md` so the cold Challenger can read
   it in step 4 without the run log (the Conductor may log a one-line decision to `log.md`).
   If the cause is still foggy after minimising, use the diagnosing-bugs hypothesis/probe loop:
   3-5 falsifiable hypotheses, targeted instrumentation only, debug prefixes, cleanup proof. If
   probes require code edits, ask the Conductor to create the worktree early and run them there;
   never instrument the integration branch checkout.
   - reproduced + cause located: proceed.
   - cannot reproduce, or the cause is unclear: `[CHECKPOINT]`.
   - the cause spans two coders' domains (not one bug): `[CHECKPOINT]` (human decides: split into
     two `bug-fix` runs, or escalate to `feature`).
2. **Worktree** (before step 3, or earlier if step 1 needed temporary probes) — create an
   isolated git worktree for this run (see `docs/git-worktree.md`). From the **target repo**
   named in step 1 / the workspace map:

   ```bash
   <FRAMEWORK>/scripts/run-worktree.sh create \
     --run-dir "$RUN_DIR" \
     --repo <absolute repo path> \
     --base <integration branch; default devel from project-context.md> \
     --merge-policy end_of_job
   ```

   Record paths in `state.json` (`git` block). The build spawn in step 3 gets **`WORKTREE:`** —
   the absolute `worktree_path`. Never edit `devel` (or the integration branch) directly during
   the run. Commit in the worktree before the diff is handed to review.
3. **The Conductor** dispatches the coder the domain names — **The Mage** (frontend/UI) ·
   **The Systemsmith** (backend/data/contract) · **The Mechanic** (ops/infra) — at tier
   **strong** to fix exactly the located cause in **`WORKTREE`** (not the integration branch
   checkout), commit, and not touch anything the cause doesn't reach → a fix diff in the worktree.
   The coder is chosen directly from step 1's domain — there is no `Coder:` tag (no prompt folder
   to carry one). **Coder instruction (carry into the spawn):** fix only within your own domain; if
   the located cause turns out to span a second coder's domain once you open it, STOP and raise
   `[CHECKPOINT]` (human decides: split into two `bug-fix` runs, or escalate to `feature`) — do not
   reach into the other domain. That is not one bug fix, and fixing across a contract boundary
   single-handed is exactly what this stop exists to prevent. Keep the fix reviewable: if the
   smallest honest fix becomes a broad refactor, a multi-surface rewrite, or a large surprise
   diff, stop and report that the bug is bigger than the located cause. The Conductor chooses
   whether to split it or escalate. Load `docs/conventions/diagnosing-bugs.md`. Before applying
   the fix, turn the minimised repro into a committed regression test at the correct target-repo
   home: Bureau targets use a `.bureau/regression/NNN-slug.md` fixture; app targets use the app's
   own test suite named by the local `testing` skill / `CLAUDE.md` / sub-app convention. Run it
   on the pre-fix code and record the red command/output in `RUN_DIR/repro.md`; then apply the fix
   and record the green command/output. If no correct seam exists, do not fake a shallow test:
   write `Regression test: none — no correct seam` in `RUN_DIR/repro.md`, with attempted seams
   and the follow-up needed to make the bug lockable.
4. **The Challenger** (Critic, **strong**, fresh context required) — cold-review the fix diff (in
   `WORKTREE`) against `RUN_DIR/repro.md` (the captured repro + located cause); it does **NOT**
   receive `log.md`, the fix rationale, or the coder's reasoning (coldness): does it fix the
   located cause (not just mask the symptom)? does the regression test exist in the correct
   per-repo home and prove pre-fix red → post-fix green, or is the no-correct-seam finding real?
   does it touch only what the cause requires? is the diff small and coherent enough for a real
   review? any regression risk? → `log.md`, findings
   - **The Conductor adjudicates**: route the fix back to the coder (max 2x — `max_critic_loops`),
     accept, or `[CHECKPOINT]`.
   - **Then verify** (Conductor): re-run the repro captured in `RUN_DIR/repro.md` — it must now
     PASS — and run the project's existing test pass (lean on the `testing` skill if the project
     has one; reuse its commands) to confirm no regression. The fix is not accepted until the
     original repro passes, the regression-test record is present (or the no-correct-seam finding
     is explicit and reviewed), and the suite is green.
   - **Close out** at the `[DEV-VERIFIED CHECKPOINT]` (format in `agents/orchestrator.md`): human
     go, then merge the worktree to the **dev/integration branch only**, then `run-worktree.sh remove`
     (on conflict: `[CHECKPOINT]`); check for new packages after the merge and install into the
     running container; append the run to `log.md`. As the **final** close-out action, run
     `scripts/account-run.sh <RUN_DIR>` and set `state.json#accounting` per
     `docs/run-accounting.md`. The run ends at **dev-verified** —
     taking anything past dev is the human's separate call (see "Production boundary" below).

> **Production boundary — hard stop (non-negotiable).** This workflow's finish line is the fix
> **built, verified, and green on the dev/integration branch**. The Conductor does NOT deploy
> beyond dev, merge toward a release/prod branch, or ship to the public as part of this workflow.
> This is the same hard stop `workflows/execute-plan/build-tail.md` carries in full — see its
> "Production boundary — hard stop" block; it is not re-documented here at length. When the repro
> passes and dev is green, raise the `[DEV-VERIFIED CHECKPOINT]` and stop. Production is the
> human's call.

The full agent specs, verdict format, worktree mechanics, and checkpoint formats live in
`agents/orchestrator.md` and the per-agent files in `agents/`. This file just names the sequence;
it doesn't duplicate them.
