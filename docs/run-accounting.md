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
SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"started","at":"2026-07-05T00:00:00Z"}
SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"complete","at":"2026-07-05T00:01:00Z"}
```

All **seven base keys** are required on every event — `role`, `agent`, `configured_model`,
`actual_model`, `attempt`, `attempt_id`, `status`. `scripts/emit-event.sh` also adds a
shell-computed `at` timestamp. The consumer accepts the optional started-line `rework` flag
defined in § B2.1; historical terminal `started_at` is tolerated but is not required or used.

An event **fails validation** (and the script skips-and-notes it, so it falls out of
accounting) if ANY of these hold:

- a required key is **missing**;
- a required key has the **wrong JSON type** (`role`/`agent`/`configured_model`/
  `actual_model`/`attempt_id`/`status` must be strings — `actual_model` may also be JSON
  `null`; `attempt` must be an integer ≥ 1);
- a required string key is **empty** (`role`, `agent`, `configured_model`, `attempt_id`
  must be non-empty);
- `attempt_id` does not START WITH `"<role>-"` **or with `"<persona-alias>-"`** — the
  role-prefix rule, relaxed to also accept the sibling naming scheme. The cast keys
  (`challenger`/`cleric`/`spellwright`/`systemsmith`/`mage`/`mechanic`/`counselor`) and the
  persona-file stems (`critic`/`designer`/`prompt-engineer`/`backend`/`frontend`/`sysadmin`/
  `voice`) name the same role, so an `attempt_id` prefixed by *either* is accepted for a spawn
  whose `role` field is the other (e.g. `role:"critic"` + `attempt_id:"challenger-1"`).
  `analyst`/`architect` share one name and have no alias. A genuinely mismatched prefix (e.g.
  `attempt_id:"architect-1"` on `role:"critic"`) still fails. The `attempt_id` is never
  rewritten — it stays verbatim as the specialist membership/join key across SPAWN-EVENTs
  and post-hoc transcripts;
- `status` is not one of the five legal values.

Also rejected before parsing keys: a line whose payload is not exactly one JSON value, or
is a JSON value that is not an object. Every rejection is noted in the accounting output,
never silently dropped.

These are the consumer rules enforced by `account-run.sh`. The narrower `emit-event.sh`
CLI covers the ordinary non-empty-string `actual_model` case and adds `at`, but it has no
JSON-null form and its numeric parser checks digits rather than the consumer's `attempt >= 1`
rule. Callers must still pass an attempt of at least 1; a helper-emitted attempt 0 is rejected at
close-out. Optional `rework` and historical `started_at` metadata are outside that helper's CLI.

`attempt_id` is role-prefixed — e.g. `"architect-1"`, and `"architect-2"` for a re-spawn;
any suffix after the hyphen is permitted. The prefix may be the role's cast key or its
persona alias (see the role-prefix bullet above); the stored `attempt_id` is the verbatim
specialist join key either way.

The five legal `status` values are: `started | complete | no-handoff | failed | terminated`.

The Conductor never emits a specialist SPAWN-EVENT for itself. Its post-hoc figure lives in
the top-level `conductor_tokens` block, recovered from recorded or discovered Conductor
transcripts when that identity is available; it never belongs in `specialist_spawns[]`. A
`role:conductor` SPAWN-EVENT is excluded from `specialist_spawns[]` (the script drops it with
a note).

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
machine-readable record, the heading is the human one. Both timestamps must be shell-computed.
A caller that composes the event from the `<TS>` returned by `log-append.sh` may reuse that read;
`emit-event.sh` intentionally reads its own clock, so its event may differ from the heading by a
small interval. Accounting uses the event timestamps, not the narrative heading.

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

**Run accounting LAST.** On a normal close-out, accounting is the final metric-producing
action — run it after the merge, package install, summary, and terminal `state.json`/`log.md`
updates, so `accounting.json` reflects the terminal run rather than a mid-close-out snapshot.
After it returns, only record the accounting attempt's status/path and command outcome; do not
add work that should have entered the aggregation basis. (On an abnormal exit — b, c, d — you
still attempt it; the partial state it captures is the point.)

This terminal call is authoritative. `account-run.sh` invokes the post-hoc transcript
aggregator inside the close-out command and publishes the resulting per-leg figures before it
returns. No later Stop hook completes or refreshes the accounting file.

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
run instead of losing it. Invocation still hard-fails on the public preconditions: wrong argument
count, a relative or absent `RUN_DIR`, missing `jq`, or a missing `state.json`. A present but thin or
corrupt state object follows the documented degrade-and-emit path.

---

## B2. Current post-hoc token pipeline

`SPAWN-EVENT`, `CHECKPOINT-EVENT`, `BLOCKER-EVENT`, `MODEL-OVERRIDE`, and
`REVIEWER-TOKEN-EVENT` remain run-local structured log lines. Delegate, Conductor, and
specialist token figures do **not** come from a live log-line emitter: terminal close-out
recovers them from Claude JSONL transcripts through `scripts/aggregate-transcripts.sh`.
This per-leg recovery is current for integrated Delegate-topology Claude runs. Direct-Conductor
Claude runs lack the recorded Delegate session identity used to locate the transcript tree and
therefore report the per-leg source as unavailable; non-Claude runtimes emit their named gap.

### 1. Current SPAWN-EVENT metadata (Conductor-owned)

The seven-key base format from § A carries a shell-computed `at` timestamp on both the started
and terminal lines. A started line may also carry `rework: true`:

```
SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"started","at":"2026-07-05T00:00:00Z"}
SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"complete","at":"2026-07-05T00:01:00Z"}
```

- **both lines** carry `"at"` (ISO-8601 UTC, `date -u +%Y-%m-%dT%H:%M:%SZ`).
- **started line** may carry `"rework": true` (omit the key when false — see
  `agents/orchestrator.md § Run accounting (close-out)` for the redo, not re-sequence rule).
- `account-tokens.sh` derives `duration_s` from the paired started/terminal `at` values. It
  ignores terminal `started_at`; old logs may retain that informational echo. Missing or
  malformed `at` values degrade confidence. If every narrative spawn timestamp lands exactly
  on the round hour, the active-time result is `"suspect"` with a note; there is no live-hook
  clock cross-check.
- `duration_s`, `turns`, and `tokens` are not written on the SPAWN-EVENT. Duration is
  consumer-derived; turns and tokens come from the post-hoc transcript fragment.

### 2. `aggregate-transcripts.sh` stdout contract

The close-out seam calls:

```sh
scripts/aggregate-transcripts.sh "$RUN_DIR" --until "<ISO-8601 UTC>"
```

The optional `--until` bound is half-open. When omitted, the script reads the current UTC time
once. Runtime is checked before transcript resolution: a non-Claude run emits one
`{"_runtime_gap":"..."}` object and exits 0, naming the absence of Claude JSONL instead of
guessing a figure.

A usable Claude result has this shape:

```json
{
  "delegate": {"tokens": {"input": 0, "cache_creation": 0, "cache_read": 0, "processed": 0, "output": 0}, "turns": 0, "confidence": "exact"},
  "conductor": {"tokens": {"input": 0, "cache_creation": 0, "cache_read": 0, "processed": 0, "output": 0}, "turns": 0, "legs": 1, "confidence": "exact"},
  "specialists": [
    {"attempt_id": "architect-1", "role": "architect", "agent_id": "<id>", "tokens": {"input": 0, "cache_creation": 0, "cache_read": 0, "processed": 0, "output": 0}, "turns": 0, "confidence": "exact"}
  ]
}
```

Each `tokens` object carries numeric `input`, `cache_creation`, `cache_read`, `processed`, and
`output`; `processed = input + cache_creation + cache_read`. Optional `_note` fields explain
degradation, and legacy-scoped output carries a top-level `_scope_note`.

Both accounting consumers treat this as a producer contract, not merely a JSON container. They
require exactly one top-level document; complete token/turn/leg fields; the producer's legal
per-leg confidence dispositions; a note on every non-exact leg; zero usage for `unavailable` or
`suspect`; a recorded Delegate session identity (or legacy session-id record) for `exact` or
`partial` Delegate usage; no fewer Conductor legs than are recorded in `delegate-state.json`
(with `exact` requiring a nonzero exact match); role- or persona-alias-prefixed, unique specialist
attempts; unique non-null transcript agent ids; and exact agreement between the fragment's
attributed attempts and the run's JSON or legacy key-value SPAWN-EVENT membership. An otherwise
well-shaped `_runtime_gap` object remains an explicit rejection. Any mismatch makes the fragment
unusable at both seams rather than allowing an authoritative zero, omitted leg, or duplicate sum.

#### Transcript summation and windows

- `sum_transcript_usage` reads assistant usage from `.message.usage`, groups repeated JSONL
  content-block lines by `.message.id`, and sums one usage object per message. `turns` counts
  deduped message groups containing a `tool_use` block.
- Every leg is bounded above by the same `until`. The Delegate is additionally bounded below
  by `delegate-state.json#run_started_at`, giving `[run_started_at, until)`. If that lower bound
  is unavailable, a uniquely matching single-run Delegate transcript can still be exact;
  shared-session ambiguity is partial and named.
