# Workflow: execute-plan

**When to use:** there is already a written plan document (e.g. a `plans/todo/NN-name.md`) and
the job is to turn it into the executable, scoped prompts that build it. NOT a raw idea or a
fuzzy ask that still needs requirements (that's `feature`). A plan is an EARLY artifact, roughly
what the Analyst produces; this workflow carries it forward to vetted, decomposed prompts.

**When NOT to use:** a raw idea or fuzzy ask that still needs requirements (use `feature`). Not
for a runbook-driven ops build with no plan to decompose (use `operational-build`).

**Type:** mixed (produces a reviewed set of scoped prompts, then builds them part by part with
review. The build stage is gated twice: you approve the prompt folder before any code is
written, and the run **stops at development** — nothing deploys beyond dev, merges toward a
release/prod branch, or ships to the public until you confirm dev looks good. Build-stage rules
live in `workflows/execute-plan/build-tail.md`.)

**Inputs:** the path to the plan doc; the workspace orientation (`monorepo-orientation`); the
per-sub-app skills the plan's surfaces need.

**Outputs:** a **prompt folder beside the plan doc**, same name minus `.md`, holding
`00-index.md` + `NN-<slug>.md` scoped prompts. Example:
`foaf-auth/docs/plans/todo/50-email-verification/`. The canonical folder contract lives in
`workflows/execute-plan/prompt-folder-format.md`.

**Leans on skills:** **novadiem-engineering** (cross-project coding standards, loaded by the
Architect, Challenger, Spellwright, and every build-party coder) + `monorepo-orientation`
(routing) + whatever the plan's surfaces call for (`auth`, `mutual-credit`, `redux`,
`components`, `testing`, `docker`, `s3`, ...). Load the skill, don't duplicate its runbook.

## Execute-plan read scope (token discipline)

Always read this file first. It is the startup/core scope for triage, plan fit, chunking, prompt
decomposition, prompt review, and the human gate.

Load `workflows/execute-plan/prompt-folder-format.md` only when:
- The Spellwright is writing an `execute-plan` or `design-build` prompt folder.
- The Challenger is reviewing an `execute-plan` or `design-build` prompt folder against the
  canonical folder contract.
- A caller explicitly needs the `00-index.md` / `NN-<slug>.md` format.

Load `workflows/execute-plan/build-tail.md` only when:
- The human approves the step 5 build gate.
- A resumed run is already at worktree, preflight, build-loop, coupling, or close-out.
- Another workflow explicitly defers to the execute-plan build tail, such as `design-build`.

Do not load the build tail for triage, Architect chunking, Challenger plan/chunking review,
Spellwright prompt writing, or a prompts-only stop. Relocating rules without this gate saves
nothing.

## Steps

The **writers' room** reviews, decomposes, and re-reviews (steps 1-4). The **build party** then
builds the vetted prompts part by part only after the human approves the gate (step 5).

1. **The Architect** (**strong**) — orient (`monorepo-orientation`), read the plan in full,
   and verify it still fits the **current** code (spot-check the plan's critical files and symbol
   anchors; plans drift). Define the chunking: the ordered list of scoped units by sub-app /
   layer, the ship order across sub-apps, the analogous shipped feature each chunk mirrors, and
   the **coder who owns each chunk** — frontend/design → **The Mage**, backend/data/contract →
   **The Systemsmith**, ops/deploy/infra → **The Mechanic**. A chunk that spans two coders'
   domains is two chunks (the contract-owning chunk ships first).
   - anchors hold → proceed.
   - material drift (a branch site is gone, a product decision is now wrong) → `[CHECKPOINT]`.
2. **The Challenger** (Critic, round 1, **strong**, fresh context required) — cold-review the
   plan + chunking: requirement gaps, missing edge cases, wrong sequence, hidden cross-sub-app
   dependencies, anything that will bite the implementer. Reports findings. The Conductor
   adjudicates: route the fix back to The Architect (max 2x), note + proceed, or `[CHECKPOINT]`.
3. **The Spellwright** (Prompt Engineer, **standard**) — load
   `workflows/execute-plan/prompt-folder-format.md` and decompose the approved plan into the
   **prompt folder**, beside the plan doc. One prompt = one coherent unit a single Claude Code
   session can finish, owned by **exactly one coder** (carry the Architect's chunk assignment; tag
   every prompt `Coder:`). Each names exact files and ends with a green checkpoint. Keep every
   prompt reviewable: it should fit in one focused code-review sitting, touch only one
   domain/surface, and produce a diff The Challenger can inspect cold. If the plan chunk would
   create a sprawling diff, split it before the build stage; a 10k-line surprise is a planning
   failure, not a productivity win.
4. **The Challenger** (Critic, round 2, **strong**, fresh context required) — load
   `workflows/execute-plan/prompt-folder-format.md` and cold-review the prompts: is each
   independently executable? correct order? hidden deps between steps? are the workspace gotchas
   captured? is every checkpoint testable? Reports findings. The Conductor adjudicates: route
   the fix back to The Spellwright (max 2x), note + proceed, or `[CHECKPOINT]`.
5. **Gate** — show the human the prompt folder and get a go before building. `[CHECKPOINT]`.
   If they only wanted the prompts, stop here; that's a valid end.
6. **The Conductor** (**strong**) — if the human approves building, load
   `workflows/execute-plan/build-tail.md` and continue at build-tail step 5b. The build tail owns
   worktree creation, preflight, fixture gates, build-loop dispatch, coupling, production and
   external-action boundaries, close-out gates, fixture promotion, and run accounting.
