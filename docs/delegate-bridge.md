# Delegate Bridge — Escalation Contract and File-Mailbox Protocol

This is the neutral authority document for the bridge between the Conductor and the Delegate.
It is owned by neither persona: `agents/delegate.md` owns the Delegate's role, the critic
checklist, and the verdict fields; `agents/orchestrator.md` owns the Conductor's internals
and the per-checkpoint reminder; this doc owns the shared protocol — the file conventions,
the spawn invocation, staging, the cap rule, and the failure modes. Cross-reference those
files; do not restate their content here.

The protocol now spans two topologies. The **integrated topology (v2)** is the primary path and
is specified first: the Delegate is the top-level session and spawns the Conductor as a resumable
Agent-tool subagent. The **v1 / watcher-attended fallback** is retained below for hosts without
nested spawning (FR16): the Conductor spawns the Delegate per checkpoint through `watcher.sh`'s
file-mailbox. On a nested-spawn host v2 is canonical; v1 is the documented fallback and the A1
escape hatch.

---

# Integrated topology (v2)

In v2 the Delegate is the **top-level session** Robin talks to, and it spawns the Conductor as a
**resumable Agent-tool subagent**. At each checkpoint the Conductor *returns* a structured block to
the Delegate instead of emitting an interactive `[CHECKPOINT]`; the Delegate stages the cold
read-set and spawns a fresh **headless `claude -p` cold reviewer** for the gating verdict, then
resumes the Conductor via `SendMessage`. The file-mailbox relay (the `watcher.sh` poll loop +
`await-verdict.sh`) is not in this path. All v1 review content survives unchanged — the 6-item
critic checklist, the 9 escalation signals, the verdict schema + Artifact-hash binding, the 5-step
integration checklist, and the § 9 ledger schema — only the topology and the invocation mechanism
change.

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
> commit. The canonical source is this section (`docs/delegate-bridge.md § v2 §1`); the A4 copy
> is the Conductor's per-checkpoint reminder.

```
CONDUCTOR-RETURN
return-type:     routine-checkpoint | genuine-fork   # parse this first
checkpoint:      NN
run-dir:         <abs RUN_DIR>          # Delegate learned RUN_DIR here (it spawned before RUN_DIR existed)
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

## v2 §2 — Mode detection (OQ4)

Two-layer, **spawn-prompt-authoritative**:

(a) The Delegate's spawn prompt to the Conductor carries an explicit `topology: integrated`
directive: *"return to me at each checkpoint; do not write `NN-request.md`, do not call
`await-verdict.sh`, do not emit an interactive `[CHECKPOINT]`."* This is authoritative and resolves
the chicken-and-egg: it is set BEFORE RUN_DIR exists.

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

# v1 / watcher-attended fallback

These sections specify the **v1 file-mailbox protocol**, retained as the fallback for hosts where the
Agent tool's nested spawn is unavailable (FR16/EC8). Their content is unchanged from v1 except where
a line is explicitly extended for v2 (the single-writer-per-file invariant in Section 2). When a
nested-spawn host is available, the integrated topology (v2) above is canonical.

## Section 1: Objective

This document specifies the file-mailbox protocol through which the Conductor and the
Delegate coordinate at each checkpoint, without meeting in the same context.

## Section 2: Checkpoint file convention (AC 6)

**Naming:** `RUN_DIR/checkpoints/NN-request.md`, `RUN_DIR/checkpoints/NN-verdict.md`,
`RUN_DIR/checkpoints/NN-robin.md` (escalation response). NN is a zero-padded ordinal.

### Checkpoint type classification

Before writing `NN-request.md`, determine `checkpoint-type` from the checkpoint's declared
action in `state.json` or the workflow's phase definition — never inferred from artifact
content.

- `integration` iff the checkpoint is a merge to a persistent branch (`main`, `release`, or a
  long-lived feature branch that is itself the integration target). v1 implements this criterion
  only. Deploy-to-non-ephemeral-env and canon/fixture-promotion are deferred extensions.
- `routine` for all other checkpoints: design review, spec review, plan review, phase-boundary
  handoff, and per-prompt build/accept checkpoints.
- Default for any unmapped phase: `routine`. A phase is integration only by explicit
  declaration, not by Delegate inference.

Phase mapping for v1:

- `execute-plan` close-out merge (worktree to integration branch) → `integration`
- `bug-fix` merge to main / integration branch → `integration`
- `feature` runs (plan-type, no build/merge phase) → no integration checkpoints
- deploy/promote phases → deferred; set as `routine` for now

For `integration`, the request must also carry `worktree-path`, `base-ref`, and
`claimed-gates`; `scope` is read from `state.json#scope` when present. The Conductor writes
`state.json#scope` at the design-model checkpoint where scope is agreed
(`declared_at`, `declared_by: "conductor"`) and thereafter reads it verbatim.

