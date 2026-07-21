# Delegate Bridge — Integrated Topology (v2)

> On-demand module for `docs/delegate-bridge.md`. Load only for integrated-topology runs or v2 implementation work.

# Integrated topology (v2)

In v2 the Delegate is the **default top-level session** Robin talks to, and it spawns the Conductor as a
**resumable Agent-tool subagent**. At each checkpoint the Conductor *returns* a structured block to
the Delegate instead of emitting an interactive `[CHECKPOINT]`; the Delegate stages the cold
read-set and spawns a fresh **headless `claude -p` cold reviewer** for the gating verdict, then
resumes the Conductor via `SendMessage`. The file-mailbox relay (the `watcher.sh` poll loop +
`await-verdict.sh`) is not in this path. All v1 review content survives unchanged — the 6-item
critic checklist, the 9 escalation signals, the verdict schema + Artifact-hash binding, the 5-step
integration checklist, and the § 9 ledger schema — only the topology and the invocation mechanism
change.

Startup invariant: the Delegate creates the run dir first with
`scripts/run-start.sh ... --no-pointer-echo`, so the normal bare pointer exists for specialist
nonce validation but its nonce does not enter the Delegate transcript. The Delegate then enrolls
and echoes its own role:delegate pointer (`<munged-RUN_DIR>.delegate`) and only then spawns the
Conductor. The Conductor reads the bare pointer privately before its first specialist spawn; it
never returns, logs, or summarizes that nonce.

This section is the single source both personas (`agents/delegate.md`, `agents/orchestrator.md`)
and the three one-shot scripts reference. A reader can build all of them from this section alone.

## v2 §1 — Conductor return-block schemas (OQ2)

The Conductor returns its checkpoint payload as a fenced block in its final message. The Delegate
parses `return-type` FIRST, then branches. The shared header applies to both shapes; a
`routine-checkpoint` adds the integration-subtype fields, and a `genuine-fork` adds three fields.
This is the parse contract the Delegate and the prompts.md builders implement; reproduce it
verbatim:

> RECIPROCAL SYNC NOTE: `agents/orchestrator.md § A4` reproduces this CONDUCTOR-RETURN schema
> verbatim. If the schema is edited in one file it must be edited in the other, in the same
> commit. The canonical source is this section (`docs/delegate-bridge/v2-integrated.md § v2 §1`);
> the A4 copy is the Conductor's per-checkpoint reminder.

```
CONDUCTOR-RETURN
return-type:     routine-checkpoint | genuine-fork   # parse this first
checkpoint:      NN
run-dir:         <abs RUN_DIR>          # echoes the Delegate-created run dir for verdict binding
artifact:        <abs path>
artifact-hash:   <sha256>               # Delegate binds the verdict to this (FR9)
log-slice:       <abs path>             # this checkpoint's slice ONLY — never full log.md (FR5/EC8)
resume-token:    <unique opaque string> # A1 integrity marker; Conductor must echo it on resume
# NOTE: the return block carries NO revise counter (W5). The SOLE cap authority is the
# Delegate's delegate-state.json#revise_counts[NN] (W-a), mutated by revise-cap.sh (W-c);
# the Conductor never tracks or echoes it.
question:        <one line>
# routine-checkpoint adds:
checkpoint-subtype: routine | integration
worktree-path:   <abs> | (none)         # integration subtype only — feeds integration-gate.sh
base-ref:        <git-ref>              # integration subtype only
claimed-gates:   [<single-line inline JSON array>]   # integration subtype only (cross-check input)
# genuine-fork adds:
escalation-reason: <one line>
signal-fired:    <one or more of 1..9 — the escalation signals in agents/delegate.md>
pending-checkpoint: <"routine on artifact X; held until fork resolves" | none>   # EC5
```

Every field is a fact or a mechanical routing tag. `signal-fired` carries the integer id of the
matched escalation signal, so the classification is auditable, never a free-text judgment. The
Conductor writes `artifact`, `log-slice`, and `state.json` BEFORE it returns (EC1
write-before-return), so a dead-Conductor recovery finds the checkpoint-completing artifacts on
disk.

A pre-spec grill checkpoint adds no new return-block field and no `checkpoint-subtype: grill`.
If the batched items are a material Robin decision, return `genuine-fork` using the existing
escalation signal(s). If the checkpoint is only a low-stakes confirmation of recommended
defaults, return `routine-checkpoint` with `checkpoint-subtype: routine`.

## v2 §2 — Mode detection (OQ4)

Two-layer, **spawn-prompt-authoritative**:

(a) The Delegate's spawn prompt to the Conductor carries an explicit `topology: integrated`
directive: *"return to me at each checkpoint; do not write `NN-request.md`, do not call
`await-verdict.sh`, do not emit an interactive `[CHECKPOINT]`."* This is authoritative from the
first Conductor turn; `RUN_DIR` already exists because the Delegate created it before spawning.

