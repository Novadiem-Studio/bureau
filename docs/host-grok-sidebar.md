# Grok sidebar Bureau host

This host runs a Bureau-shaped cast on **Grok Bot sidebar agents and rooms**.
It is parallel to the existing Grok Task-executor host in `GROK.md`
(`scripts/run-start.sh --runtime grok`). It does **not** use Claude Code
(`claude --bg`) or Codex collaboration tools.

Robin’s standing Envoy seat on this host is the Grok Bot agent **bureau**.

## When to use

- You want the Bureau’s roles and RUN_DIR discipline with a visible sidebar
  studio (Conductor, Analizer, Architect, build party, …).
- Campaign supervision (Envoy / run-series) should live in Grok Bot, with no
  Claude in the run loop.

## When not to use

- A single cold specialist pass with no standing desks — use `GROK.md` Task
  executors only.
- The live rheo-stream Claude campaign — that stays on the Claude supervisor
  transport until Robin explicitly migrates it.
- Graded Challenger / Notary reviews that must stay cold — those still use
  **blank Task executors**, not sticky sidebar brains (see Cold roles).

## Topology

```
Envoy (bureau)  →  Delegate (gates)  →  Conductor (router)  →  specialists
                                              │
                                              ├─ warm desks: SendToAgent / rooms
                                              └─ cold roles: Task executor (persona + paths only)
```

- **Envoy** advances the *sequence* (INDEX, HANDOFF, escalation). Does not
  build or grade on its own authority (`agents/envoy.md`,
  `workflows/run-series.md` ideas; transport is Grok, not Claude).
- **Delegate** owns *one run’s* flow/gating under Envoy. Never self-grades;
  cold Task reviewers own verdicts (`agents/delegate.md`).
- **Conductor** is the **router** for that run: triage workflow, brief
  specialists with RUN_DIR paths + the ask, synthesize handoffs, decide phase
  done (`agents/orchestrator.md`). Conductor must not write spec/design/critique
  itself.
- **Truth is on disk** under `RUN_DIR` (`state.json`, `log.md`, `spec.md`,
  `plan.md`, prompts). Chat coordinates; it is not the source of truth.

## Conductor routing norms (load-bearing)

Sidebar bots *can* message each other. That must not replace Conductor or
collapse isolation into design-by-committee.

1. **Conductor (or Delegate) briefs every run ask.** A specialist does not start
   run work, open a new phase, or peer-brief another specialist unless Conductor
   or Delegate named the `RUN_DIR` paths and the ask.
2. **Rooms are status + narrow clarification only.** Allowed: “where is the
   artifact?”, “confirm path X”, blockers, short status. Forbidden: freestyle
   requirements/architecture/prompt design across desks, or skipping the written
   handoff.
3. **Handoffs are files.** Analizer → Architect goes through `RUN_DIR/spec.md`
   (and Conductor’s brief), not a DM thread that never hits disk.
4. **No peer-owned workflow.** Mage does not assign Systemsmith work; Spellwright
   does not re-scope Architect. Escalations and next-desk choices go to Conductor.
5. **Cold grades stay Tasks.** Challenger/Notary are never sticky sidebar brains
   for graded reviews — blank Task, persona + paths only.
6. **Envoy stays out of specialist peer chat** except campaign/escalation. Envoy
   briefs Delegate/Conductor; Conductor runs Build/Writers/Shop rooms.

If a desk is messaged without a Conductor/Delegate brief, it should reply with
the ask to re-route through Conductor rather than improvising the run.

## Standing desks (CreateAgent)

Seed personas from `agents/*.md`. Typical cast:

| Desk | Persona file | Notes |
|------|--------------|-------|
| Conductor | `agents/orchestrator.md` | One run at a time; does not write spec/design/critique itself |
| Analizer 2000 | `agents/analyst.md` | Requirements → `RUN_DIR/spec.md` |
| Architect | `agents/architect.md` | Design + plan from Requirements |
| Spellwright | `agents/prompt-engineer.md` | Approved plan → scoped prompts |
| Mage / Systemsmith / Mechanic | `frontend.md` / `backend.md` / `sysadmin.md` | Build party |
| Counselor | `agents/voice.md` | Audience frame / copy review |

Pilot cast (created 2026-09-11):

- **Bureau Core:** Envoy **bureau**, **Conductor**, **Analizer**, **Architect**
- **Bureau Build:** Conductor, **Mage**, **Systemsmith**, **Mechanic**
- **Bureau Writers:** Conductor, **Spellwright**, **Cleric**, **Counselor**
- **Bureau Shop:** Conductor, **Scoot**, **Tally**, **Coupler**, **Witness**
- **Delegate** seated in Bureau Core (per-run gates under Envoy; never self-grades)
- **Scribe** (long-form) — dispatch via Conductor / Writers
- Cold (Task only, not sidebar): Challenger, Notary

## Rooms (CreateChannel)

Channels cap at **6** members. Suggested layout:

| Room | Members |
|------|---------|
| Bureau Core | Envoy, Delegate, Conductor, Analizer, Architect |
| Bureau Build | Conductor, Mage, Systemsmith, Mechanic (Envoy briefs Conductor 1:1; not seated here) |
| Bureau Writers | Conductor, Spellwright, Cleric, Counselor (same) |
| Bureau Shop | Conductor, Scoot, Tally, Coupler, Witness |

Pilot rooms: **Bureau Core** (+ Delegate), **Bureau Build**, **Bureau Writers**, **Bureau Shop**.

## Cold roles (non-negotiable)

Standing agents keep memory. That breaks cold review.

