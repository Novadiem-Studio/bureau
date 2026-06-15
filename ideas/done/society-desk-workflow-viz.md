# Idea Definition — Ministry of Flow (aka Logistics): Workflow Registry Visualizer

> **Status:** idea (pre-spec)
> **Suggested workflow:** `feature`
> **Suggested run slug:** `society-desk-workflow-viz`
> **Mode:** existing project (a feature inside the `society-desk` app; data source = each
>   install's `agent-framework/workflows/`)
> **Author:** Robin (Visionary), drafted 2026-06-13
> **For:** The Conductor → Analizer 2000 → The Architect → … (feature pipeline, existing-project mode)

---

## One-liner

A read-only **Workflows** view in Ministry of Flow (aka Logistics) that parses each install's workflow registry
(`workflows/index.md` + `workflows/<name>.md`) and renders every registered workflow as a
**structured pipeline** — the ordered agents, their power levels (tiers) and the models those
levels resolve to, what each reads and writes, the human checkpoints, and the skills loaded —
so you can see at a glance what each workflow actually does. Built so a later editor is a clean
follow-on, not part of v1.

---

## Problem

The framework's behavior is defined by its workflow registry, but that definition is only
legible by opening `workflows/index.md` and reading each workflow file's prose Steps. There is
no visual map of:

- which agents run, in what order, at which **power level (tier)**, and which **model** that
  level resolves to under the active runtime
- what each step reads and writes (the I/O handoff chain)
- where the human checkpoints sit (design-model, design handoff, dev-verified gates)
- which skills each workflow loads (`novadiem-engineering`, `monorepo-orientation`, per-sub-app)

The level→model mapping is deliberately defined **separately** from the stage→level
assignment (tiers in `config/model-policy.v2.json` + the workflow files; models per tier in
`config/runtimes/*.json`), and there is no view that shows the two together.

Ministry of Flow (aka Logistics) already shows run **state** (`state.json` / `log.md`). It does not show the
**definitions** those runs execute. Understanding or explaining a workflow today means tracing
markdown by hand.

---

## Users

| Persona | Need |
|---------|------|
| **Robin (Visionary)** | See what a workflow does without reading the files; spot when a workflow is heavier or lighter than the task needs |
| **The Conductor** | A quick visual reference during triage — what each registered workflow entails before picking one |
| **Future collaborators** | Understand the Bureau pipeline without learning the file layout |

Primary user: Robin, solo, macOS, the Ministry of Flow (aka Logistics) app already running on `:3010`.

---

## What it does (v1 — read-only, structured pipeline)

1. **Workflow source** — for each configured install, read `<install>/workflows/index.md`
   (the registry table: name, when-to-use, type, summary) and each `workflows/<name>.md`.
2. **Parser** — parse each workflow file into a structured model: ordered **steps**, each with
   agent/role, **tier** (standard/strong/…), **reads**, **writes**, **returns/handoff**, and
   **checkpoints**; plus workflow-level type, when-to-use, inputs, outputs, and "Leans on
   skills". **Graceful fallback:** a step that does not parse cleanly renders as its raw
   markdown rather than being dropped.
3. **Workflows view** — a new tab beside Runs / Sessions. Left: the registry list (name · type
   · when-to-use). Select one → render its pipeline: numbered agent nodes with **tier (power
   level) + the model it resolves to** + I/O, human-checkpoint markers inline (◆), skills
   badges, and the workflow's type/inputs/outputs. Reuse the existing cast accents/sigils so
   agents look consistent with the run board.
4. **Per-step skills** — where derivable, show which skills an agent loads at a step (e.g.
   Architect / Challenger / coders / Spellwright → `novadiem-engineering`; `execute-plan`
   Architect → `monorepo-orientation`), from `DEPENDENCIES.md` + each workflow's "Leans on
   skills" line. If full per-step derivation is brittle, fall back to workflow-level skills.
5. **Model routing per stage (power levels)** — surface the framework's two-layer routing so
   each stage shows both its power level and the concrete model:
   - **Per stage:** the assigned **tier** (cheap / standard / strong / frontier / escalated)
     and, for the active runtime, the **model** it maps to (e.g. `strong → opus`). The workflow
     file names a tier per step as documentation; the authoritative default is
     `config/model-policy.v2.json` (`roles.<role>.default_tier` + `allowed`). Where the
     workflow-named tier and the policy default differ, flag it (resolved routing wins).
   - **Level → model panel:** a small view of the active runtime adapter's tier→model table
     (`config/runtimes/<runtime>.json` `.tiers`, e.g. `claude.json`: standard→sonnet,
     strong→opus), with a runtime switcher (claude / openai / openrouter / hermes). This is the
     "what model goes to what level" definition, maintained separately from the stage→level
     assignment.
   - **v1 is read-only:** the JSON files are the source of truth and are edited by hand; the
     viz reflects them on reload. **Later (editor follow-on):** a per-stage tier dropdown and a
     tier→model editor that write the JSON back (same deferred-editor caution about git-tracked
     config).
6. **Scaffold for an editor** — the source layer and types are designed so a future write path
   (edit workflow files / `index.md`, and the tier / tier→model JSON above) slots on top
   without re-architecting. **v1 writes nothing.**

---

## Out of scope (v1)

- Editing or creating workflows from the UI (writes to git-tracked, canonical-upstream
  framework files — its own deliberate effort, see Open Questions).
- Running or triggering a workflow, or spawning agents.
- Overlaying a live run's current step onto its workflow pipeline (nice v1.1; the Runs view
  already covers live state).
