# Workflow: feature

**When to use:** a new feature, a new product, a substantial change, or anything that needs
a fresh requirements + architecture + design + build plan. The default for greenfield
projects. NOT for one-line bug fixes or operational builds — those get lighter workflows.

**When NOT to use:** a one-line bug fix or a runbook-driven operational build — those get lighter workflows (`bug-fix` once registered, or `operational-build`). Not for reviewing or framing copy (use `copy-review` / `message-framing`).

**Type:** plan (produces a spec, plan, and scoped prompts; you implement them)

**Inputs:** the project idea or task brief; `project-context.md` if present; in existing
projects, the workspace orientation (see "Existing-project mode" in `agents/orchestrator.md`).

**Outputs:** under `RUN_DIR` (`output/runs/<yyyymmdd>-<task-slug>/`): `spec.md`, `plan.md`,
`prompts.md`, `log.md`, `state.json`, plus `design/` artifacts if a UI is involved.

**Leans on skills:** **novadiem-engineering** (the cross-project coding standards) — loaded by
The Architect, The Challenger, and The Spellwright so design, review, and prompts hold the
same bar. In existing projects, agents also load the relevant per-sub-app skills when they
work in that area. See `DEPENDENCIES.md`.

## Steps

Run these as spawned subagents (see "How to spawn an agent" and "Model routing" in
`agents/orchestrator.md`). Sequential — wait for each handoff before the next. Pass
`RUN_DIR` as an absolute path in every spawn prompt.

1. **Analizer 2000** (Analyst, **standard**) — requirements, scope, edge cases → `spec.md` (Requirements)
2. **The Architect** (**strong**) — system design + plan → `spec.md` (Architecture), `plan.md`
3. **[DESIGN-MODEL CHECKPOINT]** (mandatory) — The Conductor shows the human the Architect's
   design-model summary + over-baseline mechanism list, waits for go or a model correction
   (see "Design-model checkpoint" in `agents/orchestrator.md`)
4. **The Challenger** (Critic, round 1, **strong**, fresh context required) — review spec + plan cold → `log.md`, findings
   - The Conductor adjudicates: route the fix back (max 2x), note + proceed, or CHECKPOINT
5. **The Cleric** (Designer, brief, **standard**) — is there a UI surface? → `design/brief.md`, or DESIGN: NOT NEEDED
   - NEEDED → `[DESIGN HANDOFF]` checkpoint, wait for the exported bundle
6. **The Cleric** (Designer, ingest, **standard**) — read the handoff bundle → `design/manifest.md`
7. **The Spellwright** (Prompt Engineer, **standard**) — approved spec/plan (+ manifest) → `prompts.md`
8. **The Challenger** (Critic, round 2, **strong**, fresh context required) — review the prompts → `log.md`, findings (The Conductor adjudicates)

The full agent specs, verdict format, and checkpoint formats live in `agents/orchestrator.md`
and the per-agent files in `agents/`. This file just names the sequence; it doesn't
duplicate them.
