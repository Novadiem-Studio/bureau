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
ships. See `workflows/execute-plan/build-tail.md § Production boundary — hard stop`.)

**Inputs:** the path to the Claude Design handoff bundle (the `.dc.html` export + its handoff
`.md`); `project-context.md` if present; the workspace orientation (`monorepo-orientation`); the
per-sub-app skills the target surfaces need. If no bundle path is supplied, `[CHECKPOINT]` and
ask for it — this workflow does not start without a handoff.

**Outputs:** under `RUN_DIR` (see `docs/run-protocol.md`): `design/manifest.md`,
`plan.md` (the build map), `prompts/` (`00-index.md` + `NN-<slug>.md`), `log.md`, `state.json`;
then — once gated — built code in an isolated worktree, delivered through a linked pull request
for public GitHub repositories (or the recorded local fallback), merged to the **integration branch only**.

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
   `workflows/execute-plan/prompt-folder-format.md`). One prompt = one coherent unit a single Claude Code
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
7. **The Conductor** (**strong**) — load `workflows/execute-plan/build-tail.md` and build the
   vetted prompts exactly as its **build-tail steps 5b–7**: create the isolated **worktree** on a
   **non-`main` integration branch** (`main` may auto-deploy), **stage the design source into the
   worktree** (below), run preflight, then drive the
   build-party loop part by part — **The Mage** builds
   each chunk in the worktree; **The Cleric** (mode: review) checks each built UI screen against
   `design/manifest.md` (components, tokens, states, flow, real data — FAITHFUL or DRIFTED, drift
   routes back to The Mage); **The Challenger** cold-reviews each diff; the Conductor adjudicates,
   captures fixtures, then closes out (PR/local merge to integration branch, package install, fixture
   promotion, run accounting) → built code on the integration branch, updated `log.md`,
   `state.json`. The **production boundary** and **external-action boundary** apply unchanged: the
   run stops at **dev-verified** — nothing deploys or merges toward prod. Follow
   `workflows/execute-plan/build-tail.md` for the full machinery (preflight, fixture gates,
   coupling, close-out gates); do not duplicate it here.

## Staging the design source into the worktree (step 7, before the first build prompt)

**The whole handoff bundle goes into the worktree under `reference/`.** Immediately after the
worktree is created and before any build prompt is dispatched:

```sh
mkdir -p "$WORKTREE/reference"
cp -R "<handoff-bundle-dir>" "$WORKTREE/reference/design-handoff"
cp "$RUN_DIR/design/manifest.md" "$WORKTREE/reference/manifest.md"
# keep it off the branch — present on disk, invisible to git
echo 'reference/' >> "$(git -C "$WORKTREE" rev-parse --git-common-dir)/info/exclude"
```

Note the exclude path: for a worktree it is the **common** dir (`--git-common-dir`, the main
repo's `.git`), NOT the per-worktree gitdir — writing to the latter silently does nothing.

**Why this is mandatory, not optional.** A worktree is a fresh checkout: anything gitignored in
the repo (a handoff bundle usually is) and anything under `.bureau/` (always gitignored) does not
exist inside it. A coder working in the worktree therefore cannot resolve a design citation
unless the source has been staged. The failure is silent and expensive — the builder invents a
plausible value, and it costs a Cleric round-trip per gap to catch.

**The Spellwright's obligation follows from this:** every design citation in a prompt must be
resolvable from the worktree. A bare line reference (`HTML:195-221`) with no path is unusable —
cite `reference/design-handoff/<file>` so the builder can open it. A prompt that cites a literal
value (a hex, a radius, a font weight) must point at the file that states it.

DONE — close-out per `workflows/execute-plan/build-tail.md` step 7 (run
`scripts/account-run.sh <RUN_DIR>` last per `docs/run-accounting.md`; satisfy the
`docs-sync-needed` and `lessons-append` gates). If the run stopped at the step-6 gate (prompts
only, no build), close out as a plan workflow — no commit-message or worktree guidance applies.

The full agent specs, verdict format, and checkpoint formats live in `agents/orchestrator.md` and
the per-agent files in `agents/`. This file names the sequence and defers the build tail to
`workflows/execute-plan/build-tail.md`; it doesn't duplicate either.
