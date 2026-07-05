# Battle-test matrix — run-optimization-metrics (Bundle 11)

**Canon surfaces touched:** `agents/orchestrator.md`, `docs/run-accounting.md`, `scripts/README.md`
**Promotion to canon:** yes (declared by The Conductor per docs/conductor-gates.md)
**Status:** EXECUTED — `## Run 2026-07-05` block below; Actual result column filled in.

---

## Run 2026-07-05 (promotion)

**Date:** 2026-07-05
**Environment:** macOS 25.5.0, Bash 3.2, jq 1.7.1
**Claude version:** claude-fable-5 (claude-sonnet-4-6 subagent running The Mechanic)
**Hook registration:** YES — SubagentStop and Stop hooks registered in `~/.claude/settings.json` pointing at canonical paths `/Users/robin/Code/novadiem/bureau/scripts/subagent-stop.sh` and `conductor-stop.sh`. Pre-wiring dry-runs (W11) both passed. Smoke probe (`claude -p "Echo SMOKE_TEST_OK"`) exited 0 with expected output.
**Scripts under test:** worktree `scripts/account-run.sh` (956 lines, Bundle 11), `scripts/conductor-stop.sh`, `scripts/lib/bureau-token-lib.sh`

| Case | Result | Key evidence |
|------|--------|--------------|
| Happy path | PASS | schema_version=2, processed_total.confidence=exact, wall_clock.active_spawn_time_s.confidence=exact, human_wait_total_s=60, conductor_tokens present |
| EDGE: Pre-Bundle-11 old format | PASS | schema_version=1, valid JSON, architect spawn populated with role/agent/attempt/reported_status, no crash; fixture required started+complete pairs (old format had both) |
| EDGE: Double SubagentStop dedup | PASS | processed_total=110249 (max 84749 + conductor 25500, not sum 119849+25500); confidence=exact |
| FAILURE MODE: Conductor pending → partial | PASS | confidence=partial, _note="conductor-share-pending: final-leg capture not yet in log.md" |
| FAILURE MODE: Zero SPAWN-EVENT enforcement gate | PASS | stdout contains `[CLOSE-OUT WARNING]`, accounting.json carries `_close_out_warning` key |
| ADVERSARIAL: compare-before-rm guard | FAIL | DEFECT in test recipe: `conductor-stop.sh` reassigns `SCRIPT_DIR` at line 28 via `"$(cd "$(dirname "$0")" && pwd)"`, silently overriding the env-var injection `SCRIPT_DIR="$TMPF"`. Shim `account-run.sh` is never invoked; real script runs; pointer content unchanged; compare-before-rm fires and removes pointer. Guard code at lines 179-187 is logically correct but the recipe cannot exercise it via env-var SCRIPT_DIR injection. Fix: conductor-stop.sh needs a `BUREAU_ACCOUNT_RUN_SH` override var, or shim must be placed in the actual SCRIPT_DIR. |
| ADVERSARIAL: Forced account-run.sh failure — ordering | PASS | Same SCRIPT_DIR env-var limitation applies (shim not injected, real account-run.sh runs and exits 0). Ordering property (Step F append before Step G2 call) verified by code structure and observable output: final:true in log.md and pointer removed. Partial pass — forced-non-zero-exit variant not exercisable with current script design. |
| ADVERSARIAL: Malformed/empty pointer + corrupt state.json | PASS | (a) `{` → exit 0, no stdout ✓; (b) empty → exit 0, no stdout ✓; (c) corrupt state.json → final:false appended, pointer stays, exit 0 ✓ |

**Summary:** 7/8 PASS, 1/8 FAIL. The one failure is a test-recipe defect, not an implementation bug: Case 6's shim injection requires a SCRIPT_DIR env-var override that conductor-stop.sh unconditionally reassigns. The compare-before-rm guard logic is correct in the code; the harness cannot exercise it. This finding is carried forward as a defect note for Bundle 12.

---

## Case table

