# Delegate Bridge — Escalation Contract and File-Mailbox Protocol

This is the neutral authority document for the bridge between the Conductor and the Delegate.
It is owned by neither persona: `agents/delegate.md` owns the Delegate's role, the critic
checklist, and the verdict fields; `agents/orchestrator.md` owns the Conductor's internals
and the per-checkpoint reminder; this doc owns the shared protocol — the file conventions,
the spawn invocation, staging, the cap rule, and the failure modes. Cross-reference those
files; do not restate their content here.

## Section 1: Objective

This document specifies the file-mailbox protocol through which the Conductor and the
Delegate coordinate at each checkpoint, without meeting in the same context.

## Section 2: Checkpoint file convention (AC 6)

**Naming:** `RUN_DIR/checkpoints/NN-request.md`, `RUN_DIR/checkpoints/NN-verdict.md`,
`RUN_DIR/checkpoints/NN-robin.md` (escalation response). NN is a zero-padded ordinal.

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
  (see spec Architecture Data Models §2, A6 ruling).

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

The spawn invocation that the watcher uses is exactly:

```sh
claude -p \
  --bare \
  --system-prompt "$DELEGATE_SYSTEM_PROMPT" \
  --model "$DELEGATE_MODEL" \
  --output-format json \
  --json-schema "$ROOT/config/delegate-verdict.schema.json" \
  --tools "Read" \
  --add-dir "$CTX" \
  --setting-sources "" \
  --no-session-persistence \
  --max-budget-usd "$DELEGATE_MAX_USD" \
  "$DELEGATE_TASK_PROMPT"
```

Where `$CTX` = `RUN_DIR/checkpoints/NN-context/` (the staged per-checkpoint read scope).

Each flag's load-bearing job:

- `--bare`: disables CLAUDE.md auto-discovery at the harness level. The "you are the
  Conductor" CLAUDE.md rule can never fire. This is the primary EC1 guard.
- `--system-prompt "$DELEGATE_SYSTEM_PROMPT"`: sets the full system prompt to:
  "You are The Delegate. Do not load CLAUDE.md. Do not act as the Conductor."
  This names the Delegate identity explicitly (FR 33). Belt-and-suspenders with `--bare`.
- `--tools "Read"`: the Delegate has no write access to the repo. Every write is owned by
  the bridge scripts. This is a hard constraint, not a convention.
- `--add-dir "$CTX"`: the ONLY read root is the staged context dir. The Delegate cannot
  read `$RUN_DIR`, `log.md`, the rest of the repo, or any other run. EC8 is a filesystem-
  level exclusion, not a prompt instruction.
- `--setting-sources ""`: suppresses user/project/local `settings.json` so no settings file
  can re-inject a Conductor identity, tool grant, or hook. W1 is RESOLVED: this flag is
  parser-legal (exit 0) and non-redundant with `--bare` — `--bare`'s documented scope is
  CLAUDE.md auto-discovery, which does not cover `settings.json` sources, so this flag closes
  a distinct hole. It stays in the load-bearing flag set: `--bare --system-prompt <…>
  --setting-sources "" --tools "Read" --add-dir NN-context …`.
- `--no-session-persistence`: no session to resume; each checkpoint is transcript-free.
- `--max-budget-usd "$DELEGATE_MAX_USD"`: per-checkpoint spend ceiling (default 0.50).

The `--bare` + `--system-prompt` PAIR is the load-bearing identity guard. `--bare` removes
the CLAUDE.md path; `--system-prompt` installs the Delegate identity in its place. If either
is changed, the other must still be present — document any change to this pair here.

## Section 4: Staging (the per-checkpoint read-scope assembly — EC8 fix)

Before the Delegate spawn, `watcher.sh` stages the read set into a scratch dir:

```sh
CTX="$RUN_DIR/checkpoints/$CP-context"
mkdir -p "$CTX"
cp "$ARTIFACT"                    "$CTX/"
cp "$LOG_SLICE"                   "$CTX/log-slice.md"
cp "$RUN_DIR/state.json"          "$CTX/"
cp "$ROOT/docs/conventions.md"    "$CTX/"
cp "$ROOT/agents/delegate.md"     "$CTX/"
```

`log.md` is never copied into `$CTX`. The Delegate physically cannot read it.
After the verdict is written, `watcher.sh` removes the staging dir:
`rm -rf "$CTX"`
The canonical artifacts remain in `$RUN_DIR`; the staged copies are throwaway.

The `$DELEGATE_TASK_PROMPT` names the staged files by their `$CTX`-relative paths
(the artifact, `log-slice.md`, `state.json`, `conventions.md`, `delegate.md`). It
cannot name `log.md` because `log.md` is not in scope.

## Section 5: Conductor checkpoint shim (additive protocol — A3)

This is the protocol the Conductor runs at each checkpoint when a Delegate is attached. It is
additive to the existing `[CHECKPOINT]` block in `agents/orchestrator.md`, which remains
unchanged as the fallback when no watcher is running. The per-checkpoint reminder lives in
`agents/orchestrator.md` § "Consuming a delegate verdict"; this is the protocol source.

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
