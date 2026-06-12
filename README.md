# Novadiem Studio AI Framework — Quick Reference

**The Society of Specialists** — a multi-agent dev framework where the **main session
orchestrates and spawns real subagents**. Each specialist runs in its own fresh context,
so reviews are genuinely independent instead of one Claude critiquing its own earlier
reasoning. Who the specialists *are* — names, archetypes, voice — is canon in `LORE.md`.
Visual poster family (THE CURRENT · THE HUB · THE ENGINE) is canon in `VISUAL-SYSTEM.md`;
character appearance locks live in `VISUAL-CANON.md`.

## Canonical copy

The copy at `~/Code/novadiem/AI_skills/agent-framework/` is the upstream. Project installs
drift — port any improvement made in a project back to the canonical copy, and run
`./check-drift.sh` there to see which installs have diverged (add new installs to its list).
Run `./check-framework.sh` in the canonical copy to lint workflow registry, `RUN_DIR`
conventions, model tiers, and handoff blocks. External skills are documented in
`DEPENDENCIES.md`.

## Model policy

Spawn every specialist on **sonnet** by default. Escalate to **opus** only when The Conductor
judges a sonnet pass inadequate (after routed fixes) or the human flags exceptional risk.
Details: `agents/orchestrator.md` § Model tiers.

## First time setup

```bash
# Copy the agent-framework folder into your project root
cp -r agent-framework/ /your/project/

# Optionally create a project context file
cp agent-framework/templates/project-context-template.md /your/project/project-context.md
# Fill it in before starting
```

### Greenfield vs existing projects

