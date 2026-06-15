# Workflow: studio-briefing

**When to use:** The Visionary or Conductor needs a **studio-wide** picture — not one run's
Archive. Active jobs across installs, what's blocked, executive summary, or a digest of a long
`log.md`. Run at session start, after a checkpoint, or on demand. Complements **Ministry of Flow (aka Logistics)**
(mechanical kanban) with narrative synthesis from **The Witness**.

**When NOT to use:** a single run's own status — read its `log.md` directly. Not for making changes; The Witness is read-only.

**Type:** mixed (spawn only — read-only, no code changes)

**Inputs:** install paths to scan (default: canonical framework `output/runs/` plus configured
legacy installs); optional `TARGET_RUN` for digest mode.

**Outputs:** under `output/studio/` on the canonical framework install:

- `briefing.md` — executive summary (default mode)
- `resume.md` — short active-run card (resume mode)
- `digests/<slug>.md` — single-run narrative (digest mode)
- `runs-snapshot.json` — optional machine index for Ministry of Flow (aka Logistics) v1.1+

**Leans on skills:** none. Optional: run `scripts/list-runs.sh` when it exists.

## Install registry

Default installs to scan (extend in spawn prompt or `config/installs.json` when added):

| Name | Path |
|------|------|
| Canonical | `~/Code/novadiem/AI_skills/agent-framework` |
| GrowOperative (legacy) | `~/Code/foaftech/Growoperative/agent-framework` |
| Oriva (legacy) | `~/Code/novadiem/oriva/agent-framework` |

Each install: read `output/runs/*/state.json` and log tails. Skip dirs without `state.json`
with a note in install health.

## Steps

1. **The Conductor** resolves mode from the task:
   - "what's running / briefing / morning check" → `briefing`
   - "resume bureau" / session start → `resume`
   - "digest this run" / "what happened in X" → `digest` + `TARGET_RUN`
2. **The Witness** (**standard**, fresh context) — read run dirs and logs for the resolved mode; pass `STUDIO_ROOT`, `INSTALL_PATHS`, `MODE`, and `TARGET_RUN` if digest. Writes to `output/studio/` only. → `output/studio/{briefing.md | resume.md | digests/<slug>.md}`
3. **The Conductor** surfaces the top of `briefing.md` or `resume.md` to the Visionary. Log spawn
   in the **current** `RUN_DIR/log.md` if a society run is active; otherwise append one line to
   `output/studio/briefing-log.md`.

No Challenger pass — Witness is read-only synthesis. If a summary looks wrong, re-spawn with a
narrower scope or run `digest` on one run.

## Relation to Ministry of Flow (aka Logistics)

| Layer | Role |
|-------|------|
| **Ministry of Flow (aka Logistics)** (v1) | Scanner, columns, counts, links — mechanical truth |
| **The Witness** | Executive prose, log digestion, "what needs you" narrative |
| **Ministry of Flow (aka Logistics)** (v1.1+) | May display `output/studio/briefing.md` above the briefing bar |

The Archive stays **per run**. The **Studio Record** (`output/studio/`) is cross-run memory
written by The Witness.
