# Run protocol — directory, state, log, and index

This document owns the Conductor's obligations around `RUN_DIR` lifecycle, `state.json`
management, `log.md` format, and the runs-index. It was extracted from
`agents/orchestrator.md` so orchestrator.md can stay focused on routing, adjudication, and
workflow execution. The rules here apply on every run, every workflow.

**Pointer back:** `agents/orchestrator.md § Run directory, state management, and log format`

---

## Run directory (`RUN_DIR`) — one per task, concurrency-safe

The canonical `RUN_DIR` is `<target-repo>/.bureau/runs/<yyyymmdd>-<task-slug>/` when
`target_repo` is a real path (including self-run where the install IS the target repo).
The fallback is `<install>/output/runs/<slug>/` when `target_repo` is `"(no-target)"`.

**Creation order (required — AC 5, AC 17):**

- **(0) Resume gate** — if an existing run dir was named or found (via the resume snippet's
  `Run dir:` line, or a slug already present at `output/runs/<slug>/`), use it **verbatim**
  — whether it lives at `output/runs/` or `.bureau/runs/`. Skip steps (1)–(3). An existing
  run dir is sticky and is never relocated or migrated.
- **(1) NEW run: resolve `target_repo`** — walk the target-resolution precedence (see
  `CLAUDE.md` "On start"), write the resolved value to `state.json#target_repo`.
- **(2) Create RUN_DIR from the resolved target** — `mkdir -p R/.bureau/runs/<slug>/` for a
  real `R`, or `output/runs/<slug>/` for `"(no-target)"`.
- **(3) Copy `templates/state.json` + init `log.md`.** Pass the resolved absolute path as
  **`RUN_DIR`** in every spawn prompt.

Two runs on repo `R` use distinct slugs — `R/.bureau/runs/<slug-A>/` vs
`R/.bureau/runs/<slug-B>/` — so they never collide (FR 13, AC 12).

`state.json`, `log.md`, `spec.md`, `plan.md`, `prompts.md`, and `design/` all live under
`RUN_DIR`. Persona files name artifacts relative to `RUN_DIR` — pass their **absolute**
paths in every spawn prompt.

This is what makes concurrent runs safe on ONE global install: two sessions each own their
`RUN_DIR` and never write each other's artifacts. The `agents/` and `workflows/` files are
read-only at runtime and shared freely.

**Git worktrees** (execute build stage) isolate code per run — see `docs/git-worktree.md`.
Create with `scripts/run-worktree.sh create` before step 6; merge/remove at close-out or per
policy. Build-party spawns get `WORKTREE:`; all commits land in the worktree branch, not
`devel` directly.

**Concurrency rules:**

- One Conductor per run; never write outside your `RUN_DIR` + your run's worktree (if any).
- Two runs on the **same repo** are OK when each has its own worktree + `RUN_DIR`. Do not
  share one worktree or edit the integration branch directly during an open run.
- Shared infrastructure (a dev DB, docker test containers) can still contend across runs —
  if both tasks run the same test database, stagger the test-running steps.
- Legacy: an old install may still have a top-level `output/state.json` from before run
  dirs, or runs from before this change that live at `output/runs/<slug>/`. Finish those
  runs in place; don't migrate them mid-run. New runs always get a `RUN_DIR`. See
  `output/README.md`.

---

## State management

After each phase, update the run dir's `state.json`:

```json
{
  "project": "Project name",
  "target_repo": "/path/to/target/repo",
  "phase": "current phase name — a SHORT label, not a paragraph",
  "phase_status": "complete | in_progress | blocked",
  "phases_complete": ["analyst", "architect"],
  "critic_loops": { "analyst": 0, "architect": 1, "prompts": 0 },
  "design": { "needed": null, "status": "pending | awaiting_design | ingested | not_needed" },
  "open_questions": [],
  "carried_items": ["things to confirm before executing prompts — OQs, caveats, known nits"],
  "checkpoints": [],
  "decisions": {},
  "accounting": { "status": "pending", "path": null },
  "git": {
    "enabled": true,
    "repo": "/path/to/target/repo",
    "base_branch": "devel",
    "branch": "bureau/20260612-task-slug",
    "worktree_path": "/Users/robin/.bureau/worktrees/target-repo/20260612-task-slug",
    "merge_policy": "end_of_job",
    "status": "active",
    "prompts_merged": []
  },
  "last_updated": "ISO timestamp"
}
```