**Request file schema** (written by the Conductor):

```
checkpoint:    NN
attempt:       A       # 1-based; incremented on EVERY re-issue (revise OR hash-rebind)
revise-count:  R       # 0-based; incremented ONLY on a real `revise` verdict (the cap basis)
run-dir:       <abs RUN_DIR>
artifact:      <path>
artifact-hash: <sha256>
log-slice:     <path>  # path to THIS checkpoint's log.md slice only
question:      <one line>
checkpoint-type:  integration | routine
                  # Required for all new requests. Legacy / absent ⇒ treat as `routine`.
worktree-path:    <abs-path> | (none)
                  # Required when checkpoint-type: integration.
                  # Single flat line. Source: state.json#git.worktree_path.
base-ref:         <git-ref>
                  # Required when checkpoint-type: integration.
                  # Single flat line. Source: state.json#git.base_branch
                  # (template default: "devel" — NOT the literal string "main").
claimed-gates:    [{"name":"<n>","command":"<cmd>","result":"green|red","pre-existing":true|false|null}, …]
                  # Required when checkpoint-type: integration.
                  # SINGLE LINE carrying an inline JSON array. The bridge's req_field
                  # parser (watcher.sh:92-98) does head -n 1, so this MUST be one line.
                  # The executor parses it with python3 json.loads().
                  # Cross-check input ONLY — NOT the gate set the watcher executes.
known-flaky-gates: [{"name":"<n>"}]
                  # Optional. Single-line inline JSON array.
                  # If present, the watcher demotes a re-run fail on a named gate to
                  # Uncertainties rather than a blocking revise. Absent ⇒ every re-run
                  # red blocks (the conservative default).
```

**Integration request fields — notes:**

1. `claimed-gates` is a cross-check input only. The canonical gate set (standing regression
   runner + project manifest gates, resolved fresh in the worktree at checkpoint time) governs
   what the watcher executes — the build's claims do NOT select or modify that set
   (FR-B14-3, FR-B14-14).

2. A routine request that happens to carry these fields is still treated as routine
   (FR-B14-10). The watcher reads `checkpoint-type` and falls through to the existing path
   when the value is `routine` or absent.

3. `worktree-path` is sourced verbatim from state.json#git.worktree_path (the field already
   exists in templates/state.json at line 20 as `"worktree_path": null`).

4. `base-ref` is sourced from state.json#git.base_branch (template default "devel", line 18).
   Never assume "main". The configured base, not a hard-coded ref.

**`state.json#scope` block — field rules** (JSON carries no comments, so the rules live here):

- `allowed_paths`: glob list of files in scope. The Delegate flags any file in
  `git diff base-ref...HEAD --name-only` that matches NO glob as out-of-scope.
- `cut_symbols`: exact symbol strings explicitly cut at a design checkpoint.
  The Delegate greps the committed diff for each; a hit is a scope violation.
- `declared_at`/`declared_by`: provenance — which planning checkpoint set the boundary
  and who authored it (always "conductor"). Written once at the design-model checkpoint;
  treated as frozen and immutable to the build thereafter.
- Absent/null `scope` ⇒ uncertainty, not blocking violation (EC-B14-6).
- Immutability is structural: state.json lives in RUN_DIR (Conductor-only writes);
  the build works in a separate git worktree. No runtime tamper-guard is added or needed
  (see spec Architecture Data Models §2, A6 ruling). **Single-writer-per-file (v2 extension):**
  the integrated topology keeps exactly one writer per file — `state.json` → Conductor,
  `delegate-state.json` → Delegate (the Delegate's runtime block lives in its own file so a
  Conductor write of `state.json` can never clobber it). See § Integrated topology (v2) §8 (AC16).