For a brand-new project, use `new-project.sh` (it scaffolds the folder and a root
CLAUDE.md pointer). For an **existing** codebase, copy `agent-framework/` in by hand,
set **Mode: existing project** in `project-context.md`, and fill in the Workspace Map.
Do **not** overwrite the project's own CLAUDE.md — either append one pointer line, or
just invoke the framework explicitly ("Read agent-framework/CLAUDE.md and act as the
Orchestrator"). In existing mode the Orchestrator builds a cross-repo map and scopes each
agent to the right sub-app, building within the current stack rather than picking a new one.

## Start a new project

```bash
cd /your/project
claude
```

Then say:

```
Read agent-framework/CLAUDE.md and start the agent framework.
My project idea is: [YOUR IDEA IN PLAIN LANGUAGE]
```

The main session becomes the Orchestrator and spawns each specialist as a subagent
in sequence. You watch the handoffs roll in.

## Resume an interrupted session

```
Read agent-framework/CLAUDE.md and resume the agent framework.
Run dir: agent-framework/output/runs/<task>/ — read its state.json and log.md for context.
```

## Concurrent runs (one install, many terminals)

Each run owns its own directory under `output/runs/<yyyymmdd>-<task-slug>/`, so multiple
sessions can run the framework on the SAME install at the same time — e.g. an orchardly-app
task in one terminal and a foaf-auth task in another. You do not need a second copy of
`agent-framework/`. Two rules: don't run two tasks that touch the same repo in parallel,
and stagger test-suite steps if two runs share a dev database. Details in "Run directory"
in `agents/orchestrator.md`.

## How it runs

| Step | Who | Spawned as | Produces |
|------|-----|-----------|----------|
| 1 | Analizer 2000 (Analyst) | subagent | spec.md (Requirements) |
| 2 | The Architect | subagent | spec.md (Architecture), plan.md |
| — | Design-model checkpoint | **you** | a 2-minute read of the design summary; go, or a model correction |
| 3 | The Challenger (Critic), round 1 | subagent | review in log.md, APPROVED/REVISE |
| 4 | (loop) routed agent | subagent | revised output, max 2 loops |
| 5 | The Cleric (Designer), brief | subagent | design/brief.md, or "not needed" |
| — | Design handoff | **you** | export from Claude Design into design/handoff/ |
| 6 | The Cleric (Designer), ingest | subagent | design/manifest.md |
| 7 | The Spellwright (Prompt Engineer) | subagent | prompts.md (builds against the manifest) |
| 8 | The Challenger (Critic), round 2 | subagent | review of prompts, APPROVED/REVISE |

If there's no UI surface, The Cleric returns "not needed" and steps 5–6 and the
handoff are skipped.

The Orchestrator (main session) never writes spec/design/critique/prompt content
itself. It spawns, reads handoffs, routes on the Critic's verdict, and decides done.

## Workflows (the dispatcher)

The Orchestrator is a **dispatcher**. On every task it triages against the workflow
registry (`workflows/index.md`) and runs the matching workflow — not always the full team.
The table above is the `feature` workflow (the heaviest). Lighter workflows do far less; an
execute-type workflow (e.g. an iOS build) often just loads an existing skill/runbook and
follows it.

- Workflows live in `workflows/`, one file each. `feature` ships by default.
- New task types (bug fix, iOS build, Android build, …) are added one at a time via the
  **define-workflow** skill — built as they come, reusing existing project skills.
- In existing multi-repo projects, the Orchestrator loads the project's orientation skill
  (e.g. `monorepo-orientation`) for its cross-repo bearings instead of rebuilding a map.

## Output files

All inside the run's directory, `output/runs/<task>/`:

| File | Contents |
|------|----------|
| `spec.md` | Requirements + architecture |
| `plan.md` | Phased development plan |
| `prompts.md` | Scoped Claude Code prompts — execute these |
| `log.md` | Human-readable handoff + decision log |
| `state.json` | Machine-readable state (for resuming) |

## When the framework pauses

If you see `[CHECKPOINT]` — answer the question in plain language. The framework
resumes after your response. It only checkpoints on an unresolvable ambiguity, a
blocker that needs a product call, or after looping twice on the same issue.

## Agent files

| Agent | File | When it runs |
|-------|------|-------------|
| The Conductor (Orchestrator) | `agents/orchestrator.md` | Main session, throughout |
| Analizer 2000 (Analyst) | `agents/analyst.md` | Phase 1 — requirements |
| The Architect | `agents/architect.md` | Phase 2 — system design + plan |
| The Challenger (Critic) | `agents/critic.md` | Review rounds (after design + after prompts) |
| The Cleric (Designer) | `agents/designer.md` | Design handoff to Claude Design (only if there's a UI) |
| The Spellwright (Prompt Engineer) | `agents/prompt-engineer.md` | Scoped prompts (against the design manifest) |
| The Counselor (Voice) | `agents/voice.md` | Frames messages for the audience, and reviews copy before it ships (spiral-dynamics + humanizer) |
| **Build party** (writes code, in an execute workflow's build stage) | | |
| The Mage (Frontend) | `agents/frontend.md` | Builds one vetted prompt: types, redux, UI |
| The Systemsmith (Backend) | `agents/backend.md` | Builds one vetted prompt: data, APIs, contract |
| The Mechanic (Sysadmin) | `agents/sysadmin.md` | Runs one vetted ops step: builds, deploys, infra |

## Customising

- **Per-project behavior belongs in triage, not in forked personas.** Add or adjust a
  workflow in `workflows/` (via the `define-workflow` skill) and let `workflows/index.md`
  route to it. Project facts (brand, audience, stack, mode) go in `project-context.md`.
- Edit an agent file only when its behavior is wrong *everywhere* — it's read fresh on
  every spawn, and the edit must be ported to the canonical copy (see "Canonical copy").
- Adjust `max_critic_loops` in the run's `state.json` for more or fewer revision cycles.
- The cast and its lore (`LORE.md`) are the same in every project — one Society, many studios.

## Note on the subagent model

Subagents are spawned via Claude Code's Agent tool with `general-purpose` type and
pointed at their persona file. They run in the project's working directory and read
and write via absolute paths the Orchestrator supplies. They share the filesystem,
not the conversation — that's the isolation the framework depends on.
