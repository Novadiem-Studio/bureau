# Delegate Bridge — Conductor Hot Path

This is the Conductor-facing router and hot-path contract for the bridge between The Conductor
and The Delegate. Keep this file small: it holds checkpoint type classification, the v1 request
fields the Conductor must write, and the Conductor checkpoint shim. Implementation details live
in the on-demand modules below.

## Delegate bridge read scope (token discipline)

**Always-read core when checkpoint traffic goes through the Delegate bridge:**
1. `docs/delegate-bridge.md` (this file).

**Load on demand:**
- `docs/delegate-bridge/v2-integrated.md` — only for integrated-topology runs,
  CONDUCTOR-RETURN schema work, Delegate manager implementation, cold-reviewer spawn recipe,
  `delegate-state.json`, or v2 staged-manifest details.
- `docs/delegate-bridge/watcher-v1.md` — only for watcher/file-mailbox implementation,
  watcher spawn/staging internals, verdict writing, revision-cap enforcement, ledger, escalation,
  or bridge failure modes.

If a module is not triggered, do not read it "just in case."

---

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
- `routine` for all other checkpoints: pre-spec grill, design review, spec review, plan
  review, phase-boundary handoff, and per-prompt build/accept checkpoints.
- Default for any unmapped phase: `routine`. A phase is integration only by explicit
  declaration, not by Delegate inference.

Phase mapping for v1:

- `execute-plan` close-out merge (GitHub PR or local fallback into integration branch) → `integration`
- `bug-fix` GitHub PR / local fallback merge to main or integration branch → `integration`
- `feature` runs (plan-type, no build/merge phase) → no integration checkpoints; a pre-spec
  grill checkpoint, when present, is `checkpoint-type: routine`
- deploy/promote phases → deferred; set as `routine` for now

Do not invent `checkpoint-type: grill`. The checkpoint id may be `"grill"` for accounting and
human readability, but the bridge type remains `routine` unless the checkpoint is an
integration gate. If the content requires Robin to decide a material fork, the v2 Conductor uses
the existing `genuine-fork` return shape and existing escalation signals; the bridge type system
does not gain a new class.

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
  Conductor write of `state.json` can never clobber it). See
  `docs/delegate-bridge/v2-integrated.md § v2 §8` (AC16).

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
