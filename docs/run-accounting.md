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
(`## [TIMESTAMP] — Spawned ...`, where `[TIMESTAMP]` is a real `date -u` UTC stamp written via
`scripts/log-append.sh`, never a typed value). Write both: the SPAWN-EVENT line is the
machine-readable record, the heading is the human one — and the heading's stamp and this line's
`"at"` field should reuse the SAME clock read (the `<TS>` `log-append.sh` echoes).

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

## B2. Bundle 11 line types

Four additional structured line types complement the SPAWN-EVENT (§ A). All four appear in `RUN_DIR/log.md`, are machine-parsed by `scripts/account-tokens.sh` and `scripts/account-run.sh`, and are backward-compatible (pre-Bundle-11 runs that contain none of these lines degrade cleanly — see EC 9 / AC 5).

### 1. SPAWN-EVENT enriched (Conductor-owned)

The seven-key base format from § A gains required timestamp fields and one optional flag on the started line. The started line gains one timestamp (`at`); the terminal line gains two (`at` and `started_at`):

```
SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"started","at":"2026-07-05T00:00:00Z"}
SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}
```

- **started line** gains `"at"` (ISO-8601 UTC, `date -u +%Y-%m-%dT%H:%M:%SZ`) and optionally `"rework": true` (omit the key when false — see `agents/orchestrator.md § Run accounting (close-out)` for the redo, not re-sequence rule).
- **terminal line** gains `"at"` and `"started_at"` (the started line's `at`, carried forward by the Conductor). The consumer derives `duration_s` from `terminal.at − started.at` using the started event's own `at` directly; the `started_at` field on the terminal line echoes that value and is informational. When either timestamp is absent, `wall_clock.active_spawn_time_s.confidence` degrades to `"partial"`. These narrative `at` values are Conductor-written (LLM), so `account-tokens.sh` runs a **timestamp-integrity guard**: it cross-checks each narrative terminal `at` against the same-`attempt_id` hook `SPAWN-TOKEN-EVENT` `at` (which the SubagentStop hook stamps with `date -u`, unfakeable). A different calendar date, a gap over 15 minutes, or every narrative spawn timestamp landing on the exact round hour marks the narrative times as fabricated and forces `active_spawn_time_s.confidence` to `"suspect"` (never `"exact"`) with a `_note` naming the tell.
- `duration_s`, `turns`, and `tokens` are NOT on the SPAWN-EVENT line — they live on the SPAWN-TOKEN-EVENT line written by the hook.

### 2. SPAWN-TOKEN-EVENT (subagent-stop.sh)

Appended by `scripts/subagent-stop.sh` (SubagentStop hook) when each specialist subagent completes. Contains the deduped token usage extracted from the subagent's isolated transcript.

```
SPAWN-TOKEN-EVENT: {"attempt_id":"architect-1","agent_id":"aae17f...","at":"2026-07-05T00:01:00Z","turns":11,"tokens":{"input":131,"cache_creation":17839,"cache_read":66779,"processed":84749,"output":699}}
```

When no `Attempt ID:` line is found in the spawn prompt (EC 7), the hook emits the fallback form — `attempt_id` is JSON `null` and a `_note` explains the gap:

```
SPAWN-TOKEN-EVENT: {"attempt_id":null,"_note":"attempt_id absent from spawn prompt — record cannot be paired to a SPAWN-EVENT","agent_id":"agent-ec7-test","at":"2026-07-05T00:01:00Z","turns":3,"tokens":{"input":50,"cache_creation":0,"cache_read":0,"processed":50,"output":3}}
```

These records are still counted into `tokens.processed_total` but cannot be paired to a SPAWN-EVENT; they appear in `tokens.unattributed_records`.

- `processed = input + cache_creation + cache_read` (by construction in `sum_transcript_usage`).
- **Dedup rule:** the consumer takes `max(processed)` per `agent_id` before summing — one subagent may produce multiple SubagentStop fires; taking max prevents inflation (EC 11 / AC 16).
- Pairing: matched to a SPAWN-EVENT pair by `attempt_id`.

### 3. CONDUCTOR-TOKEN-EVENT (conductor-stop.sh)

Appended by `scripts/conductor-stop.sh` (Stop hook) for the Conductor's own main-session token usage. Fires after every main-session response turn. There is no separate post-close-out fire — the one-shot final capture is simply the first Stop fire that finds the run closed (`state.json#accounting.status` non-pending after `account-run.sh` wrote it at close-out).

**Legacy shape** (pointer has no `baseline` key — pre-Bundle-16 run or backward-compat fallback):

```
CONDUCTOR-TOKEN-EVENT: {"session_id":"c66e96...","at":"2026-07-05T00:14:00Z","turns":42,"tokens":{"input":1234,"cache_creation":5678,"cache_read":9012,"processed":15924,"output":100},"final":false}
CONDUCTOR-TOKEN-EVENT: {"session_id":"c66e96...","at":"2026-07-05T00:15:00Z","turns":43,"tokens":{"input":1234,"cache_creation":5678,"cache_read":9012,"processed":15924,"output":102},"final":true}
```

**Non-legacy shape** (pointer has a `baseline` field — Bundle-16+ run; `tokens.*` are run-scoped deltas):

```
CONDUCTOR-TOKEN-EVENT: {"session_id":"c66e96...","at":"2026-07-06T00:14:00Z","turns":121,"tokens":{"input":10000000,"cache_creation":2000000,"cache_read":4000000,"processed":16000000,"output":100000},"final":false,"baseline":{"session_id":"c66e96...","input":20000000,"cache_creation":8000000,"cache_read":6000000,"processed":34000000,"output":300000,"turns":121}}
CONDUCTOR-TOKEN-EVENT: {"session_id":"c66e96...","at":"2026-07-06T00:15:00Z","turns":16,"tokens":{"input":10000000,"cache_creation":4000000,"cache_read":4000000,"processed":18000000,"output":100000},"final":true,"baseline":{"session_id":"c66e96...","input":20000000,"cache_creation":8000000,"cache_read":6000000,"processed":34000000,"output":300000,"turns":121}}
```

- **Delta values (Bundle-16+ runs):** when the pointer has a `baseline` field, `tokens.*` fields carry **run-scoped deltas**, not session-cumulative values. Each field is `raw_cumulative − baseline[field]`, clamped to ≥ 0. `processed` is re-derived from the clamped components (`input + cache_creation + cache_read`) — never subtracted separately — keeping `processed == input + cache_creation + cache_read` by construction.
- **`baseline` key:** non-legacy lines carry a top-level `baseline` object (the subtrahend — for audit only; `account-tokens.sh` does not consume it). An optional `_note` key is appended when any field was clamped, naming each clamped field with its raw and baseline values (e.g. `"clamped input (raw 100 < baseline 200) to 0"`).
- **`confidence:exact` meaning (Bundle-16+ runs):** `confidence:exact` now means an exact **run-scoped** share, not the full session-cumulative. Two sequential runs in the same session each produce a separate `RUN_DIR/log.md`; their per-run `processed` values sum to the session total. For legacy lines (no `baseline` key), `confidence:exact` retains its original meaning — exact session-cumulative for single-run sessions.
- **Legacy branch:** a line with **no `baseline` key** (pre-Bundle-16 pointer or backward-compat fallback) carries session-cumulative values exactly as before, in the same 6-key shape with no `baseline` or `_note` keys. Consumer semantics and `account-tokens.sh` logic are unchanged for these lines.
- `final: true` on the one-shot post-closure fire only. Confidence `"exact"` is only achievable when ≥ 1 `final: true` line is present.
- **Consumer rule:** take `max(processed)` per `session_id`, then sum across sessions (multi-leg Conductor runs produce multiple session_ids).
- A run with all SPAWN-TOKEN-EVENTs matched but no CONDUCTOR-TOKEN-EVENT has `tokens.processed_total.confidence == "partial"` with `_note: "conductor-share-pending"` — NOT `"exact"`. A build that labels this `"exact"` is broken (EC 12 / AC 4 Blocker guard).

### 4. CHECKPOINT-EVENT (Conductor-written)

Appended by the Conductor to `log.md` at each checkpoint lifecycle event. See also `agents/orchestrator.md § Checkpoint format`.

```
CHECKPOINT-EVENT: {"id":"design-review","status":"raised","at":"2026-07-05T00:05:00Z"}
CHECKPOINT-EVENT: {"id":"design-review","status":"resolved","at":"2026-07-05T00:30:00Z","decision":"proceed with mobile-first layout"}
```

- `wait_s` is consumer-derived (`resolved.at − raised.at`); it is unavailable when only a raised line is present (run still blocked).
- The consumer sums `wait_s` across all resolved pairs to produce `checkpoints.human_wait_total_s`.

### 5. BLOCKER-EVENT (Conductor-written)

Appended by the Conductor to `log.md` at two lifecycle points per Challenger blocker:
when the Conductor adjudicates a Challenger round (one `raised` line per blocker) and
when the Conductor verifies each fix (one `closed` line per blocker — same moment it
writes the `COMPLETION-CHECK:(b)` prose today). See also
`agents/orchestrator.md § Adjudicating The Challenger's findings`.

```
BLOCKER-EVENT: {"round":1,"id":"r1-b1","status":"raised","root":"architecture","gist":"cold-reviewer guard misses v2 reach-out"}
BLOCKER-EVENT: {"round":1,"id":"r1-b1","status":"closed","fix_ref":"spec.md §R2 / plan.md Phase 3","closed_at_round":1}
```

**`raised` keys:** `round` (int), `id` (string), `status` (`"raised"`), `root` (string —
the root-cause category, e.g. `"architecture"`, `"prompts"`, `"scope"`), `gist` (string —
one-line description of the blocker).

**`closed` keys:** `round` (int), `id` (string), `status` (`"closed"`), `fix_ref` (string
— artifact and section where the fix lands), `closed_at_round` (int — the round in which
the fix was verified; equals `round` for a same-round fix, higher for a cross-round fix).

**`id` format:** `"r<round>-b<n>"` — deterministic and stable across the `raised`→`closed`
pair. Mirrors the `attempt_id = "<role>-<attempt>"` convention (§ A). The stable id is what
makes the `raised`/`closed` pair grep-recoverable: `grep 'BLOCKER-EVENT:' log.md | grep
'"id":"r1-b1"'` returns exactly the raise line and the close line for that blocker.

**Append cadence:** same pattern as SPAWN-EVENT / CHECKPOINT-EVENT — the literal prefix
`BLOCKER-EVENT: ` followed by compact JSON on its own line. The consumer parses by prefix;
a malformed payload is a Conductor write error, not a format extension.

**Parsed by:** the Conductor (deriving the round-2 exclusion set before a round-2 Challenger
spawn) and `bureau-run-eval` (the `blocker-replay` no-regression check). NOT parsed by
`account-run.sh` or `account-tokens.sh` — no accounting-schema change (FR 8).

**Backward compatibility:** a `log.md` with zero `BLOCKER-EVENT` lines degrades gracefully
to today's prose-only blocker tracking (FR 9). A run that predates this line type or does
not emit it is valid; the round-2 exclusion falls back to reading the `### Blockers` /
`COMPLETION-CHECK:(b)` prose, exactly as today.

---

## B3. Pointer lifecycle (canonical — FR 6)

The pointer file `~/.novadiem/bureau-active-run` (overridable via `BUREAU_POINTER_FILE` for test isolation) tracks the active bureau run across Stop hook fires.

**Format:** one-line JSON — `{"run_dir":"<abs RUN_DIR>","nonce":"<uuidgen lowercase>","written_at":"<ISO-8601 UTC>","baseline":null}`. The `baseline` field is `null` at enrollment and is updated to a baseline object on the first Stop hook fire for the run (see state machine below).

**Baseline state machine:** `conductor-stop.sh` inspects the pointer's `baseline` field after every Stop fire to decide how to compute the run-scoped delta. `jq has("baseline")` distinguishes an absent key (pre-Bundle-16 pointer) from an explicit `null` (Bundle-16 enrolled, not yet fired). See `scripts/conductor-stop.sh § Step E.5` for the implementation.

| `pointer.baseline` | Action |
|---|---|
| key absent (`has("baseline")==false`) | Legacy — emit the old 6-key cumulative shape, no write (FR 6, FR 7). |
| `null` | First fire — record current session cumulative as the baseline object, write back via two-step guard, then use it. Write fails → baseline=0 this fire only, no retry (EC 3 residual). |
| object, `.session_id` matches current session | Same session — reuse the recorded baseline verbatim (FR 3). No write. |
| object, `.session_id` differs from current session | Resumed leg in a new session (EC 4) — re-record a fresh baseline for this session, write back, use it. Write fails → baseline=0 this fire. |

**Accounting confidence:** for Bundle-16+ runs (pointer has a `baseline` field), `CONDUCTOR-TOKEN-EVENT` lines carry run-scoped deltas, so `confidence:exact` on these lines means an exact **run-scoped** share — not the full session-cumulative. Two sequential runs in the same session each contribute their own share; the per-run shares sum to the session total (see § B2.3 for the full confidence note).

**Two-step write-back guard:** the enrollment `printf` is not atomic. A sibling run can enroll between the pre-`mv` check and the `mv` (pre-check→mv window: undetectable — the sibling's capture degrades to partial / baseline=0, EC 5). The post-`mv` re-read guards only the post-`mv` window: if a sibling writes after the `mv` but before the re-read, the writer sees the sibling's pointer, bails, and correctly degrades. No wrong values are emitted by either run. See `scripts/conductor-stop.sh § _bl_write_back` for the exact guard.

**EC 3 residual:** if the first-fire baseline write fails, the hook falls back to baseline=0 and emits a line without a `baseline` key (the old 6-key cumulative shape). A subsequent successful fire will emit a delta line. `account-tokens.sh` uses `max_by(.tokens.processed)` per `session_id` — the early raw-cumulative line (larger processed value) dominates take-max, producing over-attribution equal to today's behavior for that run. This residual is deliberate and pinned by a standing fixture (Fixture E / fixture 96).

**Step B validation:** the three-key gate (`run_dir` / `nonce` / `written_at`) does NOT include `baseline`. An absent `baseline` key is the backward-compat legacy signal, not a validation error.

**`BUREAU_ACCOUNT_RUN_SH`:** when this environment variable is set, `conductor-stop.sh` calls the named script at Step G(2) instead of `$SCRIPT_DIR/account-run.sh`. Unset behavior is identical — the default path resolves to `$SCRIPT_DIR/account-run.sh`. Primarily used for test injection (fixture-F / forced-failure shim).

**Who writes it:** The Conductor, at run start and on resume (with echo to stdout for enrolment — see `agents/orchestrator.md § Pointer lifecycle`). The Conductor does NOT remove it.

**Nonce ownership check:** `conductor-stop.sh` greps the transcript FILE CONTENT for both the nonce and `run_dir` (a path-based check would fail — the transcript path never contains these values). This closes EC 14: a session whose transcript contains `run_dir` but not the nonce exits 0.

**Why the Conductor does NOT rm at close-out:** the post-closure Stop fire must still find the pointer to write `final: true`. Removing it at close-out (a round-2 defect) would make the final capture impossible and lock `processed_total.confidence` at `"partial"` forever.

**Closure evidence:** On every Stop fire, `conductor-stop.sh` reads `RUN_DIR/state.json` to determine whether the run is closed. The run is closed when `accounting.status` is present and not `"pending"` (both `"complete"` and `"unavailable"` close it). A missing, unreadable, or unparseable `state.json` is treated as NOT closed — fail-safe direction, since a false positive would remove the pointer before the final capture can fire.

**One-shot final capture:** `conductor-stop.sh` appends a `CONDUCTOR-TOKEN-EVENT` with `final: true`, then self-refreshes (`account-run.sh "$RUN_DIR"`), then performs compare-before-rm: re-reads the pointer and removes it ONLY if its `run_dir` AND `nonce` still match this run. If a newer run has enrolled (overwritten the pointer), it is left untouched.

**Bounded capture:** once removed, later Stop fires in the same session find no pointer and exit 0. A single run produces at most one `final: true` line.

**Stale pointer (crashed run):** retired by next run's startup overwrite, or by `rm "$_pointer_file"` at archive time. It never misattributes tokens to the wrong run because the nonce is unique per run.

---

## B4. Schema version and confidence enum

**`schema_version`:** `accounting.json` carries `"schema_version": 1` when built from a pre-Bundle-11 log (old 7-key SPAWN-EVENT only, no Bundle 11 lines). It carries `"schema_version": 2` when `account-tokens.sh` returns Bundle 11 token data (the `tokens_have_data` signal — five conditions checked in `scripts/account-run.sh § 9.5`). A re-run on a log with no Bundle 11 event lines stays at schema 1; a failed `account-tokens.sh` invocation (non-zero exit or non-JSON output) also leaves the version at 1.

**Six-value confidence enum** (used in `tokens.processed_total.confidence`, `wall_clock.active_spawn_time_s.confidence`, etc.):

| Value | Meaning |
|-------|---------|
| `"exact"` | Full data available; no gaps or approximations. |
| `"estimated"` | Derived from heuristics (e.g. output-tokens estimation). |
| `"partial"` | Some data present but incomplete (e.g. SPAWN-TOKEN-EVENTs matched but no final CONDUCTOR-TOKEN-EVENT). |
| `"unavailable"` | No usable data found for this field. |
| `"inferred"` | Derived by inference from a secondary source (e.g. model-tiers.json tier name rather than an explicit model name in model-routing.json). |
| `"suspect"` | The figure is complete, but its inputs are actively distrusted — not merely incomplete. Currently emitted only by the timestamp-integrity guard on `wall_clock.active_spawn_time_s`: when the narrative `SPAWN-EVENT` times (LLM-written) disagree with the unfakeable hook `SPAWN-TOKEN-EVENT` times (shell `date -u`) by >15 min or land on a different calendar date, or when every narrative spawn timestamp lands on the exact round hour, the narrative times are treated as fabricated and the sum is downgraded from `"exact"` to `"suspect"` with a mandatory `_note` naming the tell. |

`"partial"` was added in Bundle 11 to distinguish "some tokens captured, conductor share pending" from "no tokens at all" (`"unavailable"`). `"suspect"` was added to name the distinct case where the data is *present and complete* but *fabricated at the source* — a fabricated 12h duration is not "partial data", it is an untrustworthy figure. A build that conflates `"partial"` with `"exact"` is broken (see EC 12 / AC 4 Blocker guard in § B2 above); likewise a build that lets a fabricated-timestamp run wear `"exact"` on `active_spawn_time_s` is broken. No consumer switches on this field's confidence *string* (`account-run.sh` reads only `.value` to gate `tokens_have_data`), so adding the sixth value is consumer-safe.

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

### Subagent transcript user-line schema (Bundle 11 ground truth)

- **Real schema (as confirmed in production, 2026-07-05):** `{"type":"user","message":{"role":"user","content":"<string or content-array>"}}`
  - Top-level `.role` is **absent** on user lines; the correct selector is `.type? == "user"` (not `.role? == "user"`).
  - The content is at `.message.content`, not at top-level `.content`.
  - Content shape is either a plain string or a content-array-of-blocks (`[{"type":"text","text":"..."}]`).
  - Any selector using `.role? == "user"` matches zero lines and silently no-ops — confirmed blocker in P2 review.

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
