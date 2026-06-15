# Idea Definition — Ministry of Flow (aka Logistics)

> **Status:** idea (pre-spec)  
> **Suggested workflow:** `feature`  
> **Suggested run slug:** `society-desk`  
> **Author:** Robin (Visionary), drafted from Cursor session 2026-06-12  
> **For:** The Conductor → Analizer 2000 → Architect → … (full feature pipeline)

---

## One-liner

A local web dashboard — **Ministry of Flow (aka Logistics)** — that shows every agent-framework project install and run at a glance, with Bureau cast avatars, run status, blocked checkpoints, and links into run artifacts.

---

## Problem

The Novadiem Studio AI Framework (The Bureau) runs across multiple project installs (GrowOperative, Oriva, …). Each install tracks work in `output/runs/<date>-<slug>/` via `state.json` and `log.md`.

Today there is **no single view** of:

- Which runs are active, done, or blocked on the Visionary
- What open questions or checkpoints need a human answer
- Which framework installs have drifted from canonical
- Who in the Bureau cast is active on the current run

Operators must SSH, grep, or open multiple run directories manually. `check-drift.sh` compares framework *files* but not *run status*. OpenClaw Mission Control on rheo.ca solves a different problem (live gateway agents) and is being retired in favor of Hermes.

---

## Users

| Persona | Need |
|---------|------|
| **Robin (Visionary)** | Glance at blocked runs, open questions, and "what needs me" without opening five terminals |
| **The Conductor (orchestrator session)** | Orient quickly when resuming: which run dir, what phase, what's carried |
| **Future collaborators** | See framework run state without learning the directory layout |

Primary user: Robin, solo, on macOS, multiple repos on disk.

---

## Vision

**Ministry of Flow (aka Logistics)** is a read-only local mission control for the **The Bureau** — not for OpenClaw, Hermes, or Claude Code team tasks (though the scanner pattern is borrowed from those tools).