- Deep parsing of agent persona files — the skills mapping uses the registry + `DEPENDENCIES.md`,
  not a full persona parse.

---

## Technical direction (for the Architect — grounding, not decided here)

The `society-desk` app already has the exact seams this needs; mirror the **Sessions** axis.

- **View switch:** `app/page.tsx` has `type View = "runs" | "sessions"` with a
  `<nav className="tabs">` and `?tab=` URL sync. Add `"workflows"`; mirror `SessionsView`.
- **Data seam:** mirror `lib/run-source.ts` — a `WorkflowSource` interface in `types`, an
  `FsWorkflowSource` implementation, a `getWorkflowSource()` singleton; only a new
  `/api/workflows/[install]` route imports it. Keeps the future-remote seam intact.
- **Types:** add `WorkflowRegistry` / `Workflow` / `WorkflowStep` to `types/index.ts` as the
  durable contract (the same way `Overview` / `RunDetail` are defined source-agnostically).
- **Config:** workflow dirs derive from existing `config/installs.json` paths
  (`<install.path>/workflows/`). No new config file. Cast accents come from
  `config/society-cast.json`, already served by `/api/cast`.
- **Model routing source:** read `config/model-policy.v2.json` (role → `default_tier` +
  `allowed`) and each `config/runtimes/*.json` (tier → model, per runtime; `default_runtime` is
  `claude`). A small `ModelRouting` type carries the per-runtime tier→model map plus per-role
  tiers. The viz reads this **static config** directly — it does not shell out to
  `scripts/resolve-model-routing.sh` (that resolver is the run-time equivalent, out of scope here).
- **Rendering:** prefer a hand-rolled CSS/flex node list (the app uses only `lucide-react`
  today — no heavy graph dependency unless the Architect justifies one).
- **Tests:** the parser gets unit tests with the real workflow files as fixtures (this repo
  already tests parsers — `scanner.test.ts`, `log-parser.test.ts`, `phase-logic.test.ts`).
  Gate: `npm run check` (vitest + tsc + eslint).

---

## Success criteria (v1)

1. A **Workflows** tab lists every workflow registered in the canonical install's `index.md`.
2. Selecting `feature` renders its 6-step pipeline with tiers, both human checkpoints, I/O per
   step, and the `novadiem-engineering` skill — matching `workflows/feature.md` without hand edits.