**Challenger** and **Notary** for graded reviews MUST be spawned as blank
Grok **Task** executors:

- Prompt = persona file text (or path + instruction to read it) + absolute
  artifact paths under `RUN_DIR` (and review target) only.
- No parent transcript, no Envoy/Conductor debate, no prior Challenger notes
  on round 2.
- Handoff is still on-disk artifacts / structured verdict files — not chat prose.

Warm coordination may mention that a cold review is underway; the reviewer
itself must not be a sticky sidebar desk for that grade.

## Messaging and isolation

| Need | Transport |
|------|-----------|
| Brief a warm desk / room | `SendToAgent` to agent id or channel id |
| Heavy isolated specialist pass | Task `executor` (blank), same spirit as `GROK.md` |
| Cold Challenger / Notary | Task `executor` only |
| Resume / steer running Task | `MessageSubagent` / Task `resume` |
| Ask Robin | Envoy → this chat (`SendToUser`); genuine forks only |

Do not collapse the cast into the Envoy session. Nested
Envoy → Delegate → Conductor → specialist remains required. Peer DMs and room
chat do **not** authorize skipping Conductor (see Conductor routing norms).

## Relation to other hosts

| Host | Doc | Transport |
|------|-----|-----------|
| Claude Code | `docs/host-runtime.md` | Agent tool / `claude --bg` for Envoy-spawned runs |
| Codex | `docs/host-runtime.md`, `CODEX.md` | `multi_agent_v1` (+ Spark helper) |
| Grok Task-executor | `GROK.md` | Blank Task executors; **no** CreateAgent fleets as specialists |
| **Grok sidebar** (this file) | `docs/host-grok-sidebar.md` | Standing desks + rooms; cold roles still Task |

`docs/host-runtime.md` remains the spawn/resume/wait table for the Task-executor
Grok column. This file owns the sidebar cast and Envoy-on-Grok campaign loop.

## Envoy loop (sidebar host)

Adopt the *intent* of `workflows/run-series.md`:

1. Adopt charter + INDEX + HANDOFF; record who supervises.
2. Monitor the active run via **RUN_DIR** (authoritative), not chat liveness.
3. At terminal PR/integration gates: verify independently, then spawn a **cold**
   Challenger Task; never grade the PR as Envoy.
4. Relay verdicts to Conductor / run within charter grant; escalate otherwise.
5. Advance INDEX when deps are satisfied; one run at a time unless INDEX says
   otherwise.
6. Keep books on disk (INDEX, HANDOFF, run cards).

Token/quota bands from the Claude Envoy charter do not apply here unless Robin
defines a Grok budget rule for the campaign.

## Non-goals

- No Claude in this host’s run loop.
- No CreateAgent fleet as the graded Challenger.
- Envoy does not implement product code and does not author PR grades.
- Not an automatic migration of rheo-stream off Claude.



## Desk skills (Grok Bot shared)

| Desk | Skills |
|------|--------|
| Counselor | [spiral-dynamics](sand-workflow:spiral-dynamics-2), [humanizer](sand-workflow:humanizer-2) — ported from `~/.claude/skills/` |
| Cleric | [design-taste-frontend](sand-workflow:design-taste-frontend-2) (tasteskill), [impeccable](sand-workflow:impeccable-2) — https://impeccable.style |
| Architect, Spellwright, Mage, Systemsmith, Mechanic | [novadiem-engineering](sand-workflow:novadiem-engineering-2) — house engineering standards |
| Conductor | [define-workflow](sand-workflow:define-workflow-2) — when no workflow fits |
| Counselor | [counsellor](sand-workflow:counsellor-2) (general outreach); [cofi-voice](sand-workflow:cofi-voice-2) for CoFi |
| Mage / Architect / Spellwright (React-Next) | [react-nextjs](sand-workflow:react-nextjs-2) — with novadiem-engineering |
| Envoy / Witness | [bureau-run-eval](sand-workflow:bureau-run-eval-2) — measure runs / framework eval |
| Counselor / Envoy (X) | X plugin + `x-api-mcp-guide` — multi-account via labeled Connect; no `tweet.write` |
| Mage (speech product) | Grok Voice plugin — add-voice / add-dictation / add-read-aloud / debug-voice |
| Mage / Systemsmith / Mechanic (Cloudflare runs) | [cloudflare](sand-workflow:cloudflare-2), [wrangler](sand-workflow:wrangler-2), [workers-best-practices](sand-workflow:workers-best-practices-2), [durable-objects](sand-workflow:durable-objects-2), [agents-sdk](sand-workflow:agents-sdk-2) — load when the run touches that surface |
| Challenger (Task-cold) | same — Conductor/Delegate must name it in the cold spawn prompt |

Full recipes live under `/home/box/agent-data/workflows/<id>/SKILL.md`. Desks must Read those files before the relevant pass.

## Pilot checklist

- [x] Envoy seat = Grok agent `bureau`
- [x] Core desks: Conductor, Analizer, Architect
- [x] Writers/build desks: Spellwright, Cleric, Counselor, Mage, Systemsmith, Mechanic
- [x] Utilities: Scoot, Tally, Scribe, Witness, Coupler, Delegate
- [x] Rooms: Bureau Core (+ Delegate), Bureau Build, Bureau Writers, Bureau Shop
- [x] Conductor routing norms documented + mirrored in desk profiles
- [ ] Host doc merged upstream (`rheos/bureau`) when GitHub access allows
- [ ] First dry-run: Envoy briefs Conductor on a toy RUN_DIR; Analizer writes
      Requirements; Architect designs; cold Challenger Task reviews artifacts