**`attempt` vs. `revise-count` — why both exist:**

- `attempt` increments on EVERY re-issue, including a hash-rebind (artifact edited
  mid-checkpoint, Delegate not yet spawned — the prior verdict is invalidated and
  the request is re-issued for the new artifact). A hash-rebind is NOT a revise cycle.
- `revise-count` increments ONLY when the Conductor re-issues in direct response to a
  `revise` verdict. The cap (default 2) is counted against `revise-count`, never `attempt`.
- The Conductor sets both fields. On a `revise` re-issue: carry `revise-count + 1`.
  On a hash-rebind: carry the same `revise-count`, increment only `attempt`.
- `verdict-write.sh` enforces the cap against `revise-count`. Two hash-rebinds at the cap
  value still produce a non-escalate verdict; a `revise-count` at the cap escalates (EC7).

**Verdict file schema** (written by the bridge, atomically — tmp→rename):

```
checkpoint:       NN
attempt:          A
artifact-hash:    <sha256>   # must equal the request's hash or the verdict is discarded
decision:         proceed | revise | escalate
uncertainties:    <text>
rationale:        <1–2 sentences>
required-changes: <tagged by root: requirements | architecture | prompts | none>
escalation:       <one-line reason | none>
ledger:           <pointer to the delegate-decisions.md entry>
```

**Binding rule:** A verdict is bound to the triple `{checkpoint, attempt, artifact-hash}`.
A verdict whose `artifact-hash` does not match the request's `artifact-hash` is discarded by
`verdict-write.sh`; the Conductor re-issues the request with the new hash and increments
`attempt`.

## Section 3: The load-bearing spawn invocation (identity isolation — EC1/EC8)

The spawn invocation that the watcher uses is exactly (Phase 4 / Prompt 4 refactor —
`--bare` dropped, CWD pinned to `$CTX`; it shares the same COLDNESS MECHANISM as the v2 §3
single-source recipe — no `--bare`, `--setting-sources ""` for CLAUDE.md suppression, and
CWD=$CTX — but is not byte-identical to it: this v1 watcher invocation additionally carries
`--no-session-persistence` and the other watcher-loop flags, where v2 §3 closes stdin with
`< /dev/null` and orders its flags differently):

```sh
cd "$CTX" && claude -p \
  --system-prompt "$DELEGATE_SYSTEM_PROMPT" \
  --model "$DELEGATE_MODEL" \
  --output-format json \
  --json-schema "$(cat "$ROOT/config/delegate-verdict.schema.json")" \
  --tools "Read" \
  --add-dir "$CTX" \
  --setting-sources "" \
  --no-session-persistence \
  --max-budget-usd "$DELEGATE_MAX_USD" \
  "$DELEGATE_TASK_PROMPT"
```

`--json-schema` takes an INLINE JSON Schema string, not a path, so the watcher inlines the schema
file's CONTENTS via `$(cat ...)` (same fix as v2 §3 — a bare path aborts the spawn on claude
2.1.187). `$DELEGATE_TASK_PROMPT` names the staged files by their ABSOLUTE `$CTX` paths (Section 4),
because the headless Read tool resolves a bare relative name against the git/workspace root, not
the CWD.

Where `$CTX` = `RUN_DIR/checkpoints/NN-context/` (the staged per-checkpoint read scope). The
watcher runs `cd "$CTX" && claude -p …` inside a scoped subshell and keeps the
`> "$out_json" 2> "$err_log"` redirects OUTSIDE it, so the CWD change touches neither the
watcher's own working directory nor where the output files land.

Each flag's load-bearing job:

- `--system-prompt "$DELEGATE_SYSTEM_PROMPT"`: sets the full system prompt to:
  "You are The Delegate. Do not load CLAUDE.md. Do not act as the Conductor."
  This names the Delegate identity explicitly (FR 33). It is one half of the identity guard;
  `--setting-sources ""` (below) is the other half.
- `--tools "Read"`: the Delegate has no write access to the repo. Every write is owned by
  the bridge scripts. This is a hard constraint, not a convention.
