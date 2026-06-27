# Existing-project mode

This document owns the Conductor protocol for running the framework against an existing
codebase (feature/change inside current systems) instead of greenfield design.

**Pointer back:** `agents/orchestrator.md § Existing-project mode`

---

The framework defaults to greenfield (a new system from an idea). When
`project-context.md` sets **Mode: existing project**, the job changes: you are scoping a
*feature or change inside a codebase that already exists*, not designing a system from
scratch. Run the same phases, but apply these rules.

## Build a frame of reference first

Before spawning agents, build a frame of reference so you can route work correctly:
1. **Load the project's orientation skill if it has one** (e.g. `monorepo-orientation`).
   It is very likely already the map - sub-app layout, shared infra, and which skill to load
   for what. Don't rebuild what it provides; supplement only.
2. Read the **Workspace Map** in `project-context.md` if present.
3. Read the project's own top-level context: `CLAUDE.md` / `AGENTS.md` / `DOCS.md` and any
   `docs/` index. In a multi-repo workspace these usually already say what lives where.
4. Write a short `RUN_DIR/workspace-map.md` (skip if an orientation skill already covers it):
   for each relevant repo/sub-app - name, path, purpose, stack, and where its local
   CLAUDE.md/conventions live. Name the **target** of this work: which sub-app(s)/dir(s) the
   change touches.

`RUN_DIR/workspace-map.md` documents the target for the human frame of reference. It is written INTO RUN_DIR *after* creation and is **NOT** the source of the RUN_DIR location - that source is `state.json#target_repo`, resolved at run start (before creation). Call `scripts/ensure-bureau-ignored.sh R` before the first artifact write to `R/.bureau/`. If a pre-existing `.bureau/` in `R` looks foreign (no Bureau `state.json` shape in its `runs/`), `[CHECKPOINT]` before writing - same pattern as `workflows/execute-plan/build-tail.md` close-out.

This map is your frame of reference across repos. Keep it current; it persists across sessions.

## Spawn agents scoped to the right place

The workspace keeps context contained per sub-app (local CLAUDE.md + skills). Use that:
when you spawn an agent, name the specific repo/sub-app/dir it works in and point it at
that dir's local context, so it loads only what's relevant and inherits the right
conventions. Don't make an agent read the whole workspace - you hold the cross-repo map,
each agent holds its corner.

## Respect what exists

Tell every agent: this is an existing codebase. Read the target code and its conventions
first. Design and build *within* the current stack and patterns. Don't introduce a new
stack, framework, or pattern unless the change genuinely requires it - and justify it
explicitly if so.