- A structurally complete, numeric all-zero usage record is a genuine exact zero. An empty or
  incomplete all-zero usage shape is unavailable with a mandatory note, never a note-free
  exact zero.

#### Identity and role recovery

- Delegate identity comes from `delegate-state.json#delegate_session_id`; an old
  `DELEGATE-TOKEN-EVENT` may supply only a legacy session-id fallback.
- Conductor identity is the de-duplicated union of `conductor_agent_ids` and
  `conductor_agent_id`. A run-scoped transcript whose `BUREAU_ROLE: conductor` marker appears
  before any `Attempt ID:` can be discovered as an unrecorded Conductor leg; discovery makes
  the aggregate partial and is named.
- Specialists are joined to the first-seen SPAWN-EVENT membership list by `attempt_id`.
  Exactly one run-scoped transcript yields a leg; no candidate yields unavailable; multiple
  candidates for one attempt yield a zeroed `suspect` collision rather than a sum.
- A run-scoped transcript with no matching SPAWN-EVENT is emitted once as an unattributed
  record. Complete usage is `inferred`; incomplete-but-summable nonzero usage is `partial`
  with a degradation note. Sibling or foreign transcripts are excluded and only their
  volatile count is reported on stderr.

For a current run, strict specialist identity requires the transcript's first `RUN_DIR:` to
match and its `Run nonce:` to equal the write-once run-scope nonce. If the nonce cannot be
proven to predate or equal `run_started_at`, the aggregator degrades to legacy first-`RUN_DIR:`
membership and names that basis in `_scope_note`. The nonce itself never appears in stdout,
`log.md`, or `accounting.json`.