- `--add-dir "$CTX"` + CWD = `$CTX`: the ONLY read root is the staged context dir. The
  Delegate cannot read `$RUN_DIR`, `log.md`, the rest of the repo, or any other run. EC8 is a
  filesystem-level exclusion, not a prompt instruction. NOTE `--add-dir` sandboxes the Read
  TOOL only — see the next bullet for why that alone does not buy identity coldness.
- `--setting-sources ""`: REQUIRED for identity coldness, and it ALONE buys it (no `--bare`).
  CLAUDE.md auto-discovery is a SEPARATE startup mechanism that walks up from CWD to the repo
  root and loads `$ROOT/CLAUDE.md` (which makes the reviewer identify as "the Orchestrator")
  AND the global `~/.claude/CLAUDE.md`; `--add-dir` does NOT cover it. `--setting-sources ""`
  suppresses that discovery (project + global) AND user/project/local `settings.json`, while
  KEEPING auth. Phase-0 TEST 3 proved the recipe WITHOUT this flag loaded `$ROOT/CLAUDE.md`
  and broke coldness; with it, `claude_md_loaded: false` and the identity probe returns
  `NONE`. (Same finding as the v2 §3 single source.)
- `--no-session-persistence`: no session to resume; each checkpoint is transcript-free.
- `--max-budget-usd "$DELEGATE_MAX_USD"`: per-checkpoint spend ceiling (default 5.00; headroom, a runaway backstop not a throttle).

`--bare` was DROPPED. It would also suppress CLAUDE.md auto-discovery, but Phase-0 TEST 4 (R6)
confirmed it breaks auth ("Not logged in · Please run /login") on the current claude (2.1.187).
The load-bearing identity guard is therefore `--system-prompt` + `--setting-sources ""` +
CWD = `$CTX`: `--setting-sources ""` removes the CLAUDE.md path (and settings re-injection),
`--system-prompt` installs the Delegate identity in its place, and the CWD pin keeps the read
root confined. If any of the three changes, the others must still be present — document any
change to this set here.

## Section 4: Staging (the per-checkpoint read-scope assembly — EC8 fix)

Before the Delegate spawn, `watcher.sh` stages the read set into a scratch dir:

```sh
CTX="$RUN_DIR/checkpoints/$CP-context"
mkdir -p "$CTX"
cp "$ARTIFACT"                    "$CTX/"
cp "$LOG_SLICE"                   "$CTX/log-slice.md"
cp "$RUN_DIR/state.json"          "$CTX/"
cp "$ROOT/docs/conventions.md"    "$CTX/"
mkdir -p "$CTX/conventions"
cp "$ROOT/docs/conventions/"*.md  "$CTX/conventions/"
cp "$ROOT/agents/delegate.md"     "$CTX/"
```

`log.md` is never copied into `$CTX`. The Delegate physically cannot read it.
After the verdict is written, `watcher.sh` removes the staging dir:
`rm -rf "$CTX"`
The canonical artifacts remain in `$RUN_DIR`; the staged copies are throwaway.

The `$DELEGATE_TASK_PROMPT` names the staged files by their ABSOLUTE `$CTX` paths
(`$CTX/<artifact>`, `$CTX/log-slice.md`, `$CTX/state.json`, `$CTX/conventions.md`,
`$CTX/conventions/`, `$CTX/delegate-reviewer.md`, and `$CTX/integration-results.json` at integration
checkpoints) — bare relative names are looked up at the git/workspace root, not the
spawn CWD, and are DENIED by `--add-dir "$CTX"`. Every named path is INSIDE `$CTX`. It
cannot name `log.md` because `log.md` is not in scope.

### Integration-mode staging additions

When `checkpoint-type: integration`, the watcher also writes:
  `$CTX/integration-results.json` — the pre-spawn ground-truth file containing
  canonical gate execution results, pre-existing-red validation at base-ref,
  under-declaration cross-check, scope-diff, and fast-forward/conflict results.

This file is the watcher's INTERNAL channel (snake_case field names; not
schema-validated). The Delegate re-projects its fields into the schema-PascalCase
`Integration-evidence` keys when emitting the verdict.

