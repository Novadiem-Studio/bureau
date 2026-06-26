# Battle-test — Delegate v2 (integrated nesting)

Pre-promotion matrix for the Delegate v2 integrated-nesting topology (Delegate top-level
session, Conductor as a resumable Agent-tool subagent, cold reviewer as a headless `claude -p`
one-shot). Format: `docs/conventions.md § Battle-test matrix file format`. This is the
pre-promotion run; promotion re-runs the full matrix and writes a fresh `## Run` block above
this one.

## Run 2026-06-25

| Case name | Input description | Expected outcome | Actual result |
|-----------|-------------------|------------------|---------------|
| **happy path** (typical) — routine checkpoint in v2 mode | A minimal v2 feature run: Delegate spawns the Conductor subagent (`topology: integrated`); the Conductor writes an artifact and returns a `routine-checkpoint` block; the Delegate stages `$CTX` and spawns the cold reviewer; the reviewer returns `proceed`; the Delegate resumes the Conductor via `SendMessage`. | Run completes; `state.json` records the Conductor as a depth-1 subagent and carries NO `delegate` block; no Robin interaction; the routine checkpoint is gated by a cold-reviewer spawn, never AskUserQuestion/`[CHECKPOINT]`. | **pass (mechanism) — BLOCKED as-shipped, see Open BLOCKER.** Topology proven by the Part-1 Conductor trace (depth-0 Delegate / depth-1 Conductor; resume at `tool_uses:0` with verbatim resume-token echo; `state.json` carries no delegate block). The cold-reviewer leg ran LIVE in Part 2 and returned a schema-valid `proceed` verdict against real integration-gate.sh evidence — but ONLY after two recipe corrections (inline `--json-schema`; absolute `$CTX` paths). The canonical recipe AS SHIPPED fails on claude 2.1.187 (`--json-schema` path defect). |
| **genuine fork** (edge — signal 5) | A checkpoint where the Conductor detects a production/release deploy (escalation signal 5) and returns a `genuine-fork` block instead of a routine one. | The Conductor does NOT call AskUserQuestion (unavailable to subagents); it RETURNS the fork. The Delegate surfaces it to Robin via AskUserQuestion; on Robin's answer the Conductor resumes at `tool_uses:0` (context-only). Robin is asked exactly once. | **pass (trace + inspection).** Part-1 trace: at checkpoint 02 the Conductor emitted a `genuine-fork` block with `signal-fired:5` and resumed at `tool_uses:0` echoing `v2trace-02-qz7bn3wd`. Phase-0 TEST 2 already proved AskUserQuestion is unavailable to subagents (so the Conductor must return, and the top-level Delegate owns the ask). The live interactive Robin-ask is attended and was not exercised in this hermetic run. |
| **cold-reviewer failure** (failure mode) — no self-grade | The cold-reviewer subprocess fails (budget exceeded, `claude -p` error, or unavailable). | AC11: the Delegate does NOT self-grade; the failure escalates to Robin (AskUserQuestion) with the checkpoint context. No warm-manager verdict path exists. | **pass — behavior specified in `agents/delegate.md` and verified by inspection (AC11).** `agents/delegate.md:192-196`: "ESCALATE TO ROBIN. NEVER self-grade … There is no 'degenerate case' fallback that lets the warm manager emit a verdict … every gating verdict comes from a cold reviewer spawn." Live exercise requires a deliberately broken claude env; not run. |
| **nested spawn unavailable** (failure mode) — AC12 diagnostic | The Delegate's first Conductor spawn fails because the host lacks nested-spawn support. | AC12: the Delegate surfaces the exact diagnostic and stops, does not proceed warm: "Nested spawning unavailable — v1 file-mailbox fallback required. Run scripts/delegate-launcher.sh to start the watcher." | **pass — verified by inspection (AC12).** `agents/delegate.md:199-200` carries the diagnostic verbatim, byte-for-byte. Live exercise requires a host without nested-spawn support; not run. |
| **revision-cap hit** (failure mode) | A checkpoint that produces a 2nd `revise` verdict at `revision_cap: 2`. | On the cap-reaching revise, `revise-cap.sh` emits `escalate` and the Delegate escalates to Robin; the Conductor's return block carries NO revise counter (the cap is `revise-cap.sh`'s sole authority). | **pass (live).** Part 4: `revise-cap.sh DS 03 2` with `revise_counts.03=1` → stdout `escalate`, count→2, all other keys untouched; the under-cap case → `revise`, count→1. The CONDUCTOR-RETURN schema (`docs/delegate-bridge.md § v2 §1`) explicitly states the block carries NO revise counter (W5); the cap is the Delegate's `delegate-state.json#revise_counts[NN]` via `revise-cap.sh` alone. |
| **schema-drift guard** (edge — carried from the Prompt-6 Challenger review) | Mutate one field in the CONDUCTOR-RETURN schema in `docs/delegate-bridge.md § v2 §1` (the canonical source); the A4 copy in `agents/orchestrator.md` must be caught as divergent. | A drift between the two blocks is caught; the documented control is the RECIPROCAL SYNC NOTE requiring both blocks to be edited in the same commit. | **pass (control verified; no automated fixture yet).** The two CONDUCTOR-RETURN fenced blocks (bridge §v2 §1 and orchestrator §A4) are BYTE-IDENTICAL today (21 lines each; `diff -q` clean). The RECIPROCAL SYNC NOTE at `delegate-bridge.md:42-45` is the documented control. A drift today is caught only by reviewer discipline + that note; **recommendation: add a standing fixture** that extracts both fenced blocks and asserts byte-identity, so a future single-file edit fails the suite. |

