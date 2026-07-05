# Run accounting — SPAWN-EVENTs, close-out, and memory

This document owns the Conductor's accounting obligations: SPAWN-EVENT emission, when to
run `scripts/account-run.sh`, how to interpret accounting outcomes, and the optional memory
key. It was extracted from `agents/orchestrator.md` so orchestrator.md can stay focused on
routing and execution. The rules here apply on every run, every workflow.

**Pointer back:** `agents/orchestrator.md § Run accounting (close-out)`

---

## Overview

A run's accounting answers a flat question: which roles ran, on which model, how many
times, and to what end. `scripts/account-run.sh <RUN_DIR>` builds `accounting.json` from
the run's artifacts. This document is the convention that makes that build correct and that
fires it on every terminal exit. It is a terminal-workflow step, not initial setup.

**Index close-out:** At terminal close-out (before archive), write the index entry with
`status: "complete"` (or `"blocked"`) — entry stays in `output/studio/runs-index/` (live
set).

**Index archive (at the same time as the run-dir `mv`):** When archiving a run (moving
`R/.bureau/runs/<slug>/` → `R/.bureau/archive/<slug>/` or `output/runs/<slug>/` →
`output/archive/<slug>/`):

1. Set `status: "archived"` and update `run_dir` to the archive path in the entry file.
2. Move the entry: `output/studio/runs-index/<slug>.json` →
   `output/studio/runs-index/archive/<slug>.json` (W5 retention — keeps the live index
   bounded by active runs; archived entries remain available under `archive/`).

These writes happen in the same step as the archive `mv` — not after. A stale `in_progress`
entry after archive is a Conductor write-discipline failure (EC 12).

---

## A. The SPAWN-EVENT obligation

Each time you spawn a specialist agent, AND again when that specialist terminates, you MUST
emit a structured **SPAWN-EVENT** record in `RUN_DIR/log.md`. The canonical form is a single
line: the literal prefix `SPAWN-EVENT: ` followed by compact JSON.

```
SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"started"}
SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"complete"}
```

All **seven** keys are required on every event — `role`, `agent`, `configured_model`,
`actual_model`, `attempt`, `attempt_id`, `status`. There are no optional keys.

An event **fails validation** (and the script skips-and-notes it, so it falls out of
accounting) if ANY of these hold:

- a required key is **missing**;
- a required key has the **wrong JSON type** (`role`/`agent`/`configured_model`/
  `actual_model`/`attempt_id`/`status` must be strings — `actual_model` may also be JSON
  `null`; `attempt` must be an integer ≥ 1);
- a required string key is **empty** (`role`, `agent`, `configured_model`, `attempt_id`
  must be non-empty);
- `attempt_id` does not equal the composite `"<role>-<attempt>"`;
- `status` is not one of the five legal values.

Also rejected before parsing keys: a line whose payload is not exactly one JSON value, or
is a JSON value that is not an object. Every rejection is noted in the accounting output,
never silently dropped.

`attempt_id` is the deterministic composite `"<role>-<attempt>"` — e.g. `"architect-1"`,
and `"architect-2"` for a re-spawn. No UUID, no external state; it is built from `role` and
`attempt` so the started/terminated pair always share the same id.

The five legal `status` values are: `started | complete | no-handoff | failed | terminated`.

The Conductor never emits a SPAWN-EVENT for itself: it runs in the main session, is never
"spawned," so a `role:conductor` event is excluded from `specialist_spawns[]` (the script
drops it with a note).

The event is emitted **twice per spawn**: `status:started` when you spawn, and one of
`complete` / `no-handoff` / `failed` / `terminated` when the specialist terminates — both
with the same `attempt_id`. `no-handoff` and `terminated` exist so a spawn that produced
no usable handoff does not vanish from accounting; those spawns still cost tokens and must
be recorded, not dropped.

