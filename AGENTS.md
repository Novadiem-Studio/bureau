# Novadiem Studio AI Framework — The Bureau

## Codex workspace instructions

Codex-only review instructions live in `CODEX.md`. They apply to Codex sessions in
this repository when Robin is inspecting or reviewing framework output. An explicit
Bureau start/resume request activates `CODEX.md § Native Codex Bureau run` instead.
These review instructions do not apply to Claude, The Conductor, spawned specialists,
or the framework runtime.

A reusable multi-agent development framework for Codex.
Use the global install at `~/Code/novadiem/bureau/` (do not copy into each project).

The cast's identities, archetypes, and voice are canon in `LORE.md` (human judgment,
clear routing, focused expertise, artifact memory). This file and `agents/` are the
mechanics. When lore and mechanics disagree, mechanics win and the lore gets fixed.

## Canonical copy and drift

**Canonical upstream:** [github.com/rheos/bureau](https://github.com/rheos/bureau).
**One global install** at `~/Code/novadiem/bureau/`. Two rules:

1. **Improvements flow upstream.** Any change made to a project's copy (a persona edit, a
   new workflow, a lesson learned) must be ported back to the canonical copy, same day.
2. **Check drift before improving.** Run `./check-drift.sh` (in the canonical copy) to see
   which installs have diverged. Add each new install to the script's known list.

## What this does

For new Bureau runs, the **default main session is The Delegate**. The Delegate runs in
attended manager/relay mode, spawns **The Conductor** as a resumable subagent, and handles
per-checkpoint flow/gating until a genuine fork needs Robin. The Conductor then spawns the
specialist subagents — the cast below — each in its own fresh context. They take a raw project
idea through to a complete spec, a phased plan, and a set of scoped prompts ready to execute in
Codex.

The subagents are real, isolated contexts. That isolation is the point: the Critic
(The Challenger) reviews the written artifacts cold, having never seen the design get
argued, so its objections are real instead of agreeable.

## Default entrypoint

When Robin says "get the bureau on this," "start the agent framework," "run the bureau," or
similar, start with **The Delegate** by default. Do not require Robin to ask for the Delegate
explicitly. Read `agents/delegate.md` and run in manager/relay mode; the Delegate is the
top-level session and spawns the Conductor underneath it with `topology: integrated`.
On Codex this instruction explicitly authorizes the required Bureau subagents: use
the Codex multi-agent tool surface (`multi_agent_v1.spawn_agent` with `fork_context: false`
in the current host) and the resolved model/reasoning, then resume them with
`multi_agent_v1.send_input`.

Use direct Conductor mode only when Robin explicitly asks to bypass Delegate, when resuming a
legacy/non-integrated run, or when the integrated Delegate topology is unavailable in the
current host/runtime. If falling back, say why in one line, log the fallback in `RUN_DIR/log.md`
when a run dir exists, then follow `agents/orchestrator.md` as the Conductor.

The Conductor remains the **dispatcher** inside the run: each task is triaged against the
workflow registry (`workflows/index.md`) and routed to the right-sized workflow, not always
the full team. A bug fix, an iOS build, and a new feature run very different workflows. New
task types get a workflow via the `define-workflow` skill.

Works for greenfield projects (idea → system) and existing ones (a feature inside a
codebase that already exists). If `project-context.md` sets **Mode: existing project**,
see "Existing-project mode" in `agents/orchestrator.md`: you build a cross-repo frame of
reference and scope each agent to the right sub-app, while building within the current stack.

## On start

**Default Delegate path:**

1. Read `agents/delegate.md`, then its required integrated-topology contract:
   `docs/delegate-bridge/v2-integrated.md`.
2. Read `docs/host-runtime.md` and select the host transport.
3. Read `workflows/index.md` and triage the task to a workflow before creating a new run dir.
4. If `project-context.md` exists in the project root, read it.
5. Start via `agents/delegate.md § Bootstrap`.

**Direct Conductor fallback path:** read `agents/orchestrator.md` core sections, then follow its
**Startup read scope (token discipline)** to load only triggered modules. In direct fallback,
run the gates below yourself; in the default Delegate path, the Delegate bootstrap owns the
same gates before it spawns the Conductor.

**Create this run's run dir** per `docs/run-protocol.md`: use
`<target-repo>/.bureau/runs/<yyyymmdd>-<task-slug>/` for a real target repo, or
`<install>/output/runs/<yyyymmdd>-<task-slug>/` only for the `"(no-target)"` fallback.
Initialize `state.json` (from `templates/state.json`) + `log.md` inside it. Pass its
absolute path as **`RUN_DIR`** in every spawn prompt. Legacy in-flight runs with a
top-level `output/state.json` finish in place — see `output/README.md`.

**New run:** direct Conductor mode uses
`scripts/run-start.sh <RUN_DIR> --target <repo> --workflow <id> --slug <slug> --runtime openai`
on Codex.
Delegate mode uses the same ceremony with `--no-pointer-echo`; see
`agents/delegate.md § Bootstrap` for the full sequence.

**Run the matching workflow.** The default `feature` workflow spawns Analizer 2000 → The
Architect → The Challenger → The Cleric → The Spellwright → The Challenger. If no workflow
fits, the `define-workflow` skill creates one.

## Agent files

| Agent | File | Role |
|-------|------|------|
| The Delegate | `agents/delegate.md` | Default top-level for new runs. Flow/gating manager; not a preference model. |
| The Conductor (Orchestrator) | `agents/orchestrator.md` | Spawned by Delegate by default; direct top-level only by explicit/fallback mode. Spawns agents, routes, resolves, decides done. |
| Analizer 2000 (Analyst) | `agents/analyst.md` | Requirements, scope, edge cases. |
| The Architect | `agents/architect.md` | System design, data models, tech choices, plan. |
| The Challenger (Critic) | `agents/critic.md` | Reviews artifacts cold. Runs twice. |
| The Cleric (Designer) | `agents/designer.md` | Decides if a UI design is needed, briefs Codex Design, ingests the handoff. |
| The Spellwright (Prompt Engineer) | `agents/prompt-engineer.md` | Approved plan → scoped Codex prompts. |
| The Counselor (Voice) | `agents/voice.md` | Frames messages for the audience up front, and reviews user-facing copy before it ships (spiral-dynamics + humanizer). |
| **Build party** (code, in an execute workflow's build stage) | | |
| The Mage (Frontend) | `agents/frontend.md` | Builds one vetted prompt on the client: types, redux, UI. |
| The Systemsmith (Backend) | `agents/backend.md` | Builds one vetted prompt on the backend: data, APIs, the contract. |
| The Mechanic (Sysadmin) | `agents/sysadmin.md` | Runs one vetted ops step: builds, deploys, infra. |
| **Utility spawns** (on demand) | | |
| The Notary | `agents/notary.md` | External cold attestation on a sealed artifact packet (advisory; Bundle 05). |

## Output

Everything for one run lands in its `RUN_DIR`:
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
Read ~/Code/novadiem/bureau/AGENTS.md and resume the agent framework.
Run dir: <absolute RUN_DIR> — read its state.json and log.md for context.
```

## Checkpoints

The framework runs mostly autonomously. If you see `[CHECKPOINT] — Human input
needed`, answer in plain language and it resumes.