### 3. Terminal authoritative merge (`account-run.sh`)

`account-run.sh` is the only publisher. At close-out it:

1. Computes a basis from the SPAWN-EVENT count and recorded Conductor-leg count. An unchanged
   basis reuses the prior `_posthoc.run_ended_at`; a changed basis takes a fresh bound.
2. Invokes and validates the aggregator. A runtime-gated, malformed, or structurally
   incomplete fragment contract is unusable and never unlocks a legacy numeric fallback.
   This is distinct from a valid fragment containing a transcript leg whose usage fields were
   incomplete: that leg retains its numeric subtotal as noted `partial` evidence.
3. Passes the fragment to `account-tokens.sh`, which derives `processed_total`,
   `rework_ratio`, `tokens_per_loop`, and `output_total` while retaining reviewer,
   checkpoint, and wall-clock calculations.
4. Replaces top-level `conductor_tokens`, `delegate_tokens`, and every matched specialist's
   tokens/turns from the fragment, then atomically publishes `accounting.json` and records
   `_posthoc.run_ended_at` plus the basis.

`attempt_id` is the authoritative specialist join. A disagreement between a legacy recorded
agent id and the post-hoc agent id keeps the post-hoc number but marks it `suspect`; a null
post-hoc agent can still authoritatively replace a stale legacy number with unavailable.
Null-attempt transcript cost is surfaced once in `tokens.unattributed_records`.