3. `execute-plan` renders its build-stage loop (coders, per-prompt review) and the
   `monorepo-orientation` skill.
4. A workflow whose steps do not fully parse still shows its registry row and raw steps — no
   crash, no silent drop.
5. Multiple installs supported; switching install shows that install's registry.
6. `npm run check` passes; the parser is covered by unit tests against the real files.
7. Each stage shows its **power level (tier)** and the **model** that level resolves to under
   the active runtime (e.g. The Architect → strong → opus on the `claude` runtime).
8. A **level→model panel** shows the active runtime's full tier→model table and lets you switch
   runtime (claude / openai / openrouter / hermes); hand-editing the underlying JSON and
   reloading is reflected.
9. Where a workflow's step-named tier differs from the role's policy default, the divergence is
   visible (resolved routing wins).

---

## Open questions (for spec phase)

1. **Standalone vs Ministry of Flow (aka Logistics) v2:** drafted as a standalone idea doc; team may fold it into
   the `society-desk` lineage instead.
2. **Per-step skill derivation depth:** full per-step (richer, more brittle) vs workflow-level
   only (robust). Recommend workflow-level first, per-step where cheap.
3. **Pipeline rendering:** hand-rolled flex node list (recommended, no new dep) vs a graph lib.
4. **Run overlay:** show a live run's current step on its workflow pipeline now, or defer to
   v1.1? Recommend defer.
5. **Which installs' registries:** all configured installs (recommended, canonical primary) vs
   canonical-only for v1.
6. **Editor follow-on:** confirm the editor is a separate later run, and whether it should ever
   write canonical files directly vs propose a diff for human commit (respect the drift /
   same-day-upstream rules in `agent-framework/CLAUDE.md`).
7. **Stage tier source of truth:** the workflow file names a tier per step (prose) while
   `model-policy.v2.json` holds the per-role default. Does the viz show both and flag drift
   (recommended), or pick one as canonical?
8. **Routing editor write target:** the future per-stage dropdown edits which file — the
   per-role `model-policy.v2.json`, the tier→model `runtimes/*.json`, or a per-run override?
   (Recommend the policy / runtime JSON; never rewrite the workflow prose.)

---

## Suggested phasing (team refines)

| Phase | Deliverable |
|-------|-------------|
| **0** | `WorkflowSource` + parser; a `scan`-style CLI that prints `WorkflowRegistry` JSON; unit tests against the real workflow files |
| **1** | `/api/workflows/[install]` + a Workflows tab listing the registry (When-to-use / Type / Summary) |
| **2** | Structured pipeline render for a selected workflow (agent nodes, tiers, I/O, checkpoints) |
| **2b** | Model routing per stage: tier + resolved model on each node; level→model panel with runtime switch (reads `model-policy.v2.json` + `runtimes/*.json`) |
| **3** | Skills badges + graceful raw-step fallback + multi-install switch + policy-vs-prose tier drift flag + polish |
| **1.1** | Live run overlay onto a workflow pipeline; (separate effort) the **editor** |

---

## How to kick off the feature pipeline

In the canonical install:

```
Read agent-framework/CLAUDE.md and start the agent framework.

Task: Ministry of Flow (aka Logistics) — add a read-only Workflows view that parses each install's workflow
registry (workflows/index.md + workflows/<name>.md) and renders each workflow as a
structured pipeline: agents; the power-level tier per stage AND the model it resolves to;
I/O; human checkpoints; skills. Include a level->model panel that reads the routing config
(config/model-policy.v2.json for role->tier, config/runtimes/*.json for tier->model) with a
runtime switcher.
Idea definition: agent-framework/ideas/society-desk-workflow-viz.md

Mode: existing project. Target sub-app: ~/Code/novadiem/society-desk (Next.js).
Mirror the existing Sessions view + run-source seam. Read-only v1 (JSON edited by hand);
do NOT add a workflow editor or a routing-save dropdown in v1.
```

Run dir: `output/runs/<yyyymmdd>-society-desk-workflow-viz/`
