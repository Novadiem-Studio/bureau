# Workflow: execute-plan

**When to use:** there is already a written plan document (e.g. a `plans/todo/NN-name.md`) and
the job is to turn it into the executable, scoped prompts that build it. NOT a raw idea or a
fuzzy ask that still needs requirements (that's `feature`). A plan is an EARLY artifact, roughly
what the Analyst produces; this workflow carries it forward to vetted, decomposed prompts.

**When NOT to use:** a raw idea or fuzzy ask that still needs requirements (use `feature`). Not for a runbook-driven ops build with no plan to decompose (use `operational-build`).

**Type:** mixed (produces a reviewed set of scoped prompts, then builds them part by part with
review. The build stage is gated twice: you approve the prompt folder before any code is
written, and the run **stops at development** — nothing deploys beyond dev, merges toward a
release/prod branch, or ships to the public until you confirm dev looks good. See "Production
boundary" below.)

**Inputs:** the path to the plan doc; the workspace orientation (`monorepo-orientation`); the
per-sub-app skills the plan's surfaces need.

**Outputs:** a **prompt folder beside the plan doc**, same name minus `.md`, holding
`00-index.md` + `NN-<slug>.md` scoped prompts (format below). Example:
`foaf-auth/docs/plans/todo/50-email-verification/`.

**Leans on skills:** **novadiem-engineering** (cross-project coding standards, loaded by the
Architect, Challenger, Spellwright, and every build-party coder) + `monorepo-orientation`
(routing) + whatever the plan's surfaces call for (`auth`, `mutual-credit`, `redux`,
`components`, `testing`, `docker`, `s3`, …). Load the skill, don't duplicate its runbook.

## Steps

The **writers' room** reviews, decomposes, and re-reviews (steps 1-4). The **build party** then
builds the vetted prompts part by part (steps 5-7), each part reviewed before the next.

1. **The Architect** (**strong**) — orient (`monorepo-orientation`), read the plan in full,
   and verify it still fits the **current** code (spot-check the plan's critical files and symbol
   anchors; plans drift). Define the chunking: the ordered list of scoped units by sub-app /
   layer, the ship order across sub-apps, the analogous shipped feature each chunk mirrors, and
   the **coder who owns each chunk** — frontend/design → **The Mage**, backend/data/contract →
   **The Systemsmith**, ops/deploy/infra → **The Mechanic**. A chunk that spans two coders' domains is
   two chunks (the contract-owning chunk ships first).
   - anchors hold → proceed.
   - material drift (a branch site is gone, a product decision is now wrong) → `[CHECKPOINT]`.
2. **The Challenger** (Critic, round 1, **strong**, fresh context required) — cold-review the plan + chunking: requirement
   gaps, missing edge cases, wrong sequence, hidden cross-sub-app dependencies, anything that
   will bite the implementer. Reports findings. The Conductor adjudicates: route the fix back
   to The Architect (max 2x), note + proceed, or `[CHECKPOINT]`.
3. **The Spellwright** (Prompt Engineer, **standard**) — decompose the approved plan into the
   **prompt folder** (format below), beside the plan doc. One prompt = one coherent unit a single
   Claude Code session can finish, owned by **exactly one coder** (carry the Architect's chunk
   assignment; tag every prompt `Coder:`). Each names exact files and ends with a green checkpoint.
   Keep every prompt reviewable: it should fit in one focused code-review sitting, touch only one
   domain/surface, and produce a diff The Challenger can inspect cold. If the plan chunk would
   create a sprawling diff, split it before the build stage; a 10k-line surprise is a planning
   failure, not a productivity win.
4. **The Challenger** (Critic, round 2, **strong**, fresh context required) — cold-review the prompts: is each independently
   executable? correct order? hidden deps between steps? are the workspace gotchas captured? is
   every checkpoint testable? Reports findings. The Conductor adjudicates: route the fix back to
   The Spellwright (max 2x), note + proceed, or `[CHECKPOINT]`.
5. **Gate** — show the human the prompt folder and get a go before building. `[CHECKPOINT]`.
   (If they only wanted the prompts, stop here; that's a valid end.)
5b. **Worktree** (before step 6) — create an isolated git worktree for this run (see
   `docs/git-worktree.md`). From the **target repo** named in the plan / workspace map:

   ```bash
   <FRAMEWORK>/scripts/run-worktree.sh create \
     --run-dir "$RUN_DIR" \
     --repo <absolute repo path> \
     --base <integration branch; default devel from project-context.md> \
     --merge-policy end_of_job
   ```

   Record paths in `state.json` (`git` block). All build-party spawns get **`WORKTREE:`** —
   the absolute `worktree_path`. Never edit `devel` (or the integration branch) directly during
   the run. Commit in the worktree before each prompt handoff is accepted.

   **Merge policy** (`git.merge_policy` in `state.json`):
   - `end_of_job` (default) — merge at step 7 only.
   - `per_prompt` — after each accepted prompt: `run-worktree.sh merge`, then `sync` before the next.
   - `checkpoint` — merge only when the human says so at `[CHECKPOINT]`.

5c. **The Conductor** — run preflight **after the worktree exists, before the build party dispatches** → `RUN_DIR/preflight.md`.
   Invoke `scripts/preflight.sh <target-dir> <RUN_DIR>` where `<target-dir>` is the worktree root
   (the absolute `worktree_path` from `state.json`). The script checks `<target-dir>/.env.example`
   keys against the live environment and writes `RUN_DIR/preflight.md` (result PASS or FAIL). If
   preflight exits non-zero, the run **halts**: the Conductor may not dispatch the build party until
   `preflight.md` shows PASS. The close-out in step 7 re-checks this before accepting the run.

6. **The Conductor** (**strong**) — build part by part: run the prompts in order, 01..NN, dispatching each to the coder named by its `Coder:` tag — the tag is the assignment; do not re-infer the owner from the sub-app (a missing or wrong tag is a Spellwright defect: route it back rather than guessing) → a reviewed diff per part
   - frontend + design implementation → **The Mage** · backend → **The Systemsmith** · ops/deploy → **The Mechanic**

   Each coder works in **`WORKTREE`** (not the integration branch checkout). Loads the target
   sub-app's CLAUDE.md + the skills the prompt names, builds exactly that one prompt, commits
   in the worktree, and gets its checkpoint green. After each part:
   - **The Challenger** (**strong**, fresh context required) cold-reviews that single diff against the prompt and the plan → findings.
   - **The Cleric (mode: review)** additionally checks UI prompts: the built screens against
     `design/manifest.md` (components, tokens, states, flow, real data). FAITHFUL or DRIFTED
     with findings; drift fixes route back to The Mage with the correctness fixes.
   - **Visual blocking rule:** a visual checkpoint (browser/device inspection of the live UI)
     is only a hard gate when a dev server is confirmed running AND the relevant UI surface is
     accessible (authenticated, navigated to the right screen). When the Mage reports limited
     visual access (no server, no demo data, no auth), carry the visual check as a
     `carried_items` note in `state.json` and proceed — do not block prompt acceptance on a
     check that cannot actually be performed. Code-visible drift (wrong component in the diff,
     wrong token, wrong data wiring) is always blocking regardless of server access.
   - **The Conductor adjudicates**: accept and move to the next prompt, send it back to the coder
     to fix (max 2x), or `[CHECKPOINT]`. Don't start the next prompt until this one is accepted.
   - **Review-size gate:** before accepting a coder handoff, compare the diff to the prompt's
     named files, domain, and `Review size` handoff line. If the authored change is much broader
     than the prompt, crosses into another coder's domain, or hides large conceptual work behind
     generated churn, do not accept it just because checkpoints are green. Route it back, split the
     prompt, or checkpoint for a human call.
   - If `merge_policy` is `per_prompt` and the prompt is accepted: `run-worktree.sh merge`,
     then `sync`, append prompt id to `git.prompts_merged` in `state.json`.

   **Parallel tracks (optional).** No more than two prompts may build SIMULTANEOUSLY (e.g. The
   Systemsmith on a backend prompt while The Mage builds UI) unless the human explicitly asks for
   a wider experiment. Even two is allowed only when ALL hold:
   - different coders AND different repos/sub-apps;
   - neither prompt consumes a contract the other produces (check `Depends on` / the named
     contract — contract-owning prompts always ship before their consumers);
   - neither touches a shared autogenerated artifact (e.g. the protocol sync).
   Each track keeps its own build→review→adjudicate loop; The Conductor interleaves
   adjudications and respects the overall ship order at the end. When in doubt, serialize —
   parallelism saves wall-clock, not review effort.

   An `[EXTERNAL-ACTION CHECKPOINT]` raised during ANY active build track halts ALL active
   build tracks until the Conductor logs resolution. Neither track proceeds autonomously while
   an external action awaits human approval — same discipline as the production boundary.

   **Coupling pass (when halves must compound).** After **both** sides of a named seam are
   accepted — typically Mage UI ↔ Systemsmith API, or any cross-coder contract the plan or
   `00-index.md` calls out — spawn **The Coupler** (`agents/coupler.md`, tier: **standard**,
   fresh context) **before** any prompt that consumes both halves.

   Pass `RUN_DIR`, `WORKTREE`, `SEAM`, `HALF_A`, `HALF_B`, and the plan's checkpoint commands.
   The Coupler writes `RUN_DIR/coupling/<seam-slug>.md` and appends to `log.md`.

   - **PHASE LOCK HELD** → log it, continue the build order.
   - **PHASE LOCK FAILED** with BLOCKERS → route fixes to the owning coder(s) (max 2 loops per
     half, same as Challenger); re-couple after fixes. Do not start downstream prompts on a
     broken seam.

   When the build used only one coder or no cross-coder contract, skip coupling. When multiple
   coders shipped and the plan names a **final integration seam**, run one Coupler pass before
   step 7 close-out.

> **Production boundary — hard stop (non-negotiable).** The build party's finish line is
> **development**: code built, checkpoints green, integrated on the dev/integration branch and
> verified there. The Conductor does **not** deploy beyond dev, merge toward a release/prod
> branch, or ship to the public as part of this workflow. Any prompt whose work crosses that
> line (deploy to demo/staging/prod, promote a release, publish a build, push to a prod branch)
> is a **release step**, not a build step — it is NEVER run in the 01→NN build loop. When the
> build prompts are done and dev is green, STOP and raise the `[DEV-VERIFIED CHECKPOINT]`
> (format in `agents/orchestrator.md`). A deploy step written into the plan or prompt folder is
> a description of intent, not authorization to run it; the human decides if and when anything
> goes past dev. Production is the human's call, every time.

> **External-action boundary — separate gate.** Distinct from the production boundary above:
> before executing any action in the external-action taxonomy (sent emails/SMS, chat posts,
> webhook calls, customer-facing notifications, payment triggers, calendar invites, DNS/infra
> mutations, other side-effecting outbound HTTP), the build party must **surface it** and raise
> an `[EXTERNAL-ACTION CHECKPOINT]` before it fires. See `docs/external-action-boundary.md` for
> the full taxonomy, the default rule, and the reversibility tiers. This gate and the
> production-deploy gate are **separate protections** — the external-action gate applies
> **regardless of deployment stage** (a dev-stage step that fires a real email is still gated);
> neither boundary subsumes the other.

7. **The Conductor** (**strong**) — close out: if `git.merge_policy` is `end_of_job` and worktree is active, human go, then merge, then remove (on conflict: `[CHECKPOINT]`); then check for new packages, install into the running container, summarize what shipped to dev vs. planned, and move the plan doc out of `todo/` → updated `RUN_DIR/log.md`, `state.json`, relocated plan doc
   human go → `run-worktree.sh merge` → `run-worktree.sh remove` (on conflict: `[CHECKPOINT]`,
   human resolves on integration branch, then `remove`). This merge targets the **dev/integration
   branch only** (e.g. `devel`), never a release/prod branch.

   **After the merge, immediately check for new packages:**
   ```bash
   git diff HEAD~1 -- package.json | grep '^\+' | grep -v '^\+\+\+'
   ```
   If any dependency lines were added, install into the **running** container — not a fresh
   `run --rm` one. Apps that use `- /app/node_modules` in docker-compose keep node_modules
   in an anonymous volume scoped to the running service; a `run --rm` container gets its own
   throwaway volume and the install is lost when it exits:
   ```bash
   docker-compose exec app npm install              # Expo / Node (running container)
   docker exec <container-name> npm install         # if compose service name differs
   # or: docker-compose exec backend bundle install # Rails
   ```
   Do not hand back to the human with the app broken because packages are missing.

   Summarize what shipped to dev vs. what the plan asked for, flag anything deferred, append
   the run to `RUN_DIR/log.md`, and move the plan doc out of `todo/` (or mark done). The run
   ends at **dev-verified**; taking anything past dev is a separate, human-initiated action
   (see "Production boundary").

   **Close-out gates (Conductor-owned, not Challenger checks).** Before accepting the run, the
   Conductor runs both of these itself — neither is delegated to The Challenger or `critic.md`:
   - **Preflight PASS** — the Conductor reads `RUN_DIR/preflight.md` directly. A missing file, or
     one whose `result` field reads FAIL while a build party was dispatched, is a **Blocker** /
     halt — not a Conductor-discretion call.
   - **External-action log** — `RUN_DIR/log.md` must contain a logged `[EXTERNAL-ACTION CHECKPOINT]`
     entry for each external action that actually fired during the run. A fired external action with
     no `log.md` entry is a **Blocker** / halt. The Conductor cross-checks the Mechanic's
     handoff-footer line `Prod/irreversible actions taken:` against the logged
     `[EXTERNAL-ACTION CHECKPOINT]` entries in `log.md` to confirm every fired action was logged
     before it fired.

## Prompt folder format

For a plan at `<dir>/<NN>-<name>.md`, create `<dir>/<NN>-<name>/` beside it.

**`00-index.md`:**
- Title: `# Job <NN> — <name> · execution prompts`.
- One line pointing at the canonical plan (`../<NN>-<name>.md`, "read it first").
- `## How to run` — execute in order 01→NN, don't start a step until the previous checkpoint is
  green; the analogous **shipped feature to mirror** (reuse its analog, adapt); the ship order
  across sub-apps; the docker-first test command per sub-app (with `-e RAILS_ENV=test` for rails,
  so DatabaseCleaner doesn't wipe dev data).
- `## Steps` — one bullet per prompt: `**NN** — <coder> · <sub-app>: <one-line scope>`
  (e.g. `**04** — The Systemsmith · railsbackend: proxy layer`).
- `## Non-negotiable gotchas` — the landmines for this work, pulled from the skills and the plan
  (audit-type registration, queue names, additive/latin1 migrations, autogenerated files that
  must be synced, etc.).
- `## Coupling seams` (when more than one coder) — each cross-coder boundary: which prompts
  are the halves, what contract they share, smoke command for phase lock. The Coupler runs
  after both halves are accepted and before any consumer prompt.

**Each `NN-<slug>.md`:**
- Title: `# <NN> — <sub-app>: <short title>`.
- `Coder:` exactly one of **The Mage** (frontend/design), **The Systemsmith** (backend/data/
  contract), **The Mechanic** (ops/deploy/infra). One prompt = one coder; if a unit needs two,
  split it and name the shared contract in both prompts.
- `Plan:` the canonical plan section it implements (`../<plan>.md §N`) + the analog to mirror.
- `Reviewability:` one line naming the expected diff surface: the primary files/dirs, whether
  generated files or lockfiles are expected, and the boundary that would make the coder stop
  instead of expanding scope.
- `## Do` — numbered, concrete steps naming **exact file paths**, what to clone/mirror, and the
  specifics (columns, method signatures, params).
- `## Checkpoint (green before NN+1)` — the exact tests / verification that must pass.
- **Release steps are not build steps.** A prompt that deploys beyond dev, promotes a release,
  publishes a build, or pushes to a release/prod branch must be tagged `Release-step: yes` and
  ordered LAST, after a `[DEV-VERIFIED CHECKPOINT]`. The 01→NN build loop never runs it
  autonomously (see "Production boundary").

Keep each prompt self-contained but anchored to its plan section. Match the established example at
`foaf-auth/docs/plans/todo/50-email-verification/`.

## Execution model

The build party writes the code; the writers' room never does. Execution runs the **already
vetted** prompts one at a time, in order, each scoped to one coder and one sub-app, and each
reviewed before the next begins. Nothing is built freehand: every part passes The Challenger
and The Conductor before the next part starts.

If you'd rather run the prompts yourself, stop at the gate (step 5); the prompt folder is built
to be run 01→NN in fresh sessions either way.