If a spawn logs `status:started` but no terminal event ever follows — the run died or was
interrupted before that specialist returned — the script keeps the attempt in
`specialist_spawns[]` with `reported_status: started`. It is **not** dropped. That is
exactly how an interrupted run's work-shape is captured (it pairs with the §B "attempt
always on all terminal exits" rule below — both exist so partial runs still account for
what they spent).

This SPAWN-EVENT line is SEPARATE from and ADDITIONAL to the existing narrative log heading
(`## [TIMESTAMP] — Spawned ...`). Write both: the SPAWN-EVENT line is the machine-readable
record, the heading is the human one.

The script parses ONLY the `SPAWN-EVENT:` lines — never the narrative headings. It reads
them in a per-line guarded loop, parsing each payload with
`jq -cs 'if length == 1 then .[0] else error(...) end'` (NOT the bare `jq -c '.'`, NOT
`jq -e`), so a malformed or multi-object line is rejected rather than silently misread.
`specialist_spawns[]` in `accounting.json` is built from these lines, so emitting them
accurately is what makes role accounting correct.

---

## B. Close-out applies on ALL terminal exits

The rule is **attempt always**: you MUST attempt `scripts/account-run.sh <RUN_DIR>` on
every terminal exit of a run, not only on success. At minimum these four count as terminal
exits:

- (a) successful completion after the workflow's final Challenger pass
- (b) a run blocked at a `[CHECKPOINT]` you cannot resolve
- (c) an abandoned run
- (d) a run terminated before the final Challenger pass

**Run accounting LAST.** On a normal close-out, accounting is the *final* action — run it
after the merge, package install, summary, and the final `state.json`/`log.md` updates, so
`accounting.json` reflects the run's terminal state, not a mid-close-out snapshot, and so a
close-out step that fails *after* accounting can't leave a falsely-current file. (On an
abnormal exit — b, c, d — you still attempt it; the partial state it captures is the
point.)

On success (accounting ran and emitted `accounting.json`):
- set `state.json#accounting.status` to `"complete"`
- set `state.json#accounting.path` to `"accounting.json"`

If the script cannot run (missing `state.json`, unreadable `RUN_DIR`, non-zero exit):
- set `state.json#accounting.status` to `"unavailable"`
- set `state.json#accounting.path` to `null` — never leave it pointing at a stale
  `accounting.json` from an earlier successful run
- write a one-line reason to `RUN_DIR/log.md`

`accounting.status` is one of `pending | complete | unavailable` (matching
`templates/state.json`). `pending` is the template default, before any close-out attempt.
The value reflects **the accounting attempt's outcome, not the run's**: if `account-run.sh`
runs cleanly and emits `accounting.json`, set `.status` to `"complete"` even when the run
itself was blocked, abandoned, or terminated (exit cases b–d). The run's incompleteness is
captured *inside* `accounting.json` — via the partial `specialist_spawns[]` (e.g. an
attempt left at `reported_status: started`) and the `phases` block — not by demoting
`.status`. `"unavailable"` is reserved for the failure write above, when accounting could
not be produced at all.

Attempting accounting on partial or early exits captures the work-shape of an interrupted
run instead of losing it. Only a missing `RUN_DIR` itself is fatal.

---

## C. The optional `state.json#memory` key

Write a `"memory"` object into `state.json` during the run **if and only if** Rheo/MOT
memory was consulted. The script reads this key; the script never writes it. The six
sub-fields:

- `retrieval_count` — integer ≥ 0
- `writes_proposed` — integer ≥ 0
- `writes_accepted` — integer ≥ 0
- `conflicts_flagged` — integer ≥ 0
- `digest_freshness` — string: an ISO-8601 duration or a staleness label
- `memory_preflight_passed` — boolean

If memory was NOT used, the key MUST be absent. A block of null/unavailable values would
falsely imply memory was consulted — omit the key entirely instead.

---

## D. State-management example

The `accounting` key and the optional `memory` note are reflected in the `state.json` schema
in `docs/run-protocol.md § State management`. The `accounting` key ships in
`templates/state.json`; `memory` does not and is added only when memory was used.

