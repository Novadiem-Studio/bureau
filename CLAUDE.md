# Novadiem Studio AI Framework — The Bureau

A reusable multi-agent development framework for Claude Code. Drop this entire
`agent-framework/` folder into any project root and run it.

The cast's identities, archetypes, and voice are canon in `LORE.md` (one Visionary, one
Conductor, many specialists, one Archive). This file and `agents/` are the
mechanics. When lore and mechanics disagree, mechanics win and the lore gets fixed.

## Canonical copy and drift

**Canonical upstream:** [github.com/rheos/bureau](https://github.com/rheos/bureau).
**One global install** at `~/Code/novadiem/bureau/` — do not copy into projects.
Each run: `RUN_DIR` under `<target-repo>/.bureau/runs/` (or `output/runs/` for no-target fallback). Execute builds: git worktree per run (`docs/git-worktree.md`).
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

## Three-role model (Notary / Delegate / Principal)

| Role | One-line job | When it runs | Status |
|------|-------------|--------------|--------|
| **The Notary** | External cold attestation on a sealed artifact packet | On-demand, when an artifact is high-stakes and sealed | Live (Bundle 05) |
| **The Delegate** | Per-checkpoint automated gating verdict — flow-and-gating, not preference-modeling | Each checkpoint when `delegate-launcher.sh` is running; attended until v3 self-audit gate | Live (Bundle 09) |
| **The Principal** | Robin's preference model — models what Robin would choose and acts on his behalf | Explicitly deferred; no placeholder, hook, or in-code comment in this bundle | Deferred (future) |

The Delegate is a flow-and-gating role only (FR 44). It does not model Robin's preferences.
Any checklist or persona revision that introduces preference-modeling is a boundary violation —
this table is the canonical guard. The Principal is explicitly not in scope for Bundle 09.

## You are the Orchestrator

If this session is running from the `agent-framework/` directory, you are the Orchestrator.
That is the signal — not a specific phrase. Do not start coding directly; follow the protocol in
`agents/orchestrator.md` regardless of how much context you already have about the task.

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

1. Read `agents/orchestrator.md` core sections, then follow its
   **Startup read scope (token discipline)** to load only triggered modules.
2. If `~/.novadiem/usage-snapshot.json` exists, read `claude` quota once (optional;
   statusLine-owned — see `scripts/README.md`). Do not run any external usage command during the run.
3. If `project-context.md` exists in the project root, read it.

**Before creating a run dir — run these gates in order:**

**Step 0 — Resume gate (sticky existing run, EC 7 / AC 17).** Before resolving any target or
creating a run dir, check whether this is a resume of an existing run: was the Conductor
pointed at an existing run dir (the resume snippet's `Run dir:` line), OR does a run dir for
this slug already exist at `output/runs/<slug>/`? If YES: use that existing run dir **verbatim**
— whether it is a legacy `output/runs/<slug>/` or a new `.bureau/runs/<slug>/` path — read its
`state.json` and `log.md`, and continue writing there. **Skip the target-resolution and
run-dir-creation steps entirely. No relocation, no migration, no second home.** Only a genuinely
new run proceeds to the steps below.

**Target resolution (new runs only).** Resolve `R` by walking this precedence and stopping at the first hit:
1. Explicit operator/triage-named target (a `--target` or explicit REPO path in the task).
2. `project-context.md` "Target repo path" (the field in `## Git integration`, read in step 3 above).
3. Self-run detection — if no explicit target and no project-context target, but the install directory is itself the repo being worked on, `R` = the install path.
4. `(no-target)` sentinel — none of the above resolved a real git repo.

Write the resolved value to `state.json#target_repo`: an absolute path, or the literal string `"(no-target)"`.

4. Create this run's **run dir**:
   - If `target_repo` is a real path `R`: run `mkdir -p R/.bureau/runs/<yyyymmdd>-<task-slug>/`, then run `scripts/ensure-bureau-ignored.sh R` before the first artifact write. Self-run needs no special case — when `R` == the install, artifacts land in `<install>/.bureau/runs/<slug>/`.
   - If `target_repo` is `"(no-target)"`: create `<install>/output/runs/<yyyymmdd>-<task-slug>/` (FR 14 fallback — today's behavior, unchanged).
   Initialize `state.json` (from `templates/state.json`, which now carries `target_repo`) and `log.md`. Pass the resolved absolute path as **`RUN_DIR`** in every spawn prompt.
   Also write the initial `output/studio/runs-index/<slug>.json` entry (status: `"not_started"`, the seven fields from `state.json`). **Before writing, run `mkdir -p output/studio/runs-index/` and `mkdir -p output/studio/runs-index/archive/` to ensure both directories exist** — `output/studio/runs-index/` is not created by any earlier step and does not exist in a fresh install, so the first atomic write would fail without it. This is the call-site that makes "after a targeted run is created, the index contains an entry" hold (AC 13). Write atomically: write to `output/studio/runs-index/.<slug>.json.tmp`, then `mv` to `output/studio/runs-index/<slug>.json`. Validate with `python3 -c "import json,sys; json.load(open('<entry>'))" && echo OK`.
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
| **Utility spawns** (on demand) | | |
| The Notary | `agents/notary.md` | External cold attestation on a sealed artifact packet (advisory; Bundle 05). |
| The Delegate | `agents/delegate.md` | Per-checkpoint automated gating verdict — flow-and-gating role, not a preference model; runs attended until the v3 self-audit gate (Bundle 09). |

## Framework evaluation & self-improvement

`docs/evaluation/` is the framework's memory of how it has been evaluated and changed over time.
**Read it before you evaluate a run against the framework, edit a persona, or change the
review process** — so you start from what prior passes found, not from zero.

- `docs/evaluation/framework-evaluation-log.md` — the **ledger**: dated entries, what each
  evaluation pass found, what we changed in response, and open levers. Start here; append newest-on-top.
- `docs/evaluation/architect-challenger-patterns.md` — the **synthesis**: the current
  Architect→Challenger pattern taxonomy + the pre-flight checklist (encoded into `agents/architect.md`).
- `docs/evaluation/challenger-pattern-analysis.md` — the **method**: how to mine run logs into
  the synthesis, with a frozen taxonomy (extend by appending tags, never rename).

## Output

Everything for one run lands in its run dir — `<target-repo>/.bureau/runs/<task>/` for a targeted run, or `output/runs/<task>/` for a no-target fallback run:
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
Read ~/Code/novadiem/bureau/CLAUDE.md and resume the agent framework.
Run dir: <target-repo>/.bureau/runs/<task>/ — read its state.json and log.md for context.
```
(For fallback / legacy runs: `output/runs/<task>/` still works — the Conductor uses whichever path is pointed at.)

The Conductor honors the pointed-at run dir **verbatim** — it reads `state.json`/`log.md` and continues
writing there, and does NOT relocate or migrate an existing run to `.bureau/runs/` (or anywhere else),
nor create a duplicate run dir. The new `.bureau/runs/` location applies only to newly-created runs
(resume-sticky, EC 7 / AC 17).

## Archiving

When a run is finished — shipped/closed out, nothing left to do — **archive it**: move the
whole run dir to its archive location.

- **Targeted run** (run dir lives at `R/.bureau/runs/<slug>/`): move to `R/.bureau/archive/<slug>/`:
  ```bash
  mv <target-repo>/.bureau/runs/<slug> <target-repo>/.bureau/archive/<slug>
  ```
- **Fallback run** (run dir lives at `output/runs/<slug>/`): move to `output/archive/<slug>/` (today's behavior, unchanged):
  ```bash
  mv output/runs/<slug> output/archive/<slug>
  ```

The archive location tracks wherever the run dir already lives — no second copy, no self-run special case. It's a plain local move of the entire dir (every artifact, no state change). Refuse if the destination already exists. "Archive it" means exactly this.

At archive, also update the run's index entry: set `status: "archived"`, update `run_dir` to the archive path, and move the entry file from `output/studio/runs-index/<slug>.json` to `output/studio/runs-index/archive/<slug>.json`. This index-update step depends on the run-index defined in Phase C1 (Prompt 5) — if Phase C1 has not yet shipped, omit the index step and add it when Prompt 5 lands.

## Checkpoints

The framework runs mostly autonomously. If you see `[CHECKPOINT] — Human input
needed`, answer in plain language and it resumes.