(b) The Delegate writes `delegate-state.json#topology: "integrated"` (the Delegate-only file, W-a).
A *resumed* Conductor (or Delegate) reads it to re-derive mode; the Conductor never writes
`delegate-state.json`.

The Conductor's per-checkpoint branch evaluates, in order:

1. spawn-prompt `topology: integrated` (or, on resume, `delegate-state.json#topology: "integrated"`)
   → **v2 return-to-caller**;
2. else `RUN_DIR/delegate-session.json` present with a live watcher → **v1** write `NN-request.md` +
   `await-verdict.sh` (unchanged);
3. else → interactive `[CHECKPOINT]` (the default, unchanged).

v1 detection is unchanged precisely because FR16 forbids touching the launcher that writes
`delegate-session.json`.

## v2 §3 — Cold-reviewer spawn recipe (OQ3, SINGLE SOURCE)

This is the canonical invocation **both** the v2 Delegate and the refactored v1 watcher (Phase 4)
use. Document it verbatim:

```sh
cd "$CTX" && claude -p \
  --setting-sources "" \
  --system-prompt "You are The Delegate cold reviewer; do not act as the Conductor." \
  --model "$DELEGATE_MODEL" \
  --output-format json \
  --json-schema "$(cat "$ROOT/config/delegate-verdict.schema.json")" \
  --tools "Read" \
  --add-dir "$CTX" \
  --max-budget-usd "$B" \
  "$TASK_PROMPT" < /dev/null
```

`$CTX = RUN_DIR/checkpoints/NN-context/` (the staged read root, v2 §9). `$TASK_PROMPT` names every
staged file by its ABSOLUTE `$CTX` path (e.g. `$CTX/delegate-reviewer.md`, `$CTX/<artifact>`,
`$CTX/integration-results.json`), NOT bare relative names: the headless Read tool resolves a
relative name against the detected git/workspace root, not the spawn CWD, so a bare name is looked
up at the repo root and DENIED by `--add-dir "$CTX"` (proven in Prompt 7 Part 2). Every named path
is INSIDE `$CTX`, so AC4's "no path outside `$CTX`" still holds. Flag notes — each verified by the
Phase-0 spike or Prompt 7 Part 2 (`RUN_DIR/log.md`):

- **`--setting-sources ""` — REQUIRED for coldness.** `--add-dir` sandboxes only the **Read tool**
  (so `RUN_DIR/log.md` correctly returns READ_BLOCKED). CLAUDE.md auto-discovery is a **separate
  startup mechanism** that walks up from CWD to the repo root and loads `$ROOT/CLAUDE.md` (which
  makes the reviewer identify as "the Orchestrator") AND the global `~/.claude/CLAUDE.md`;
  `--add-dir` does NOT cover it. `--setting-sources ""` suppresses that discovery while KEEPING
  auth. Phase-0 TEST 3 proved the recipe WITHOUT this flag loaded `$ROOT/CLAUDE.md` and broke
  coldness; with it, `claude_md_loaded: false` and the identity probe returns `NONE`.
- **NO `--bare`.** `--bare` would also suppress CLAUDE.md discovery, but Phase-0 TEST 4 (R6)
  confirmed it breaks auth ("Not logged in · Please run /login") on the current claude (2.1.187),
  so coldness is bought with `--setting-sources ""`, not `--bare`. The Phase-4 `watcher.sh` refactor
  drops `--bare` for the same reason.
- **`--json-schema` takes an INLINE JSON Schema STRING, not a path.** `claude --help` shows the
  flag's argument is an inline schema (example `{"type":"object",...}`). Pass the schema file's
  CONTENTS via `--json-schema "$(cat "$ROOT/config/delegate-verdict.schema.json")"` (double-quoted
  command substitution keeps the JSON as one arg). A bare PATH aborts the spawn with
  `Error: --json-schema is not valid JSON: JSON Parse error: Unrecognized token '/'`, so no verdict
  is written. There is therefore NO absolute path argument for the schema anymore. This was never
  live-tested before Prompt 7 Part 2 — Phase-0 TEST 3 omitted `--json-schema` — which is why the
  earlier "MUST be absolute path" characterization survived; Part 2 ran the full recipe live and
  corrected it. `$ROOT` must be set in the spawn environment so the `$(cat ...)` resolves regardless
  of the `cd "$CTX"` CWD (the path inside it is absolute).
- **`$DELEGATE_MODEL`** is caller-supplied. **`$B`** is the per-spawn spend ceiling, set as
  `${DELEGATE_MAX_USD:-5.00}`: generous headroom so the cap is a runaway backstop, not a throttle
  (on a flat-rate subscription the dollars are notional; the cap only stops a stuck spawn, it must
  never throttle a real review). `< /dev/null` closes stdin; `--max-budget-usd` caps one spawn's spend.

