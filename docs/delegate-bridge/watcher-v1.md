# Delegate Bridge — v1 Watcher Implementation

> On-demand module for `docs/delegate-bridge.md`. Load only for watcher/file-mailbox implementation work. The Conductor hot path remains in `docs/delegate-bridge.md`.

# v1 / watcher-attended fallback — implementation details

The root bridge doc keeps Section 2 (checkpoint file convention/classification) and Section 5 (Conductor checkpoint shim). This module keeps the watcher-side mechanics.

## Section 3: The load-bearing spawn invocation (identity isolation — EC1/EC8)

The watcher has no provider-specific spawn. After staging, it calls the same
single-source adapter as v2:

```sh
REVIEW_META="$(
  scripts/run-cold-reviewer.sh \
    "$RUN_DIR" "$CTX" "$REQ_CHECKPOINT" "$SPAWN_ID" "$ARTIFACT_BASE" "$REVIEW_MODE"
)"
```

`$CTX = RUN_DIR/checkpoints/NN-context/`. The helper reads
`model-routing.json#runtime`, creates a unique verdict/envelope pair, and returns their paths.
The watcher copies the normalized verdict to the legacy `NN.delegate-out.json` compatibility
path, appends one reviewer token event from the envelope, then calls `verdict-write.sh`.

The load-bearing provider guarantees are owned by
`docs/delegate-bridge/v2-integrated.md § v2 §3` and `docs/host-runtime.md`:

- Claude retains CWD=`$CTX`, `--system-prompt`, `--tools "Read"`,
  `--add-dir "$CTX"`, `--setting-sources ""`, `--no-session-persistence`, and no `--bare`.
- Codex uses an ephemeral copied packet, ignores user config/rules, closes the schema at every
  object boundary, disables network tools, and denies live run/repository/session paths.

The reviewer is read-only and cannot access `RUN_DIR/log.md` on either host. The watcher alone
owns durable writes.

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
awk '/^# COLD-REVIEWER-MODE:BEGIN/,/^# COLD-REVIEWER-MODE:END/' \
  "$ROOT/agents/delegate.md" > "$CTX/delegate-reviewer.md"
```

`log.md` is never copied into `$CTX`. The Delegate physically cannot read it.
After the verdict is written, `watcher.sh` removes the staging dir:
`rm -rf "$CTX"`
The canonical artifacts remain in `$RUN_DIR`; the staged copies are throwaway.

The helper's task prompt names the staged files by their isolated absolute context paths
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

The helper also switches to an integration
variant that names `integration-results.json` as a required read. The routine
prompt is unchanged when `checkpoint-type` is routine/absent.

`log.md` is still never staged in any mode. The EC8 assertion remains enforced.

**OQ-B14-1 decision: option (c).** The watcher (not the Delegate) runs the canonical
gate commands. The Delegate stays `--tools "Read"` and reads only `$CTX`. This
preserves the § 3 hard constraints (no Bash grant; the worktree is never added to the
Delegate's read root; no-write constraint). The watcher resolves the canonical gate
set from the project's own runners (regression runner + manifest), never from
`claimed-gates` (FR-B14-3, FR-B14-14) — the verified party does not define what
gets executed.

The watcher parses the integration fields before staging, creates `$CTX`, then invokes
`integration-gate.sh` to write `integration-results.json` before the provider-neutral reviewer.
The `$CTX`-must-exist-before-write invariant remains: no gate output targets `$CTX` before it
is created.

**`known-flaky-gates` demotion (OQ-B14-4):** an optional `known-flaky-gates` field in
the request lists gates whose re-run failures are known flaky. The watcher marks matching
red gates with `flaky: true` in the staged results; the Delegate flags those entries in
Uncertainties instead of blocking. Absent ⇒ every re-run red blocks (the conservative
default). This is a membership test, not preference modeling (FR-44).

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

The `artifact:` path field (not just hash) is required so a future cold auditor for the
self-audit gate can re-evaluate a `proceed` from the ledger entry alone without parsing other
run files.

## Section 10: Attended-only constraint (FR 43)

Until the self-audit gate exists and reads clean, the Delegate runs attended. This is
a constraint, not a TODO: "Do not run the Delegate loop unattended until FR 43's self-audit
gate is implemented and has a clean run." No code implements this gate in this bundle; it is
documented here as the unattended-operation prerequisite.

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