The `DELEGATE_TASK_PROMPT` (`watcher.sh:284`) also switches to an integration
variant that names `integration-results.json` as a required read. The routine
prompt is unchanged when `checkpoint-type` is routine/absent.

`log.md` is still never staged in any mode. The EC8 assertion (`watcher.sh:276-279`)
is unchanged.

**OQ-B14-1 decision: option (c).** The watcher (not the Delegate) runs the canonical
gate commands. The Delegate stays `--tools "Read"` and reads only `$CTX`. This
preserves the § 3 hard constraints (no Bash grant; the worktree is never added to the
Delegate's read root; no-write constraint). The watcher resolves the canonical gate
set from the project's own runners (regression runner + manifest), never from
`claimed-gates` (FR-B14-3, FR-B14-14) — the verified party does not define what
gets executed.

**Two-part insertion in watcher.sh:** the integration executor spans insertion point A
(parse + short-circuit flags, before staging at line 262 — no file writes yet) and
insertion point B (write integration-results.json + override DELEGATE_TASK_PROMPT,
after the EC8 assertion at line ~279 — $CTX exists here). The $CTX-must-exist-before-
write invariant is maintained: no file targeting $CTX is written before $CTX is created.

**`known-flaky-gates` demotion (OQ-B14-4):** an optional `known-flaky-gates` field in
the request lists gates whose re-run failures are known flaky. The watcher marks matching
red gates with `flaky: true` in the staged results; the Delegate flags those entries in
Uncertainties instead of blocking. Absent ⇒ every re-run red blocks (the conservative
default). This is a membership test, not preference modeling (FR-44).

## Section 5: Conductor checkpoint shim (additive protocol — A3)

This is the protocol the Conductor runs at each checkpoint when a Delegate is attached. It is
additive to the existing `[CHECKPOINT]` block in `agents/orchestrator.md`, which remains
unchanged as the fallback when no watcher is running. The per-checkpoint reminder lives in
`agents/orchestrator.md` § "v1 / watcher-attended fallback: Consuming a delegate verdict"; this
is the protocol source.

Steps (the Conductor performs these at each checkpoint when the watcher is active):

1. Write the artifact under review to its RUN_DIR path. Hash it:
   `shasum -a 256 "$ARTIFACT" | awk '{print $1}'` (fallback: `sha256sum "$ARTIFACT"`)
2. Write `RUN_DIR/checkpoints/NN-request.md` carrying both `attempt` and `revise-count`
   (start at attempt=1, revise-count=0; see Section 2 for increment rules).
3. Call `scripts/await-verdict.sh "$RUN_DIR/checkpoints/NN-verdict.md" <timeout>` via
   **`run_in_background`** (Bash tool, background=true). End the turn here.
   Zero model tokens are spent while the script sleep-loops.
4. On the completion notification: the script exits 0 (verdict file appeared) or exit 2
   (timeout). Read `NN-verdict.md`. Act:
   - `proceed` → continue
   - `revise` → route the fix, increment `revise-count`, re-issue request (Section 2)
   - `escalate` → hold; read `NN-robin.md` when Robin responds
   - exit 2 (timeout) → treat as escalation; do not auto-proceed (FR 37)
5. Fallback: if no watcher is running, use the normal `[CHECKPOINT]` human prompt.

## Section 6: Revision cap rule (FR 35 / EC7)

`verdict-write.sh` enforces the cap. Default cap: 2 (configurable as `revision_cap` in
`delegate-session.json`). The cap is counted against `revise-count` in the request file.

When `revise-count` ≥ cap at verdict-write time: `verdict-write.sh` rewrites the decision
to `escalate`, regardless of what the Delegate emitted. This rewrites the verdict JSON
before writing `NN-verdict.md`, so the Conductor sees `escalate` in the verdict file.

A hash-rebind re-issue (which bumps `attempt` but NOT `revise-count`) never trips the cap.
Two consecutive hash-rebinds at the cap value still produce a non-escalate verdict. Only
a real `revise` re-issue (where `revise-count + 1`) counts toward the cap.

## Section 7: Bridge failure modes (FR 37–40)

- **Timeout (FR 37):** `await-verdict.sh` exits 2. The Conductor treats this as escalation.
  The loop does NOT auto-proceed. `notify-escalation.sh` fires (see Section 8). The loop
  holds until Robin writes `NN-robin.md`.
- **Watcher restart (FR 38/EC3):** On restart, re-scan for `*-request.md` with no matching
  `*-verdict.md`. Skip any request that already has a verdict. The `mkdir NN.lock` atomic
  claim prevents a second watcher from spawning a Delegate for the same request. A stale
  lock whose PID is dead: remove the lock dir and re-claim. The lock dir carries the
  spawning PID.
- **Duplicate/partial writes (FR 39/EC6):** tmp→rename ensures the verdict file is either
  complete or absent. A `.tmp` file left behind on crash is NOT `NN-verdict.md`; the watcher
  treats it as absent and re-spawns.
- **Stale requests (FR 40):** Each request file carries `run-dir:` for cross-restart
  identification. A watcher that reads a request from a different run-dir must not claim it.
- **Persistent spawn failure (spawn-failure ceiling, money-safety):** `--max-budget-usd`
  caps the spend of one spawn but not the number of spawns, so a Delegate that keeps emitting
  invalid/empty JSON (verdict-write fails closed, no verdict) would otherwise be re-spawned
  every poll forever — unbounded spend. The watcher counts consecutive failed spawns per
  checkpoint in `RUN_DIR/checkpoints/NN.failcount`. After `MAX_SPAWN_FAILURES` (default 3) in
  a row for one NN, it gives up: fires `notify-escalation.sh`, writes a poison marker
  `RUN_DIR/checkpoints/NN.failed` so later poll passes skip the request, and stops
  re-spawning. Attended intervention is then required. A successful verdict clears the
  failcount.

## Section 8: Escalation channel (FR 7 / EC4 / A2)

On escalation (any verdict decision = escalate):

1. `notify-escalation.sh` fires `osascript -e 'display notification ...'`.
2. On `osascript` failure (Linux, CI, or notification daemon down): write
   `RUN_DIR/checkpoints/ESCALATION-NN.md` and retry the notification. Never abort the loop.
3. The loop holds indefinitely. The absence of a Robin reply does NOT unblock the loop.
   Auto-proceed on timeout is prohibited.
4. Robin responds by writing `RUN_DIR/checkpoints/NN-robin.md`. On detection:
   `verdict-write.sh` populates the ledger entry's `Robin's call:` field.

## Section 9: Decision ledger schema (FR 26–28 / OQ4)

One record per verdict, appended by `ledger-append.sh`. Never edited in place (FR 27).
No rolling summary in this file (FR 28).

Record format:

```
## NN.A — <ISO-8601 timestamp>
decision:      proceed | revise | escalate
artifact:      <path>       ← OQ4 addition: path so a cold auditor can open the artifact
artifact-hash: <sha256>
uncertainties: <text>
rationale:     <1–2 sentences>
borderline:    yes | no
refs:          <notary review path | none>
Robin's call:  <populated only when an escalation resolves; else blank>
```

The `artifact:` path field (not just hash) is required so a future cold auditor (v3 self-
audit gate) can re-evaluate a `proceed` from the ledger entry alone without parsing other
run files.

## Section 10: Attended-only constraint (FR 43)

Until the self-audit gate (v3) exists and reads clean, the Delegate runs attended. This is
a constraint, not a TODO: "Do not run the Delegate loop unattended until FR 43's self-audit
gate is implemented and has a clean run." No code implements this gate in this bundle; it is
documented here as the v3 prerequisite.

## Section 11: Done criteria

Objective checks that the bridge is operating correctly (not "looks right"):

- A hand-written `NN-request.md` + stubbed Delegate JSON exercises the full chain
  (lock → stage → validate → tmp→rename → ledger append → rm context dir → summary).
- `NN-context/` contains the slice but NOT `log.md` (assert `log.md` absent from the dir).
- Hash mismatch → escalate + no verdict written.
- Missing field → escalate + no verdict written.
- `revise-count` ≥ cap → decision rewritten to escalate.
- Hash-rebind (bumped `attempt`, same `revise-count`) → NOT escalated.
- `await-verdict.sh` timeout → exit 2.