It should feel like the polished dark dashboard Robin liked on rheo.ca:3001 ([builderz-labs/mission-control](https://github.com/builderz-labs/mission-control)), but:

- **Data source:** filesystem (`state.json`, `log.md`) — not SQLite task store, not gateway WebSocket
- **Cast:** fixed Bureau members from `LORE.md` / `VISUAL-CANON.md` with sigils or bust avatars — not runtime agent initials
- **Scope:** framework run tracking across configured installs — not fleet ops, cron, skills hub, or GitHub sync

The UI centers on **runs** (not installs). A run is one feature/docs/execute workflow tracked under `output/runs/<yyyymmdd>-<slug>/`.

---

## Inspiration & reference (do not fork wholesale)

| Reference | Location | Take |
|-----------|----------|------|
| **builderz-labs Mission Control** | `/Users/robin/Code/novadiem/mission-control` (local clone); was on rheo.ca:3001 | UX polish: nav rail, dark theme, activity feed, kanban columns, briefing bar, smart polling |
| **`claude-tasks.ts` pattern** | `mission-control/src/lib/claude-tasks.ts` | Filesystem scanner: read dirs, parse JSON, detect stale via mtime |
| **`use-smart-poll.ts`** | `mission-control/src/lib/use-smart-poll.ts` | Visibility-aware polling; copy or adapt |
| **`check-drift.sh`** | `agent-framework/check-drift.sh` | Install registry; extend for run scanning |
| **VISUAL-CANON** | `agent-framework/VISUAL-CANON.md` | Cast names, species locks, ensemble layout; Hub mode = sigils/small busts, not full workshop art |
| **Existing runs (fixtures)** | Growoperative `output/runs/` | Real data for design/dev: notification-actionable-dismissal (done/planning), orchardly-field-test-readiness (blocked), orchardly-docs-reconcile (complete) |

**Explicit non-goals from MC:** SQLite as source of truth, OpenClaw gateway, 32 panels, Aegis review, multi-gateway, skills hub, Google OAuth for v1.

---

## Core capabilities (v1)

### 1. Install registry

- Config file lists framework installs (name + absolute path), same idea as `check-drift.sh`'s hardcoded list
- Initial installs: GrowOperative, Oriva
- Show per-install: path exists, last scan time, drift badge (optional v1.1: shell out to `check-drift.sh`)

### 2. Run scanner

- For each install, scan `output/runs/*/state.json` (and legacy `output/state.json` if present)
- Parse: `project`, `workflow`, `phase`, `phase_status`, `open_questions`, `checkpoints`, `phases_complete`, `last_updated`, `carried_items`
- Infer **active Bureau member** from last relevant handoff in `log.md` (e.g. "Spawned The Architect")
- Detect **stale** runs (no `log.md` / `state.json` mtime change in N hours while phase suggests in-progress)

### 3. Overview dashboard

- **Briefing bar:** counts of blocked, awaiting Visionary, in-progress, complete (recent)
- **Run board:** kanban-style columns mapped to run status, e.g.:
  - Planning
  - Blocked (Visionary)
  - Building
  - Complete
- Column mapping rules are a spec detail — derive from `phase` + `phase_status` + `open_questions`

### 4. Bureau cast rail

- Fixed cast from registry (`society-cast.json` or equivalent): Conductor, Analyst, Architect, Challenger, Cleric, Spellwright, Counselor, Mage, Systemsmith, Mechanic; Archive as sidebar object (not a character)
- Each member: name, subtitle, sigil SVG (v1) and/or bust WebP (v1.1), accent color
- Per selected run: show cast with status — complete ✓, active (glow), pending, not invoked
- Align layout with VISUAL-CANON ensemble grid where practical

### 5. Run detail

- Selected run: phase timeline, open questions, carried items, checkpoints
- Links / actions to open `spec.md`, `plan.md`, `prompts.md`, `log.md`, `state.json` in editor (file URLs or copy path)
- Activity feed: tail of `log.md` parsed into chronological entries (day groups like MC activity feed)

### 6. Local app

- Runs on localhost (e.g. `:3010`), macOS-first
- No cloud, no telemetry; reads only paths in install registry
- Auth: none for v1 (localhost only) or optional simple password if ever exposed beyond loopback

### 7. Live refresh

- Poll install dirs on interval; pause when browser tab hidden (smart poll pattern)
- Optional v1.1: filesystem watch on `output/runs/` for near-instant updates

---

## Out of scope (v1)

- Writing or mutating run state from the UI (read-only)
- Spawning agents or driving the Conductor from the dashboard
- OpenClaw / Hermes / Claude Code task integration
- SQLite persistence (filesystem is source of truth)
- Multi-user auth, roles, Google Sign-In
- Deploying to rheo.ca or any remote server (local tool first)
- Full MC panel parity (chat, cron, cost tracker, skills, GitHub, gateway config)
- Commissioning full ENGINE workshop portraits (sigils/busts per VISUAL-CANON Hub fidelity only)

---

## Technical direction (for Architect — not decided here)

- **Likely stack:** small Next.js app (study MC, do not fork), or Vite + minimal API — team chooses
- **Repo location:** `~/Code/novadiem/society-desk` or `agent-framework/society-desk/` — team decides relationship to canonical framework
- **API shape (illustrative):** `GET /api/installs`, `GET /api/runs`, `GET /api/runs/:install/:slug`, `GET /api/cast`
- **Assets:** `reference/cast/` under agent-framework for sigils; link from cast registry
- **Legacy runs:** support both `output/runs/` and top-level `output/state.json` (Oriva still on legacy layout)

---

## Success criteria (v1)

1. Robin opens one URL on his Mac and sees all configured installs and their runs
2. Blocked runs (open questions / checkpoints) are visually obvious within 5 seconds
3. Clicking a run shows cast status, phase, open questions, and links to artifacts
4. Growoperative's three June 2026 runs render correctly from real on-disk data without manual config per run
5. App starts with one documented command; no Docker required for v1
6. Bureau cast appears with sigil avatars (not MC-style initials circles)

---

## Open questions (for spec phase)

1. **Repo placement:** sibling to `agent-framework` vs nested inside canonical copy?
2. **Drift in v1?** Show drift badge via `check-drift.sh` or defer to v1.1?
3. **Kanban columns:** fixed set vs derived dynamically from `phase` strings (legacy runs use varied vocabulary)?
4. **Cast inference:** rules for mapping `log.md` handoffs → active member when `state.json` only has `phase`?
5. **Theme:** adopt one MC dark theme vs custom Bureau / Novadiem tokens from VISUAL-SYSTEM?
6. **Name:** Ministry of Flow (aka Logistics) — shipped; repo `society-desk` until renamed
7. **Growoperative-only dev:** use Growoperative runs as fixtures during build, or point at both installs from day one?

---

## Suggested phasing (for plan — team refines)

| Phase | Deliverable |
|-------|-------------|
| **0** | `society-cast.json` + sigil SVGs; `installs.json`; `society-runs.ts` scanner CLI that prints JSON |
| **1** | Minimal web UI: run list + briefing bar + run detail (no cast rail yet) |
| **2** | Cast rail + activity feed from `log.md` |
| **3** | Run board kanban + stale detection + file-open links |
| **4** | Drift badge, fs watch, polish |
| **1.1** | **The Witness** narrative layer — display `output/studio/briefing.md` above briefing bar |
| **1.2** | **The Coupler** seam status — show last `RUN_DIR/coupling/` verdict on run detail when present |

Ministry of Flow (aka Logistics) v1 is mechanical truth (columns, counts, links). **The Witness** writes the
executive paragraph and log digests the Desk does not generate. See `agents/witness.md`,
`LORE.md` § Studio Record.

---

## How to kick off the feature pipeline

In a project with `agent-framework/` installed (or from canonical copy):

```
Read agent-framework/CLAUDE.md and start the agent framework.

Task: Ministry of Flow (aka Logistics) — local dashboard for agent-framework run status across installs,
with Bureau cast avatars. Idea definition: agent-framework/ideas/society-desk.md

Mode: existing project where the "codebase" is new tooling in the Novadiem workspace;
data sources are existing framework run dirs on disk. Reference mission-control UX
patterns but do not fork MC. VISUAL-CANON governs cast appearance.
```

Run dir: `output/runs/20260612-society-desk/` (or current date).

---

## Appendix: example run states (fixtures)

From Growoperative install (`~/Code/foaftech/Growoperative/agent-framework/`):

| Run slug | Status (human) | Notable |
|----------|----------------|---------|
| `20260611-notification-actionable-dismissal` | Planning complete; 9 prompts ready | `phase: done`, workflow feature |
| `20260610-orchardly-field-test-readiness` | Blocked on Visionary | W2 sign-off, Spanish by ~Jun 16 |
| `20260610-orchardly-docs-reconcile` | Complete | docs committed locally |

Legacy: top-level `output/state.json` holds Job 51 invitation migration (execute-plan complete, deploy gates human-gated).

From Oriva install: legacy `output/state.json` only — build prompt 23 next.