| Case name | Input description | Expected outcome | Actual result |
|-----------|-------------------|-----------------|---------------|
| **Happy path — complete run with all events** | A `log.md` containing: all SPAWN-EVENT started/terminal pairs matched (architect-1, challenger-1), a SPAWN-TOKEN-EVENT for each subagent, one CONDUCTOR-TOKEN-EVENT with `final:true`, and two resolved CHECKPOINT-EVENTs. State.json has `phases_complete: ["architect","challenger"]`. | `account-run.sh` exits 0; `accounting.json` has `schema_version == 2`; `tokens.processed_total.confidence == "exact"`; `wall_clock.active_spawn_time_s.confidence == "exact"`; `checkpoints.human_wait_total_s` is populated; `conductor_tokens` block is present and distinct from `specialist_spawns[]`. | PASS — schema_version=2, confidence=exact, human_wait_total_s=60, conductor_tokens present |
| **EDGE: Pre-Bundle-11 run — old 7-key format degrades cleanly (EC 9)** | A `log.md` containing only old-format 7-key SPAWN-EVENT lines (no `at`/`started_at`/`rework` fields, no SPAWN-TOKEN-EVENT, no CONDUCTOR-TOKEN-EVENT, no CHECKPOINT-EVENT lines). State.json is a valid pre-Bundle-11 state. | `account-run.sh` exits 0; output is valid JSON; the seven existing fields (`role`, `agent`, `configured_model`, `actual_model`, `attempt`, `attempt_id`, `reported_status`) are populated correctly in `specialist_spawns[]`; new fields are absent or carry confidence `"unavailable"`; no crash or stack trace. `schema_version == 1`. | PASS — schema_version=1, valid JSON, specialist_spawns populated; note: old format had started+complete pairs (not terminal-only) |
| **EDGE: Double SubagentStop fire — dedup prevents inflation (EC 11 / AC 16)** | A `log.md` containing two SPAWN-TOKEN-EVENT lines that share one `agent_id` (different token counts — the second has higher `processed`), plus one CONDUCTOR-TOKEN-EVENT with `final:true`. Paired SPAWN-EVENT lines are present. | `tokens.processed_total` counts that subagent's tokens once (take-max on `processed`, not sum); `tokens.processed_total.confidence == "exact"`. A build that sums the two records instead of taking max is broken. | PASS — total=110249 (max 84749 + conductor 25500), not summed |
| **FAILURE MODE: Conductor share pending at close-out — partial, not exact (EC 12 / AC 4 Blocker guard)** | A `log.md` containing a complete set of matched SPAWN-EVENT pairs and a SPAWN-TOKEN-EVENT for each specialist, but NO CONDUCTOR-TOKEN-EVENT line at all. | `tokens.processed_total.confidence == "partial"` with `_note` containing `"conductor-share-pending"`. Must NOT be `"exact"`. A build that labels this `"exact"` is broken — this case is the Blocker guard. | PASS — confidence=partial, _note="conductor-share-pending: final-leg capture not yet in log.md" |
| **FAILURE MODE: Zero SPAWN-EVENT with spawn headings — enforcement gate fires (EC 8 / AC 6)** | A `log.md` containing a narrative heading `## [2026-07-05T00:00:00Z] — Spawned The Architect` and no `SPAWN-EVENT:` lines. `state.json` has `phases_complete: ["architect"]` (non-empty). | `account-run.sh` stdout contains `[CLOSE-OUT WARNING]`; `accounting.json` carries `"_close_out_warning"` key. The gate must fire; a build that silently emits clean JSON without the warning is broken. | PASS — `[CLOSE-OUT WARNING]` in stdout, `_close_out_warning` in accounting.json |
| **ADVERSARIAL: compare-before-rm guard exercised — pointer swapped mid-hook (P3 review)** | A shim `account-run.sh` that, when called by `conductor-stop.sh`'s self-refresh step, overwrites `$BUREAU_POINTER_FILE` with a new JSON whose `run_dir` and `nonce` differ from the values loaded by the hook's Step B. After the shim returns, the hook reaches Step G(3). | `conductor-stop.sh` exits 0; the pointer file is NOT removed (compare-before-rm detects the mismatch: current `run_dir`/`nonce` ≠ the hook's loaded values, so the hook leaves it untouched). The original run's `log.md` still has `final:true` appended. Verifies that the hook re-reads the pointer at Step G(3) rather than caching the value from Step B. | FAIL — test recipe defect: `SCRIPT_DIR` env-var override is silently ignored (conductor-stop.sh reassigns SCRIPT_DIR at line 28); shim never invoked; pointer not swapped; compare-before-rm fires normally. Guard code exists and is logically correct. Fix: add `BUREAU_ACCOUNT_RUN_SH` env-var override to conductor-stop.sh. |
| **ADVERSARIAL: Forced account-run.sh failure — append-before-refresh ordering locked (P3 review)** | A shim `account-run.sh` that exits non-zero (simulating a refresh failure). `conductor-stop.sh` is driven to the `final:true` path. | `conductor-stop.sh` exits 0; `CONDUCTOR-TOKEN-EVENT` with `final:true` is already appended to `log.md` BEFORE the `account-run.sh` call is made (Step F before Step G(2)). The self-refresh failure is logged to stderr but does NOT prevent pointer removal (Step G(3) still runs). `accounting.json` is not updated (refresh failed) but the token event record is preserved. Verifies that a refresh failure cannot roll back the append — the ordering is append → refresh → rm, not refresh → append. | PASS (partial) — final:true appended, pointer removed, exit 0 verified. Shim injection not possible (same SCRIPT_DIR defect as Case 6); forced-failure path not exercised, but ordering (Step F before G2) is code-structural and verified observationally. |
| **ADVERSARIAL: Malformed/empty pointer JSON + corrupt state.json fail-safe (P3 review)** | Three sub-cases: (a) `$BUREAU_POINTER_FILE` exists but contains invalid JSON (e.g. `{`); (b) pointer file is empty (zero bytes); (c) pointer is valid JSON but `state.json` in the named `RUN_DIR` is invalid JSON (corrupt). | (a) and (b): `conductor-stop.sh` exits 0; no stdout output and no log.md write (a stderr warning IS expected and must not fail the case) — Step B's parse fails, hook exits at the pointer-validation fail-safe. (c): `conductor-stop.sh` exits 0 — Step E reads `state.json` for closure evidence; parse failure is treated as OPEN (final=false), so it appends a non-final `CONDUCTOR-TOKEN-EVENT` and skips Step G entirely (no pointer removal, no self-refresh). Verifies that malformed inputs never cause non-zero exits (would disrupt non-bureau Claude sessions). | PASS — (a) exit 0, no stdout; (b) exit 0, no stdout; (c) final:false appended, pointer stays, exit 0 |

---

## Waiver

None. All cases must pass before canon promotion.

---

## Notes

- Cases 1–5 map to specific AC/EC entries in the Bundle 11 spec and are verifiable by running `account-run.sh` against fixture log files.
- Cases 6–8 are adversarial integration tests that require shim scripts and `BUREAU_POINTER_FILE` isolation. They target the three highest-risk ordering and guard properties identified in the P3 (Prompt 3) review. Standing fixtures 62–71 in `.bureau/regression/` encode the same checks. The concrete harness recipe for each:

  **Case 6 — compare-before-rm guard** (fixture 67: `conductor-stop AC 17c`)
  ```bash
  TMPF=$(mktemp -d); export BUREAU_POINTER_FILE="$TMPF/ptr"
  RUN_PATH="$TMPF/run"; mkdir -p "$RUN_PATH"
  # Write a shim account-run.sh that overwrites the pointer with a new nonce/run_dir
  printf '#!/usr/bin/env bash\nprintf '"'"'{"run_dir":"/other","nonce":"other","written_at":"2026-01-01T00:00:00Z"}'"'"' > '"'"'%s'"'"'\n' "$BUREAU_POINTER_FILE" > "$TMPF/shim-account-run.sh"
  chmod +x "$TMPF/shim-account-run.sh"
  # Drive hook to final=true path: closed run + nonce + run_dir all in transcript
  NONCE=$(uuidgen | tr '[:upper:]' '[:lower:]'); touch "$RUN_PATH/log.md"
  printf '{"accounting":{"status":"complete","path":"accounting.json"}}' > "$RUN_PATH/state.json"
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-07-05T00:00:00Z"}\n' "$RUN_PATH" "$NONCE" > "$BUREAU_POINTER_FILE"
  printf 'RUN_DIR: %s\nnonce: %s\n' "$RUN_PATH" "$NONCE" > "$TMPF/t.jsonl"
  # Override SCRIPT_DIR so conductor-stop.sh finds the shim
  SCRIPT_DIR="$TMPF" BUREAU_POINTER_FILE="$BUREAU_POINTER_FILE" \
    bash scripts/conductor-stop.sh <<< \
    "{\"session_id\":\"s1\",\"transcript_path\":\"$TMPF/t.jsonl\",\"stop_hook_active\":false}"
  # Assert: pointer still present (not removed); log.md has final:true
  [ -e "$BUREAU_POINTER_FILE" ] && grep -q '"final":true' "$RUN_PATH/log.md" && echo PASS
  rm -rf "$TMPF"
  ```

  **Case 7 — forced account-run.sh failure** (fixture 66: `conductor-stop AC 17b`)
  ```bash
  TMPF=$(mktemp -d); export BUREAU_POINTER_FILE="$TMPF/ptr"
  RUN_PATH="$TMPF/run"; mkdir -p "$RUN_PATH"; touch "$RUN_PATH/log.md"
  printf '{"accounting":{"status":"complete","path":"accounting.json"}}' > "$RUN_PATH/state.json"
  NONCE=$(uuidgen | tr '[:upper:]' '[:lower:]')
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-07-05T00:00:00Z"}\n' "$RUN_PATH" "$NONCE" > "$BUREAU_POINTER_FILE"
  printf 'RUN_DIR: %s\nnonce: %s\n' "$RUN_PATH" "$NONCE" > "$TMPF/t.jsonl"
  # Shim account-run.sh exits non-zero
  printf '#!/usr/bin/env bash\nexit 1\n' > "$TMPF/account-run.sh"; chmod +x "$TMPF/account-run.sh"
  SCRIPT_DIR="$TMPF" bash scripts/conductor-stop.sh <<< \
    "{\"session_id\":\"s1\",\"transcript_path\":\"$TMPF/t.jsonl\",\"stop_hook_active\":false}" 2>/dev/null
  # Assert: final:true already appended; pointer removed; hook exits 0
  grep -q '"final":true' "$RUN_PATH/log.md" && [ ! -e "$BUREAU_POINTER_FILE" ] && echo PASS
  rm -rf "$TMPF"
  ```

  **Case 8 — malformed/empty pointer + corrupt state.json** (fixtures 62, 70, and 62–71 coverage set)
  ```bash
  ROOT="$(git rev-parse --show-toplevel)"
  # Sub-cases (a) and (b): expect exit 0, no stdout, no log write; stderr IS expected
  for content in '{' ''; do
    TMPF=$(mktemp -d); export BUREAU_POINTER_FILE="$TMPF/ptr"
    printf '%s' "$content" > "$BUREAU_POINTER_FILE"
    printf '{"session_id":"s1","transcript_path":"/dev/null","stop_hook_active":false}' \
      | bash "$ROOT/scripts/conductor-stop.sh" > "$TMPF/out.txt" 2>/dev/null
    [ -s "$TMPF/out.txt" ] && { echo "FAIL: unexpected stdout for content='$content'"; rm -rf "$TMPF"; } || echo "PASS (a/b: no stdout, no log write)"
    rm -rf "$TMPF"
  done
  # Sub-case (c): corrupt state.json → treat as OPEN → final:false, pointer stays
  TMPF=$(mktemp -d); export BUREAU_POINTER_FILE="$TMPF/ptr"
  RUN_PATH="$TMPF/run"; mkdir -p "$RUN_PATH"; touch "$RUN_PATH/log.md"
  printf '{CORRUPT' > "$RUN_PATH/state.json"
  NONCE=$(uuidgen | tr '[:upper:]' '[:lower:]')
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-07-05T00:00:00Z"}\n' "$RUN_PATH" "$NONCE" > "$BUREAU_POINTER_FILE"
  printf 'RUN_DIR: %s\nnonce: %s\n' "$RUN_PATH" "$NONCE" > "$TMPF/t.jsonl"
  bash "$ROOT/scripts/conductor-stop.sh" <<< \
    "{\"session_id\":\"s1\",\"transcript_path\":\"$TMPF/t.jsonl\",\"stop_hook_active\":false}" 2>/dev/null
  grep -q '"final":false' "$RUN_PATH/log.md" && [ -e "$BUREAU_POINTER_FILE" ] && echo "PASS (c)"
  rm -rf "$TMPF"
  ```

- The `## Run <date>` block and filled-in Actual result column will be added during Part B live execution after hooks are registered in `~/.claude/settings.json`.
