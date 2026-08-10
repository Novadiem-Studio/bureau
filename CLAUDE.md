# Novadiem Studio AI Framework — The Bureau

A reusable multi-agent development framework for Claude Code. Drop this entire
`agent-framework/` folder into any project root and run it.

The cast's identities, archetypes, and voice are canon in `LORE.md` (human judgment,
clear routing, focused expertise, artifact memory). This file and `agents/` are the
mechanics. When lore and mechanics disagree, mechanics win and the lore gets fixed.

## Canonical copy and drift

**Canonical upstream:** [github.com/Novadiem-Studio/bureau](https://github.com/Novadiem-Studio/bureau).
**One global install** at `~/Code/novadiem/bureau/` — do not copy into projects.
Each run: `RUN_DIR` under `<target-repo>/.bureau/runs/` (or `output/runs/` for no-target fallback). Execute builds: git worktree per run (`docs/git-worktree.md`).
Two rules:

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
Claude Code.

The subagents are real, isolated contexts. That isolation is the point: the Critic
(The Challenger) reviews the written artifacts cold, having never seen the design get
argued, so its objections are real instead of agreeable.

## Three-role model (Notary / Delegate / Principal)

| Role | One-line job | When it runs | Status |
|------|-------------|--------------|--------|
| **The Notary** | External cold attestation on a sealed artifact packet | On-demand, when an artifact is high-stakes and sealed | Live (Bundle 05) |
| **The Delegate** | Per-checkpoint automated gating verdict — flow-and-gating, not preference-modeling | Default top-level for new Bureau runs | Live |
| **The Principal** | Robin's preference model — models what Robin would choose and acts on his behalf | Explicitly deferred; no placeholder, hook, or in-code comment in this bundle | Deferred (future) |

The Delegate is a flow-and-gating role only (FR 44). It does not model Robin's preferences.
Any checklist or persona revision that introduces preference-modeling is a boundary violation —
this table is the canonical guard. The Principal is explicitly not in scope for Bundle 09.

## Default entrypoint

When Robin says "get the bureau on this," "start the agent framework," "run the bureau," or
similar, start with **The Delegate** by default. Do not require Robin to ask for the Delegate
explicitly. Read `agents/delegate.md` and run in manager/relay mode; the Delegate is the
top-level session and spawns the Conductor underneath it with `topology: integrated`.

Use direct Conductor mode only when Robin explicitly asks to bypass the Delegate, or when resuming
a legacy/non-integrated run. On Claude Code, nested subagent spawning **is** supported — the
Delegate→Conductor→specialist chain runs here (see the many `delegate-state.json` build runs across
installs) — so do **not** pre-emptively judge the integrated topology "unavailable." Host
unavailability is established **only** by an actual failed Conductor spawn at runtime
(`agents/delegate.md` EC8): attempt the Delegate first, and fall back only if the spawn literally
errors. A pre-emptive "topology unavailable" determination with no failed-spawn evidence is a
process violation. If you do fall back (Robin's bypass, a legacy resume, or a real EC8 spawn
failure), say why in one line, log the fallback in `RUN_DIR/log.md` when a run dir exists (with the
exact spawn-failure diagnostic on EC8), then follow `agents/orchestrator.md` as the Conductor.

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
2. If `~/.novadiem/usage-snapshot.json` exists, read `claude` quota once (optional;
   statusLine-owned — see `scripts/README.md`). Do not run any external usage command during the run.
3. Read `workflows/index.md` and triage the task to a workflow before creating a new run dir.
4. If `project-context.md` exists in the project root, read it for target-repo hints.
5. Start via `agents/delegate.md § Bootstrap`.

**Direct Conductor fallback path:** read `agents/orchestrator.md` core sections, then follow its
**Startup read scope (token discipline)** to load only triggered modules. In direct fallback,
run the gates below yourself; in the default Delegate path, the Delegate bootstrap owns the
same gates before it spawns the Conductor.

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

**New run:** direct Conductor mode uses
`scripts/run-start.sh <RUN_DIR> --target <repo> --workflow <id> --slug <slug>`.
Delegate mode uses the same ceremony with `--no-pointer-echo`; see
`agents/delegate.md § Bootstrap` for the full sequence. The script creates the run dir,
.gitignore protection, `state.json`, `log.md`, runs-index entry, `model-routing.json`, and
pointer enrolment.

**Run the matching workflow.** The default `feature` workflow spawns Analizer 2000 → The
Architect → Analizer 2000 (reconciliation) → The Challenger → The Cleric → The Spellwright
→ The Challenger. If no workflow fits, the `define-workflow` skill creates one.

## Agent files

| Agent | File | Role |
|-------|------|------|
| The Delegate | `agents/delegate.md` | Default top-level for new runs. Flow/gating manager; not a preference model. |
| The Conductor (Orchestrator) | `agents/orchestrator.md` | Spawned by Delegate by default; direct top-level only by explicit/fallback mode. Spawns agents, routes, resolves, decides done. |
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