Old `SPAWN-TOKEN-EVENT`, `CONDUCTOR-TOKEN-EVENT`, and `DELEGATE-TOKEN-EVENT` lines may remain
in historical logs. Narrow compatibility reads can recover missing work-shape, a Delegate
session id, or an agent-id comparison, but `account-tokens.sh` no longer rolls their numeric
figures up. With no usable post-hoc fragment, per-leg and fragment-derived metrics degrade;
they do not fall back to those values.

`tokens.processed_total` remains build-only: specialists plus Conductor. It is the denominator
for `rework_ratio` and `tokens_per_loop`; Delegate and reviewer gating cost is excluded.
`tokens.output_total` includes specialists, Conductor, Delegate, and reviewers.

### 3a. REVIEWER-TOKEN-EVENT (Delegate-appended, per cold-reviewer spawn)

Each checkpoint the Delegate calls `scripts/run-cold-reviewer.sh`. It returns a normalized
envelope whose `.usage` sibling is exact for either Claude or Codex. The Delegate appends one
`REVIEWER-TOKEN-EVENT` per spawn via `scripts/append-reviewer-tokens.sh`.

```
REVIEWER-TOKEN-EVENT: {"checkpoint":"05","at":"2026-07-11T00:03:00Z","turns":4,"tokens":{"input":100,"cache_creation":200,"cache_read":300,"processed":600,"output":15},"spawn_id":"05-1"}
```

- **Raw usage.** Each cold reviewer is a fresh one-shot, so the event carries the returned
  envelope usage directly and has no baseline/delta lifecycle.
- **Keyed by `checkpoint` + `spawn_id`.** A checkpoint can spawn more than one reviewer;
  each spawn gets a distinct `NN-<k>` id. The rollup takes the maximum duplicate record per
  `spawn_id`, then sums across distinct ids.
- **Fail-safe.** An envelope without usable `.usage` yields a zero-token event with a note;
  it is never silently treated as exact.

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
pair. Mirrors the `attempt_id` role-prefix convention (§ A). The stable id is what
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

### 6. MODEL-OVERRIDE: (controller- or account-run-written)

A spawning controller may write this line when it deliberately chooses an actual model that
differs from `model-routing.json`; the Delegate does so for a Conductor affordability downgrade.
Affordability supplies model choice only and never enters an accounting token field. For
specialists, `account-run.sh` also reconciles an honest divergent SPAWN-EVENT after the fact when
no matching line exists.

Format: `MODEL-OVERRIDE:` followed by compact JSON on its own line:

```
MODEL-OVERRIDE: {"role":"<role>","attempt_id":"<attempt_id>","configured":"<model-routing value>","actual":"<model used>","reason":"<free text>","at":"<iso8601>"}
```

Match key: `attempt_id` (stable per-spawn id). A `MODEL-OVERRIDE:` line whose `attempt_id`,
`configured`, and `actual` all match the divergent `SPAWN-EVENT` suppresses the divergence
note. If a specialist divergence has no matching line, `account-run.sh` appends exactly one
idempotent record with a shell-computed `at` and an `auto-reconciled from SPAWN-EVENT
actual_model` reason; the self-declared divergence is not reported as a protocol violation.
Zero `MODEL-OVERRIDE:` lines on a clean run (no divergence) is valid.

---

## B3. Run-scope nonce lifecycle (canonical — FR 6)

The per-run file is a post-hoc transcript-membership credential. It is not a token baseline,
does not trigger capture, and is never consumed by a Stop hook.

### Path and shape

Each run owns one file keyed by its munged `RUN_DIR` (every `/` and `.` becomes `-`). Path
resolution is shared by `run-start.sh`, `spawn-gate.sh`, and `aggregate-transcripts.sh`:

| Condition | File selected |
|---|---|
| non-empty `BUREAU_POINTER_FILE` | that exact file (forced single-file/test-isolation mode) |
| otherwise | `${BUREAU_POINTER_DIR:-$HOME/.novadiem/active-runs}/<munged RUN_DIR>` |

The current one-line JSON shape has exactly four fields:

```json
{"run_dir":"<absolute RUN_DIR>","nonce":"<secret>","written_at":"<ISO-8601 UTC>","project_dir":"<cwd>"}
```

There is no `baseline` field and no current `.delegate` role pointer. `run-start.sh` writes a
fresh file only when the selected file is absent, foreign, or nonce-less. If it already names
the same `RUN_DIR` and has a non-empty nonce, startup preserves the complete existing file,
including `written_at`; one run therefore has one nonce for its life.

### Enrollment and secrecy

In direct-Conductor mode, startup echoes the file so the Conductor can copy the nonce into the
`Run nonce:` line of each specialist's first message. In integrated Delegate mode,
`run-start.sh --no-pointer-echo` keeps it out of the Delegate transcript; the Conductor reads
the file privately before specialist dispatch. `spawn-gate.sh` requires the file to exist.

The nonce belongs in the run-scope file and specialist first messages. Direct-Conductor startup
also places it in that Conductor's owning transcript by echoing the file; integrated Delegate
startup suppresses that echo and the Conductor reads the file privately. Never write the nonce to
`log.md`, SPAWN-EVENT, accounting output, a handoff, or a summary. The enrollment line in `log.md`
deliberately contains no value.

### Strict and legacy aggregation

Strict specialist membership applies when `delegate-state.json#run_started_at`, the nonce,
and `written_at` are all present and `written_at <= run_started_at`. A candidate specialist
must have this run as its first `RUN_DIR:` identity and carry the exact run nonce. This excludes
sibling runs even when they reuse an `Attempt ID:`.

If those prerequisites are unavailable, or the nonce postdates run start, aggregation uses
legacy first-`RUN_DIR:` membership and emits `_scope_note` naming the weaker basis. It never
prints the nonce. This compatibility mode preserves old/rotated runs without pretending their
scope proof is current.

### Resume, close-out, and archive

On resume, validate the existing file before specialist dispatch. If it is absent, foreign, or
nonce-less, halt dispatch and recover the **original** run-scope file from trusted backup. Do
not call `run-start.sh` for an existing run to mint a replacement, and do not restore the
deleted `run-reopen.sh`; if recovery is impossible, block rather than claiming strict
attribution.

Keep the file through terminal close-out so a pre-archive re-account can still use strict
scope. Post-hoc accounting needs no pointer reset, nonce rotation, baseline recovery, or later
hook fire. If recorded activity grows after an earlier close-out, `account-run.sh` advances its
bound when the run basis changes and aggregates again.

At archive, remove only this run's keyed file. Also remove `${pointer_file}.delegate` as an
idempotent janitor for legacy Delegate pointers; no current path writes one. Do not run a broad
active-runs deletion while runs may still require strict re-accounting.

---

## B4. Schema version and confidence enum

**`schema_version`:** `account-run.sh` starts from the schema-1 work-shape and promotes the
result to schema 2 when `account-tokens.sh` returns a valid object that passes its data gate. A
usable post-hoc fragment always qualifies, including a structurally complete exact-zero run.
Reviewer/checkpoint/wall-clock data can also qualify independently. A genuine legacy run with no
qualifying data stays at schema 1. A failed or non-JSON `account-tokens.sh` invocation also stays
at schema 1 and receives `_tokens_note`; an unusable post-hoc fragment never by itself earns a
schema-2 promotion.

**Six-value confidence enum** (used in `tokens.processed_total.confidence`, `wall_clock.active_spawn_time_s.confidence`, etc.):