`target_repo`: set by the Conductor at run start (before RUN_DIR creation) from the
target-repo resolution step; an absolute path or the literal `"(no-target)"` sentinel.
Independent of the execute-only `git` block (which stays `enabled: false` on planning runs).

`git` block: set by `scripts/run-worktree.sh create`; omit or `enabled: false` for
planning-only runs. Full schema: `templates/state.json`, `docs/git-worktree.md`.

`accounting` block: part of `templates/state.json`; the close-out step sets its `status`
and `path` (see `docs/run-accounting.md`). `memory` is an optional Conductor-written key,
added to `state.json` only if Rheo/MOT memory was consulted this run — it is NOT part of
`templates/state.json` and is NOT written by `scripts/account-run.sh`. See
`docs/run-accounting.md § C` for its sub-fields and the absent-when-unused rule.

### State discipline

All three of these have bitten real runs:

- **`state.json` is state, not prose.** Values are short labels, lists, and decisions.
  Anything that needs a paragraph (a migration pattern, a design rationale, a build
  narrative) goes in `log.md`; `state.json` may hold a one-line pointer to it.
- **Carried items get their own key.** Open questions, caveats, and confirm-before-build
  notes go in `carried_items` — never appended to the `phase` string. `carried_items` is
  populated 1:1 from each agent's `Passing forward` footer bullets — copy them, don't
  author a parallel list (`docs/conventions.md`).
- **Validate after every write.** Duplicate keys silently shadow each other and stale
  values survive. After each update run:
  `python3 -c "import json,sys; json.load(open('<RUN_DIR>/state.json'))" && echo OK`
  If you re-set a key, find and remove the old occurrence — never append a second copy.

### Index write (same cadence as `state.json`)

After every `state.json` write and its validation, project the run's current state into
`output/studio/runs-index/<slug>.json`:

```json
{
  "slug": "<slug>",
  "repo": "<state.json#target_repo>",
  "run_dir": "<absolute RUN_DIR>",
  "status": "<derived — see run-level status derivation below>",
  "phase": "<state.json#phase>",
  "last_updated": "<state.json#last_updated>",
  "workflow": "<state.json#workflow>"
}
```

Six fields copied verbatim from `state.json` (using `target_repo` for `repo` — NOT
`git.repo`, which is `null` on planning runs); one field derived (`status`, per the
derivation table below). Before the first index write in a session, run
`mkdir -p output/studio/runs-index/ && mkdir -p output/studio/runs-index/archive/`
— the directory is not created by any prior framework step and does not exist in a fresh
install. Write atomically: temp `.<slug>.json.tmp` then `mv`. Validate the entry file the
same way as `state.json`. Per-run files are the concurrency mechanism — no lock needed
(EC 13).

> **Not committed.** `output/studio/runs-index/` and the derived
> `output/studio/runs-snapshot.json` are **gitignored** local runtime cache — per-run
> pointers carrying machine-local absolute `run_dir` paths, rewritten every phase and
> regenerable by `scripts/build-runs-snapshot.sh`. They are NOT part of the committed
> Studio Record (`briefing.md`, `lessons.md`); do not track them. Each install builds its
> own index from its own runs.

### Run-level `status` derivation

The index `status` is NOT `phase_status` verbatim:

| Run condition | index `status` |
|---|---|
| Template default (`phase_status: "pending"`, `phases_complete: []`) | `"not_started"` |
| `phase_status == "blocked"` | `"blocked"` |
| Phase `in_progress`, OR phase `complete` but more phases remain (not terminal close-out) | `"in_progress"` |
| Terminal close-out (not yet archived) | `"complete"` |
| Post-archive | `"archived"` |

---

## Log format

Append to `RUN_DIR/log.md` after every spawn and every decision:

```markdown
## [TIMESTAMP] — Spawned Analyst → complete
Handoff: <paste the agent's returned block>

## [TIMESTAMP] — The Challenger round 1 → 2 blockers, 1 warning
The Conductor's call: blocker 1 (architecture) → fix; blocker 2 → fix; warning → noted, proceed.
Re-spawning The Architect (loop 1/2) with the two blockers.
```

Machine-readable `SPAWN-EVENT:` lines are separate from these narrative headings — see
`docs/run-accounting.md § A`.
