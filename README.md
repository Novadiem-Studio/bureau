# Novadiem Studio AI Framework — Quick Reference

**The Bureau** — a multi-agent dev framework where the **main session
orchestrates and spawns real subagents**. Each specialist runs in its own fresh context,
so reviews are genuinely independent instead of one warm model critiquing its own earlier
reasoning. Who the specialists *are* — names, archetypes, voice — is canon in `LORE.md`.
Visual poster family (THE CURRENT · THE HUB · THE ENGINE) is canon in `VISUAL-SYSTEM.md`;
character appearance locks live in `VISUAL-CANON.md`.

## Repository

**GitHub:** [github.com/rheos/bureau](https://github.com/rheos/bureau) (private)

```bash
git clone git@github.com:rheos/bureau.git
cd bureau
./check-framework.sh
```

Robin’s working checkout: `~/Code/novadiem/bureau/`. **One global install**
— do not copy the framework into each project. Each job gets its own `RUN_DIR`; execute builds
also get a **git worktree** off `devel` (`docs/git-worktree.md`). Legacy per-project copies:
`./check-drift.sh`. Lint: `./check-framework.sh`. External skills: `DEPENDENCIES.md`.

## Model policy

**Provider-neutral routing** — resolved from `config/model-policy.v2.json` + runtime adapters
(`config/runtimes/*.json`) + provider-neutral experiments (`config/model-experiments/*.json`)
using `scripts/resolve-model-routing.sh`. The framework starts roles on capable but not always
frontier tiers, then escalates on evidence. Details: `config/runtimes/README.md`.

**Codex:** `gpt-5.6-terra` handles cheap/standard roles; `gpt-5.6-sol` handles strong,
frontier, and escalated roles with explicit reasoning effort. Start with `--runtime openai`.

**Claude Code:** haiku, sonnet, opus, and fable-for-escalation. Haiku = Scoot (cheap
errands). Fable re-enabled Jul 2026 for the `frontier` / `escalated` tiers only (never a first-pass
default; no legacy `premium`). Challenger defaults to `strong` and escalates to opus for
final/high-risk gates; Architect/Mage default opus; utility roles default sonnet. Always pass
`model` explicitly on every spawn. Host transport and isolation:
`docs/host-runtime.md`. Cast routing: `docs/model-routing-and-cast.md`.

**Legacy Claude tiers** — `config/model-policy.json`, `config/experiments/`, and
`scripts/resolve-model-tiers.sh` remain for existing Claude Code runs during the transition.

**Usage snapshot** — Claude Code's `statusLine` (`scripts/statusline-usage.sh`) writes
`~/.novadiem/usage-snapshot.json` after each API response, so the Conductor always has
fresh quota data without running any external command. Wired via `~/.claude/settings.json`.
Docs: `scripts/README.md`, `DEPENDENCIES.md`.

## Studio-wide status (The Witness)

The **Archive** is per run (`RUN_DIR`). **The Witness** (`agents/witness.md`)
holds the cross-run view: executive briefings and log digests in `output/studio/`. Workflow:
`workflows/studio-briefing.md`. Ministry of Flow (aka Logistics) shows counts; The Witness writes the narrative.
Install list: `config/installs.json`.

## Build seams (The Coupler)

When parallel build halves must compound (Mage UI ↔ Systemsmith API), **The Coupler**
(`agents/coupler.md`) verifies **phase lock** at the junction. Wired into
`workflows/execute-plan/build-tail.md` — writes `RUN_DIR/coupling/`. Energy/spells metaphor,
not railway.

## First time setup

```bash
git clone git@github.com:rheos/bureau.git ~/Code/novadiem/bureau
# Per project: project-context.md in the project root (not inside the framework)
cp ~/Code/novadiem/bureau/templates/project-context-template.md \
   /your/project/project-context.md
```

Optional one-liner in the project's `CLAUDE.md`:

```
Bureau framework: ~/Code/novadiem/bureau/CLAUDE.md
```

### Greenfield vs existing projects

Set **Mode** in `project-context.md`. For **existing** codebases, fill in the Workspace Map
and **Git integration** (integration branch, target repo path). The Conductor scopes each agent
to the right sub-app and builds within the current stack.

## Start a run

Codex:

```
Read ~/Code/novadiem/bureau/AGENTS.md and run the Bureau as Codex.
Project context: /your/project/project-context.md
My project idea is: [PLAIN LANGUAGE]
```

Claude Code:

```
Read ~/Code/novadiem/bureau/CLAUDE.md and start the agent framework.
Project context: /your/project/project-context.md
My project idea is: [PLAIN LANGUAGE]
```

Run artifacts: `<target-repo>/.bureau/runs/<yyyymmdd>-<project>-<task>/` for targeted
runs, or `~/Code/novadiem/bureau/output/runs/<yyyymmdd>-<project>-<task>/` for the
no-target fallback.

The main session becomes The Delegate, which keeps one resumable Conductor and
gates its specialist handoffs.

## Resume an interrupted session

```
Read ~/Code/novadiem/bureau/AGENTS.md (Codex) or CLAUDE.md (Claude) and resume the agent framework.
Run dir: <absolute RUN_DIR> — read state.json and log.md.
```

## Concurrent runs (one install, many terminals)

Each run owns its own `RUN_DIR`. Execute builds also get a **git worktree** per run, so two
jobs on the same repo can run in parallel (different worktrees). Stagger test-suite steps if
two runs share a dev database. Details: `docs/git-worktree.md`, `agents/orchestrator.md`.

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

All inside the run's `RUN_DIR`:

| File | Contents |
|------|----------|
| `spec.md` | Requirements + architecture |
| `plan.md` | Phased development plan |
| `prompts.md` | Scoped agent-ready prompts — execute these |
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
- The cast and its lore (`LORE.md`) are the same in every project — one Bureau, many studios.

## Note on the subagent model

Claude spawns through its Agent tool; Codex spawns through collaboration tools with
`fork_turns: "none"`. Both are pointed at the same persona and absolute input/output
paths. They share the filesystem, not the conversation — that's the isolation the
framework depends on. See `docs/host-runtime.md` for the exact mapping and the
current Codex token-accounting gap.