---

### Verification notes

- **Live cold-reviewer leg (Case 1, Part 2):** `scripts/integration-gate.sh` produced a Track-3 proceed-evidence `integration-results.json` (no `verdict` key); the staged `$CTX` held the v2 §9 manifest (artifact, the W-d awk slice `delegate-reviewer.md`, `conventions.md`, `log-slice.md`, scope `state.json`, `integration-results.json` — never the full `log.md` or the full dual-mode `delegate.md`). The headless `claude -p` reviewer (model `sonnet`, $0.18) returned `Decision: proceed` with a well-formed `Integration-evidence` block (correct PascalCase re-projection, inner keys `exit-code-on-branch`/`exit-code-on-base`/`confirmed-pre-existing`), hash-bound to the artifact. Verdict: `spike/track3-v2-verdict.json`.
- **Coldness (AC13) is OS-enforced:** a dedicated probe confirmed the reviewer's Read of `RUN_DIR/log.md` is denied at the OS layer (`permission_denials` records the path; reviewer self-reported `{"log_read":"blocked"}`). The leak is prevented, not caught.
- **v1 fallback (AC7):** F10 (watcher → integration-gate.sh, claude stubbed) PASS — the watcher stages Track-3 proceed-evidence field-for-field. The `--bare`-drop (R6) is confirmed in `watcher.sh` (`--setting-sources ""` carries CLAUDE.md suppression). F11 (live routine reviewer) FAILS as-shipped on the same `--json-schema` path defect (see Open BLOCKER); the scratch-patched watcher cleared the parse error.
- **FR-44 (AC10):** every preference-modeling-term hit across the 7 edited/created files is an FR-44 negation/boundary statement that FORBIDS preference modeling; no actual model, placeholder, or hook exists.

### Open BLOCKER (pre-promotion) — `--json-schema` path defect

The canonical cold-reviewer recipe passes the verdict schema as a **file path**:
`--json-schema "$ROOT/config/delegate-verdict.schema.json"`. On claude 2.1.187 the
`--json-schema <schema>` flag takes an **inline JSON Schema string**, not a path, so the
spawn aborts with `Error: --json-schema is not valid JSON: JSON Parse error: Unrecognized
token '/'` and writes no verdict. This was never live-tested before Phase 5 (Phase-0 TEST 3
omitted `--json-schema`). The defect appears at five call sites:

- `scripts/watcher.sh:357`
- `agents/delegate.md:134`
- `docs/delegate-bridge.md:112`, `:454`, and the now-incorrect "MUST be absolute" note at `:133`

**Fix (one line per site):** pass the schema contents inline, e.g.
`--json-schema "$(cat "$ROOT/config/delegate-verdict.schema.json")"`. Proven in Part 2 (live
`proceed` verdict) and Part 3 (scratch-patched watcher cleared the parse error). A second,
related correction is needed for the v2 stager: bare `$CTX`-relative filenames in the task
prompt resolve against the detected git/workspace root, not CWD=`$CTX`, when `$CTX` lives
inside a git tree, so the reviewer cannot read its staged files; name them by absolute `$CTX`
path (still inside `$CTX`, so coldness and the AC4 "no path outside `$CTX`" rule hold), or
stage `$CTX` outside any git tree.

These corrections are the same class as the Phase-0 `--setting-sources ""` finding: a
recipe/invocation fix the build must apply. Promotion to canon is gated on landing them and
re-running this matrix with the live happy-path and the v1 routine path both green.

### waiver

None. The two failure-mode cases (cold-reviewer failure, nested-spawn unavailable) are marked
`pass` by inspection of the specified behavior, not `fail`, so no waiver is required. The
`--json-schema` defect is recorded as an Open BLOCKER above, not waived — it must be fixed
before canon promotion.