---

## E. Commit-message guidance

Commit-message guidance for execute workflows lives in `workflows/execute-plan/build-tail.md`
at the close-out step (step 7). It is advisory (SHOULD), not a hard gate.

---

## Hook field names (Bundle 11 ground truth)

Probed live on 2026-07-05 (16:41–16:43 UTC) with a throwaway append-only hook registered
for both `SubagentStop` and `Stop`, fired via one trivial Task subagent and one headless
`claude -p` sub-session (4 captured fires), then removed. `~/.claude/settings.json` was
restored byte-identical to its pre-probe state. **Installed Claude Code version: 2.1.187.**

### SubagentStop payload — confirmed field names

| Design assumption | Confirmed name | Value shape |
|---|---|---|
| `agent_transcript_path` | `agent_transcript_path` — **as designed** | absolute path, e.g. `~/.claude/projects/<munged-cwd>/<parent-session-id>/subagents/agent-<agent_id>.jsonl` |
| `agent_id` | `agent_id` — **as designed** | stable per-subagent hex id, e.g. `a2782d235aa9e19ae` |

- **Transcript-basename fallback: works.** The transcript basename is exactly
  `agent-<agent_id>.jsonl`; stripping the `agent-` prefix and `.jsonl` suffix recovers
  `agent_id` (verified: basename `agent-a2782d235aa9e19ae.jsonl` ↔ `agent_id`
  `a2782d235aa9e19ae`).
- The SubagentStop payload also carries the **parent** session's `session_id` and
  `transcript_path` (the main-session JSONL, not the subagent's), plus `agent_type`,
  `stop_hook_active`, `hook_event_name`, `cwd`, `last_assistant_message`.

### Stop payload — confirmed field names

| Design assumption | Confirmed name |
|---|---|
| `transcript_path` | `transcript_path` — **as designed** |
| `session_id` | `session_id` — **as designed** |
| `stop_hook_active` | `stop_hook_active` — **as designed** |

- `stop_hook_active` is **present in every captured fire** (Stop and SubagentStop alike)
  and carries JSON `false` when the hook fires normally.

### Timing findings

- **Stop vs close-out ordering: Stop fires AFTER the turn's last action.** The captured
  Stop fire arrived after the headless session's final command had completed, and its
  payload carries the session's complete final response in `last_assistant_message` —
  the response (and every tool call inside it) is finished before the hook runs. A
  close-out `account-run.sh` call made inside the final turn therefore completes before
  the Stop hook fires, as the deferred-exact design requires.
- **SubagentStop synchronicity: the append lands BEFORE the Task tool returns control.**
  The hello-subagent's SubagentStop payload was on disk at 16:42:34Z; the parent's next
  turn (captured verbatim in the following fire's `last_assistant_message`) began at
  16:42:43Z. Prompt 2's hook can rely on its `SPAWN-TOKEN-EVENT:` line being written
  before the Conductor resumes.
- **Repeat fires per `agent_id` are real.** SubagentStop fired for the observing
  session's own `agent_id` mid-run when it ended a turn while its background children
  were still pending (`background_tasks` showed `status: "running"`). One subagent can
  produce multiple SubagentStop fires; the dedup-by-`agent_id` (take-max on `processed`)
  in the consumer is load-bearing, not defensive.

### Dedup verification on a real transcript (sum_transcript_usage)

- Transcript: `~/.claude/projects/-Users-robin-Code-novadiem-bureau/a0e10f20-33a6-42fb-854c-1d265f8d392a/subagents/agent-a51e7587527aabcae.jsonl`
  (31 assistant usage lines, 14 unique `message.id` groups)
- Naive processed sum (no dedup): **1,839,770**
- Deduped processed sum (`sum_transcript_usage`): **914,546**
- Overcount ratio on this transcript: **2.01x** (the 2.23x in the spec is the average
  across the 2026-07-04 evaluation set; per-transcript ratios vary with content-block
  fan-out)
