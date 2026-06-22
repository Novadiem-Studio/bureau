# Workflow: design-build

**When to use:** you have a **Claude Design handoff bundle** (a `.dc.html` export + a handoff
markdown) to implement in a codebase that already exists. The design IS the spec — there are no
fresh requirements to extract. This is `feature`'s Cleric-ingest head bolted onto
`execute-plan`'s gated build tail, minus the requirements analysis.

**When NOT to use:** a raw idea or fuzzy ask that still needs requirements (use `feature`). A
written plan doc with no design handoff (use `execute-plan`). A runbook-driven ops build (use
`operational-build`). A **small tweak** to existing UI — a label, a color, moving one control —
needs no Claude Design round-trip: note it for The Mage and run `execute-plan` or `bug-fix`.

**Type:** mixed (produces a design manifest + a reviewed scoped-prompt folder, then builds them
part by part with review. Gated twice: you approve the prompt folder before any code is written,
and the run **stops at development** — nothing deploys, merges toward a release/prod branch, or
ships. See `execute-plan` § Production boundary.)

**Inputs:** the path to the Claude Design handoff bundle (the `.dc.html` export + its handoff
`.md`); `project-context.md` if present; the workspace orientation (`monorepo-orientation`); the
per-sub-app skills the target surfaces need. If no bundle path is supplied, `[CHECKPOINT]` and
ask for it — this workflow does not start without a handoff.

**Outputs:** under `RUN_DIR` (`output/runs/<yyyymmdd>-<task-slug>/`): `design/manifest.md`,
`plan.md` (the build map), `prompts/` (`00-index.md` + `NN-<slug>.md`), `log.md`, `state.json`;
then — once gated — built code in an isolated worktree, merged to the **integration branch only**.

**Leans on skills:** **novadiem-engineering** (cross-project coding standards — loaded by The
Architect, The Challenger, The Spellwright, and every build-party coder) + `monorepo-orientation`
(routing) + whatever the design's surfaces call for (`react-nextjs`, `components`, `testing`, …).
Load the skill, don't duplicate its runbook.

## Steps

Run as spawned subagents (see "How to spawn an agent" and "Model routing" in
`agents/orchestrator.md`). Sequential — wait for each handoff before the next. Pass `RUN_DIR` as
an absolute path in every spawn prompt.

The **design + writers' room** ingests and scopes (steps 1–6, ending at the gate). The **build
party** then builds the vetted prompts part by part — that tail is identical to `execute-plan`
and is run by reference, not re-documented here.

1. **The Cleric** (Designer, ingest, **standard**) — read the handoff bundle in full and write a
   build-ready manifest: screens, components, tokens, states, flows, real entity names, asset
   dependencies, SEO requirements → `design/manifest.md`. Self-read `project-context.md` (and
   `spec.md` § Requirements if a prior run produced one) for brand, voice, and real entity names.
2. **The Architect** (**strong**) — orient (`monorepo-orientation`), map every manifest screen and
   component onto the **existing** routes and components (what's reused, what's new, what's
   replaced), then define the chunking: the ordered scoped units by sub-app / layer, the ship
   order, the analogous shipped surface each chunk mirrors, and the **coder who owns each chunk**
   (frontend/design → **The Mage** · backend/data → **The Systemsmith** · ops/deploy → **The
   Mechanic**) → `plan.md`. Requirements stay light — the manifest is the spec.
   - clean fit → proceed.
   - material drift (a target route is gone, a product decision is now wrong, the manifest assumes
     a surface that doesn't exist) → `[CHECKPOINT]`.
3. **The Challenger** (Critic, round 1, **strong**, fresh context required) — cold-review the
   manifest + chunking → `log.md`, findings. Specifically hunt: missing loading / empty / error /
   **stale** states, SEO requirements (server-rendered DOM, JSON-LD, meta/OG), real-asset
   dependencies (production SVGs/icons, finalized logo geometry, favicons), production-boundary
   risk, wrong sequence, hidden cross-surface deps. The Conductor adjudicates: route the fix back
   to The Architect (max 2x), note + proceed, or `[CHECKPOINT]`.
4. **The Spellwright** (Prompt Engineer, **standard**) — decompose the approved manifest + build
   map into the prompt folder → `prompts/` (`00-index.md` + `NN-<slug>.md`, format per
   `execute-plan` § Prompt folder format). One prompt = one coherent unit a single Claude Code
   session can finish, owned by **exactly one coder** (tag every prompt `Coder:`), naming exact
   files and ending in a testable checkpoint. UI prompts carry design-fidelity acceptance criteria
   (the manifest's components, tokens, and states). Split any chunk that would sprawl.
5. **The Challenger** (Critic, round 2, **strong**, fresh context required) — cold-review the
   prompts → `log.md`, findings: each independently executable? correct order? hidden deps? are
   the workspace gotchas captured? is every checkpoint testable? do UI prompts carry fidelity
   criteria? The Conductor adjudicates: route the fix back to The Spellwright (max 2x), note +
   proceed, or `[CHECKPOINT]`.
6. **Gate** — show the human the design manifest + prompt folder; get a go before building.
   `[CHECKPOINT]`. (If they only wanted the manifest + prompts, stop here — a valid plan-only end.)
7. **The Conductor** (**strong**) — build the vetted prompts exactly as **`execute-plan` steps
   5b–7**: create the isolated **worktree** on a **non-`main` integration branch** (`main` may
   auto-deploy), run preflight, then drive the build-party loop part by part — **The Mage** builds
   each chunk in the worktree; **The Cleric** (mode: review) checks each built UI screen against
   `design/manifest.md` (components, tokens, states, flow, real data — FAITHFUL or DRIFTED, drift
   routes back to The Mage); **The Challenger** cold-reviews each diff; the Conductor adjudicates,
   captures fixtures, then closes out (merge to integration branch, package install, fixture
   promotion, run accounting) → built code on the integration branch, updated `log.md`,
   `state.json`. The **production boundary** and **external-action boundary** apply unchanged: the
   run stops at **dev-verified** — nothing deploys or merges toward prod. Follow `execute-plan`
   §§ 5b–7 for the full machinery (preflight, fixture gates, coupling, close-out gates); do not
   duplicate it here.

DONE — close-out per `execute-plan` step 7 (run `scripts/account-run.sh <RUN_DIR>` last; satisfy
the `docs-sync-needed` and `lessons-append` gates). If the run stopped at the step-6 gate
(prompts only, no build), close out as a plan workflow — no commit-message or worktree guidance
applies.

The full agent specs, verdict format, and checkpoint formats live in `agents/orchestrator.md` and
the per-agent files in `agents/`. This file names the sequence and defers the build tail to
`execute-plan`; it doesn't duplicate either.