Read-only (`--tools "Read"`) and read-scope (`--add-dir "$CTX"` + CWD=`$CTX`) are OS-enforced: the
reviewer physically cannot read `RUN_DIR/log.md` or a prior `NN-verdict.md`. The leak is PREVENTED,
not caught (AC13).

## v2 §4 — COLD-REVIEWER-MODE markers + slice recipe (W-d)

`agents/delegate.md` is a dual-mode file (manager/relay mode + cold-reviewer mode). The
cold-reviewer-mode content is wrapped in two exact marker lines, each on its own line:

```
# COLD-REVIEWER-MODE:BEGIN
…the cold-reviewer-mode section: the 6-item critic checklist, the 5-step verifying checklist,
the 9-signal backstop, the verdict semantics, the FR-44 note, and the DELEGATE FLAG guard…
# COLD-REVIEWER-MODE:END
```

Both the v2 Delegate's stager and the refactored v1 watcher extract ONLY that section with the same
`awk` slice:

```sh
awk '/^# COLD-REVIEWER-MODE:BEGIN/,/^# COLD-REVIEWER-MODE:END/' \
  "$ROOT/agents/delegate.md" > "$CTX/delegate-reviewer.md"
```

The output file is **`delegate-reviewer.md`** — this is what gets staged into `$CTX`. The full
dual-mode `agents/delegate.md` is NEVER staged: it grants manager-mode Bash/Write/spawn
capabilities a read-only reviewer must not read as its own (W7 capability-contamination guard).

## v2 §5 — Gate-execution ownership (OQ1)

`scripts/integration-gate.sh` is the **single shared executor** for integration checkpoints:

- The **v2 Delegate** (manager mode) invokes it before spawning the cold reviewer at an integration
  checkpoint.
- The **refactored v1 watcher** calls it in place of its inline executor (Phase 4 / Prompt 4) — one
  copy, two callers, no duplicate to drift.
- **Inputs (CLI flags):** `--checkpoint-type`, `--worktree-path`, `--base-ref`, `--claimed-gates`,
  `--known-flaky-gates` (optional), `--state-json`, `--out <dir>`.
- **Output:** writes `integration-results.json` to the `--out` dir.
- **Deps:** POSIX `sh` + `python3` + `git` — exactly what `watcher.sh` already required, so a
  pure-v1 host gains no new dependency.

"The build cannot grade its own homework" (FR14): the Delegate runs the gates; the Conductor/build
never runs them, and the cold reviewer never runs them (it stays read-only). The canonical gate set
is resolved from the project's own runners/manifest, never from `claimed-gates` — the verified party
does not define what gets executed.

## v2 §6 — Ledger ownership (OQ5 / W6)

The **Delegate** (top-level session, manager mode) appends each verdict via the **unchanged
`scripts/ledger-append.sh`** — one call per cold-reviewer verdict = one appended record (the
per-verdict / single-writer / append-only invariants of FR10, § 9 schema).

`Robin's call:` on an escalation-resolution entry is filled by the deterministic one-shot
**`scripts/ledger-set-robins-call.sh`**, NOT by a model hand-edit:

```
ledger-set-robins-call.sh <NN> "<literal value>"
```

It locates the blank `Robin's call:` line for record `NN` and fills only that field, touching
nothing else. The model never writes to `delegate-decisions.md` directly, so the append-only
invariant stays a SCRIPT guarantee (it would degrade to instruction-enforced if the warm Delegate
free-hand-edited the file).

## v2 §7 — Deterministic revision cap (W-c / FR11)

On a `revise` verdict, the Delegate calls **`scripts/revise-cap.sh`**:

```
revise-cap.sh <delegate-state.json-path> <NN> <cap>
```

It atomically increments `revise_counts[NN]` in `delegate-state.json` and emits to stdout:

- `escalate` — if the new count reaches `cap`;
- `revise` — otherwise.

The Delegate acts on this stdout, never on its own cap inference. **Default cap: 2.** The cap is a
SCRIPT guarantee, not a model instruction — this restores v1 `verdict-write.sh`'s hard cap ("rewrite
to escalate at cap regardless of what the Delegate emitted", AC15). The return block carries no
counter (W5), so the cap can neither fire early nor never.

## v2 §8 — `delegate-state.json` spec (W-a / Data Models)

New file, per-run, at `RUN_DIR/delegate-state.json`. **Delegate-only writes.** Schema:

```json
{
  "topology": "integrated",
  "conductor_agent_id": "<id>",
  "active_checkpoint": "NN",
  "revise_counts": { "NN": 0 },
  "revision_cap": 2
}
```