| Value | Meaning |
|-------|---------|
| `"exact"` | Full data available; no gaps or approximations. |
| `"estimated"` | Derived from heuristics (e.g. output-tokens estimation). |
| `"partial"` | Some usable data is present, but one or more transcript/window/leg inputs are incomplete or ambiguous. |
| `"unavailable"` | No usable data found for this field. |
| `"inferred"` | Derived from a secondary identity or membership signal, such as a run-scoped transcript with no matching SPAWN-EVENT. |
| `"suspect"` | Data is present or a candidate exists, but it must not be trusted as an exact pairing: examples are an attempt-id collision, a post-hoc/legacy agent-id disagreement, or all narrative spawn timestamps landing exactly on the round hour. A note names the cause. |

Confidence describes evidence, not magnitude. A complete numeric zero can be `"exact"`; a zero
created by a missing, malformed, ambiguous, or collided source must be non-exact and carry a note.
`"partial"` and `"suspect"` are distinct: partial names an incomplete figure, while suspect
names an actively distrusted pairing or source. Build-derived `processed_total`, `rework_ratio`,
and `tokens_per_loop` collapse any non-exact Conductor/specialist input to `"partial"`;
`output_total` is `"estimated"` whenever a usable post-hoc fragment exists. Other derived fields
apply their documented metric-specific confidence rule rather than upgrading a degraded source.

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

## F. Current Claude transcript ground truth

`aggregate-transcripts.sh` reads JSONL directly; it does not depend on a hook payload.

### Assistant usage and message dedup

- Usage-bearing assistant lines have `.type == "assistant"`, a stable `.message.id`, and a
  `.message.usage` object.
- One assistant message can appear on several JSONL lines because content blocks are split.
  Those lines repeat the same message-level usage object. `sum_transcript_usage` groups by
  `.message.id` and counts the usage once.
- A production verification sample contained 31 usage-bearing lines but only 14 unique
  message ids. Naive summation over-counted processed usage by 2.01x; message-id dedup removed
  that inflation. Exact values and private transcript paths are intentionally not operational
  documentation.
- User lines store content under `.message.content`, not top-level `.content`, and have no
  top-level `.role`. Content can be a string or an array of content blocks. Identity helpers
  therefore inspect the transcript's real nested content/raw text rather than selecting
  `.role == "user"`.

### Transcript locations

The top-session transcript is normally
`~/.claude/projects/<munged-cwd>/<session-id>.jsonl`; subagents are normally under
`<session-id>/subagents/agent-<agent-id>.jsonl`. The aggregator first tries the expected
project directory and then accepts only a unique cross-project match. A basename-derived agent
id is structural metadata, not proof of run membership; strict membership still requires the
run identity rules in § B3.

---

## G. Retired Bundle 11 hook evidence (historical only)

> **Retired:** this section records why old run logs have their shapes. Do not wire these
> hooks, implement new consumers from them, or treat their numeric values as current per-leg
> sources. `conductor-stop.sh` and `subagent-stop.sh` are permanent exit-0 stubs.

A July 2026 probe used temporary append-only `SubagentStop` and `Stop` hooks, then restored the
settings file. It confirmed these historical payload fields:

| Historical event | Confirmed fields |
|---|---|
| `SubagentStop` | `agent_transcript_path`, `agent_id`, parent `session_id`, parent `transcript_path`, `agent_type`, `stop_hook_active`, `hook_event_name`, `cwd`, `last_assistant_message` |
| `Stop` | `transcript_path`, `session_id`, `stop_hook_active` |

The former SubagentStop path used `agent-<agent_id>.jsonl`, so the basename could recover the
payload's agent id. `stop_hook_active` was present and false on normal fires. The probe also
showed that Stop ran after its response completed, SubagentStop appends could arrive before
parent control resumed, and one agent could fire more than once. Those observations justified
the old take-max/delta machinery; that machinery, its baseline fields, and its deferred final
capture all retired under FR4=A REPLACE.

Historical `SPAWN-TOKEN-EVENT`, `CONDUCTOR-TOKEN-EVENT`, and `DELEGATE-TOKEN-EVENT` records
remain valid old-log syntax. Current code reads them only through the narrow compatibility
paths named in § B2.3. They are never a numeric fallback for a current post-hoc close-out.
