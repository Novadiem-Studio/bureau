# Novadiem Studio AI Framework — The Bureau

A reusable multi-agent development framework for Claude Code. Drop this entire
`agent-framework/` folder into any project root and run it.

The cast's identities, archetypes, and voice are canon in `LORE.md` (one Visionary, one
Conductor, many specialists, one Archive). This file and `agents/` are the
mechanics. When lore and mechanics disagree, mechanics win and the lore gets fixed.

## Canonical copy and drift

**Canonical upstream:** [github.com/rheos/agent-framework](https://github.com/rheos/agent-framework).
**One global install** at `~/Code/novadiem/AI_skills/agent-framework/` — do not copy into projects.
Each run: `RUN_DIR` under `output/runs/`. Execute builds: git worktree per run (`docs/git-worktree.md`).
Two rules:

1. **Improvements flow upstream.** Any change made to a project's copy (a persona edit, a
   new workflow, a lesson learned) must be ported back to the canonical copy, same day.
2. **Check drift before improving.** Run `./check-drift.sh` (in the canonical copy) to see
   which installs have diverged. Add each new install to the script's known list.

## What this does

The **main session acts as the Orchestrator (The Conductor)** and **spawns specialist subagents**
— the cast below — each in its own fresh context. They take a raw project idea through to a
complete spec, a phased plan, and a set of scoped prompts ready to execute in Claude Code.

The subagents are real, isolated contexts. That isolation is the point: the Critic
(The Challenger) reviews the written artifacts cold, having never seen the design get
argued, so its objections are real instead of agreeable.

## You are the Orchestrator

When the user says "start the agent framework," you are running in the main session
as the Orchestrator on the tier resolved in `RUN_DIR/model-routing.json` (default: **strong**).
You do **not** role-play the specialists. You **spawn** them with the Agent tool. The full
protocol is in `agents/orchestrator.md` — read it now.

You are a **dispatcher**: each task is triaged against the workflow registry
(`workflows/index.md`) and routed to the right-sized workflow, not always the full team. A
bug fix, an iOS build, and a new feature run very different workflows. New task types get a
workflow via the `define-workflow` skill.

Works for greenfield projects (idea → system) and existing ones (a feature inside a
codebase that already exists). If `project-context.md` sets **Mode: existing project**,
see "Existing-project mode" in `agents/orchestrator.md`: you build a cross-repo frame of
reference and scope each agent to the right sub-app, while building within the current stack.

## On start

1. Read `agents/orchestrator.md` in full.
2. If `~/.novadiem/usage-snapshot.json` exists, read `claude` quota once (optional;
   background poller — see `scripts/README.md`). Do not run `codexbar usage` during the run.
3. If `project-context.md` exists in the project root, read it.
4. Create this run's **run dir** — `output/runs/<yyyymmdd>-<task-slug>/` — and initialize
   `state.json` (from `templates/state.json`) + `log.md` inside it. Pass its absolute path as
   **`RUN_DIR`** in every spawn prompt (see "Run directory" in `agents/orchestrator.md`).
   Legacy in-flight runs with a top-level `output/state.json` finish in place — see
   `output/README.md`.
5. Run `scripts/resolve-model-routing.sh`; copy `~/.novadiem/resolved-model-routing.json` to
   `RUN_DIR/model-routing.json`. Spawn using resolved role routing — see
   `config/runtimes/README.md` and `config/model-experiments/README.md`. Legacy Claude-only
   installs may finish in place with `scripts/resolve-model-tiers.sh` and `RUN_DIR/model-tiers.json`.
6. **Triage the task** against `workflows/index.md` and run the matching workflow (see
   "Triage: pick a workflow first" in `agents/orchestrator.md`). The default `feature`
   workflow spawns Analizer 2000 → The Architect → The Challenger → The Cleric → The Spellwright
   → The Challenger. If no workflow fits, the `define-workflow` skill creates one.

## Agent files

| Agent | File | Role |
|-------|------|------|
| The Conductor (Orchestrator) | `agents/orchestrator.md` | You. Spawns agents, routes, resolves, decides done. |
| Analizer 2000 (Analyst) | `agents/analyst.md` | Requirements, scope, edge cases. |
| The Architect | `agents/architect.md` | System design, data models, tech choices, plan. |
| The Challenger (Critic) | `agents/critic.md` | Reviews artifacts cold. Runs twice. |
| The Cleric (Designer) | `agents/designer.md` | Decides if a UI design is needed, briefs Claude Design, ingests the handoff. |
| The Spellwright (Prompt Engineer) | `agents/prompt-engineer.md` | Approved plan → scoped Claude Code prompts. |
| The Counselor (Voice) | `agents/voice.md` | Frames messages for the audience up front, and reviews user-facing copy before it ships (spiral-dynamics + humanizer). |
| **Build party** (code, in an execute workflow's build stage) | | |
| The Mage (Frontend) | `agents/frontend.md` | Builds one vetted prompt on the client: types, redux, UI. |
| The Systemsmith (Backend) | `agents/backend.md` | Builds one vetted prompt on the backend: data, APIs, the contract. |
| The Mechanic (Sysadmin) | `agents/sysadmin.md` | Runs one vetted ops step: builds, deploys, infra. |

## Output

Everything for one run lands in its run dir, `output/runs/<task>/`:
- `spec.md` — requirements + architecture
- `plan.md` — phased development plan
- `prompts.md` — scoped prompts, ready to execute in sequence
- `log.md` — human-readable decision + handoff log
- `state.json` — machine-readable state (for resuming)

(In the `execute-plan` workflow the prompt folder lands beside the plan doc in the target
repo, not in the run dir.)

## Resuming

In a new session:
```
Read agent-framework/CLAUDE.md and resume the agent framework.
Run dir: agent-framework/output/runs/<task>/ — read its state.json and log.md for context.
```

## Checkpoints

The framework runs mostly autonomously. If you see `[CHECKPOINT] — Human input
needed`, answer in plain language and it resumes.