Field notes: `topology` is the OQ4 resume echo (read by a resumed Conductor; `"watcher"`/absent ⇒
not v2). `conductor_agent_id` is the EC2/EC6 reconnect handle, rewritten at each checkpoint boundary.
`active_checkpoint` is the EC2 resume marker. `revise_counts` is the EC7 cap counter, mutated by
`revise-cap.sh` (v2 §7), never the model. `revision_cap` is an optional override (default 2).

`state.json` is unchanged and **Conductor-only** (it still carries `#scope`, `#git`, etc. that
`integration-gate.sh` reads). `delegate-state.json` is additive: no v1 script reads it (it did not
exist in v1), and `delegate-session.json` (the v1 launcher's PID file) is a different file,
untouched.

**Single-writer-per-file invariant (extended).** The bridge keeps exactly one writer per file:
`state.json` → **Conductor** only; `delegate-state.json` → **Delegate** only. A Conductor
read-modify-write of `state.json` can never clobber the Delegate's runtime block, because the two
blocks live in two files (this is why W-a chose a separate file over "Conductor re-reads before
every write", AC16).

## v2 §9 — Staged manifest (per-checkpoint)

For each reviewer spawn the Delegate stages `$CTX = RUN_DIR/checkpoints/NN-context/` with exactly:

- **the artifact under review** (copied by name);
- **`log-slice.md`** — this checkpoint's log slice only;
- **`state.json`** — the scope projection (the Conductor writes this before returning);
- **`conventions.md`** — router from `$ROOT/docs/`;
- **`conventions/`** — convention modules from `$ROOT/docs/conventions/`, loaded on demand;
- **`delegate-reviewer.md`** — the cold-reviewer-mode SECTION of `agents/delegate.md`, via the W-d
  slice (v2 §4);
- **`integration-results.json`** — integration checkpoints only, written by `integration-gate.sh`
  into `$CTX`.

**NEVER staged:** the full `log.md`, the full dual-mode `agents/delegate.md`, any prior
`NN-verdict.md`. `$CTX` is the cold reviewer's only read root (v2 §3), so the manifest IS its world;
the full `log.md` being absent is what makes the verdict cold (FR5/EC8).

## v2 §10 — Cold-reviewer signal backstop + named gap (FR8 / AC3)

For every routine checkpoint the cold reviewer **independently re-applies all 9 escalation signals**
(`agents/delegate.md`) against the staged manifest, as a backstop to the Conductor's classification:
a genuine fork the Conductor under-classified as routine is caught when the cold reviewer returns
`escalate` (which the Delegate then surfaces to Robin). Detectability from the staged artifact +
context alone:

| # | Signal (abbrev) | Cold-detectable? | Why |
|---|---|---|---|
| 1 | Challenger BLOCKER fix wrong/thin | Yes | Adjudication review (checklist item 1) reads the BLOCKER + fix in the artifact + log-slice. |
| 2 | Scope decision materially changes cost/timeline | Partial | Detectable if the scope/cost is written into the artifact; a conversation-only cost claim is invisible. |
| 3 | Two equally valid approaches, tradeoff is Robin's | Partial | Detectable if both approaches are in the artifact; an alternative discussed only in conversation is not. |
| 4 | Touches a Robin-marked sensitive system (prod DB, billing, auth) | Yes | Enumerated-keyword/name match on the artifact (same posture as verifying mode). |
| 5 | Production/release deploy, public shipping | Yes | The artifact/plan names the action. |
| 6 | Destructive/irreversible, secrets/access, security/privacy | Yes | Artifact/diff inspection + keyword. |
| 7 | Unresolved BLOCKER · exhausted revision cap · specialist conflict | Partial | BLOCKER + conflict are in the artifact/log-slice; **cap-exhaustion is NOT cold-detectable** — it is a cross-checkpoint counter the warm manager owns (`revise_counts`, EC7). |
| 8 | Unexpected scope expansion · overlaps Robin's unrelated work | Partial | Scope-expansion vs spec § Requirements is detectable; **"overlaps unrelated work" is NOT** — it needs live external context. |
| 9 | Spec-compliant but doctrine-violating (over-engineering) | Yes | The reviewer has the staged conventions router/modules + the artifact. |

**The named residual under-escalation gap:** cap-exhaustion (7), unrelated-work overlap (8), and
conversation-only tradeoffs (2/3). The cold reviewer cannot independently catch these. For (7) the
warm Delegate manager enforces the cap before spawning a reviewer (EC7, via `revise-cap.sh`). For (8)
and the conversation-only parts of (2/3), the **Conductor's classification remains primary** — it is
the only actor that sees the conversation. The backstop catches the artifact-detectable majority (1,
4, 5, 6, 9 fully; 2, 3, 7-BLOCKER/conflict, 8-scope-expansion to the extent written); the gap is
stated, not hidden (FR8, AC3 — the Challenger checks both).

---
