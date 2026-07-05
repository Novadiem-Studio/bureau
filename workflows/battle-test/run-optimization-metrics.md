# Battle-test matrix — run-optimization-metrics (Bundle 11)

**Canon surfaces touched:** `agents/orchestrator.md`, `docs/run-accounting.md`, `scripts/README.md`
**Promotion to canon:** yes (declared by The Conductor per docs/conductor-gates.md)
**Status:** AUTHORED — `## Run <date>` block and Actual result column are added during live execution (Part B, when hooks are registered and the matrix cases are run against real scripts).

---

## Case table

| Case name | Input description | Expected outcome | Actual result |
|-----------|-------------------|-----------------|---------------|
| **Happy path — complete run with all events** | A `log.md` containing: all SPAWN-EVENT started/terminal pairs matched (architect-1, challenger-1), a SPAWN-TOKEN-EVENT for each subagent, one CONDUCTOR-TOKEN-EVENT with `final:true`, and two resolved CHECKPOINT-EVENTs. State.json has `phases_complete: ["architect","challenger"]`. | `account-run.sh` exits 0; `accounting.json` has `schema_version == 2`; `tokens.processed_total.confidence == "exact"`; `wall_clock.active_spawn_time_s.confidence == "exact"`; `checkpoints.human_wait_total_s` is populated; `conductor_tokens` block is present and distinct from `specialist_spawns[]`. | pending — Part B |
| **EDGE: Pre-Bundle-11 run — old 7-key format degrades cleanly (EC 9)** | A `log.md` containing only old-format 7-key SPAWN-EVENT lines (no `at`/`started_at`/`rework` fields, no SPAWN-TOKEN-EVENT, no CONDUCTOR-TOKEN-EVENT, no CHECKPOINT-EVENT lines). State.json is a valid pre-Bundle-11 state. | `account-run.sh` exits 0; output is valid JSON; the seven existing fields (`role`, `agent`, `configured_model`, `actual_model`, `attempt`, `attempt_id`, `reported_status`) are populated correctly in `specialist_spawns[]`; new fields are absent or carry confidence `"unavailable"`; no crash or stack trace. `schema_version == 1`. | pending — Part B |
| **EDGE: Double SubagentStop fire — dedup prevents inflation (EC 11 / AC 16)** | A `log.md` containing two SPAWN-TOKEN-EVENT lines that share one `agent_id` (different token counts — the second has higher `processed`), plus one CONDUCTOR-TOKEN-EVENT with `final:true`. Paired SPAWN-EVENT lines are present. | `tokens.processed_total` counts that subagent's tokens once (take-max on `processed`, not sum); `tokens.processed_total.confidence == "exact"`. A build that sums the two records instead of taking max is broken. | pending — Part B |
| **FAILURE MODE: Conductor share pending at close-out — partial, not exact (EC 12 / AC 4 Blocker guard)** | A `log.md` containing a complete set of matched SPAWN-EVENT pairs and a SPAWN-TOKEN-EVENT for each specialist, but NO CONDUCTOR-TOKEN-EVENT line at all. | `tokens.processed_total.confidence == "partial"` with `_note` containing `"conductor-share-pending"`. Must NOT be `"exact"`. A build that labels this `"exact"` is broken — this case is the Blocker guard. | pending — Part B |
| **FAILURE MODE: Zero SPAWN-EVENT with spawn headings — enforcement gate fires (EC 8 / AC 6)** | A `log.md` containing a narrative heading `## [2026-07-05T00:00:00Z] — Spawned The Architect` and no `SPAWN-EVENT:` lines. `state.json` has `phases_complete: ["architect"]` (non-empty). | `account-run.sh` stdout contains `[CLOSE-OUT WARNING]`; `accounting.json` carries `"_close_out_warning"` key. The gate must fire; a build that silently emits clean JSON without the warning is broken. | pending — Part B |
| **ADVERSARIAL: compare-before-rm guard exercised — pointer swapped mid-hook (P3 review)** | A shim `account-run.sh` that, when called by `conductor-stop.sh`'s self-refresh step, overwrites `$BUREAU_POINTER_FILE` with a new JSON whose `run_dir` and `nonce` differ from the values loaded by the hook's Step B. After the shim returns, the hook reaches Step G(3). | `conductor-stop.sh` exits 0; the pointer file is NOT removed (compare-before-rm detects the mismatch: current `run_dir`/`nonce` ≠ the hook's loaded values, so the hook leaves it untouched). The original run's `log.md` still has `final:true` appended. Verifies that the hook re-reads the pointer at Step G(3) rather than caching the value from Step B. | pending — Part B |
| **ADVERSARIAL: Forced account-run.sh failure — append-before-refresh ordering locked (P3 review)** | A shim `account-run.sh` that exits non-zero (simulating a refresh failure). `conductor-stop.sh` is driven to the `final:true` path. | `conductor-stop.sh` exits 0; `CONDUCTOR-TOKEN-EVENT` with `final:true` is already appended to `log.md` BEFORE the `account-run.sh` call is made (Step F before Step G(2)). The self-refresh failure is logged to stderr but does NOT prevent pointer removal (Step G(3) still runs). `accounting.json` is not updated (refresh failed) but the token event record is preserved. Verifies that a refresh failure cannot roll back the append — the ordering is append → refresh → rm, not refresh → append. | pending — Part B |
| **ADVERSARIAL: Malformed/empty pointer JSON + corrupt state.json fail-safe (P3 review)** | Three sub-cases: (a) `$BUREAU_POINTER_FILE` exists but contains invalid JSON (e.g. `{`); (b) pointer file is empty (zero bytes); (c) pointer is valid JSON but `state.json` in the named `RUN_DIR` is invalid JSON (corrupt). | (a) and (b): `conductor-stop.sh` exits 0; no stdout output and no log.md write (a stderr warning IS expected and must not fail the case) — Step B's parse fails, hook exits at the pointer-validation fail-safe. (c): `conductor-stop.sh` exits 0 — Step E reads `state.json` for closure evidence; parse failure is treated as OPEN (final=false), so it appends a non-final `CONDUCTOR-TOKEN-EVENT` and skips Step G entirely (no pointer removal, no self-refresh). Verifies that malformed inputs never cause non-zero exits (would disrupt non-bureau Claude sessions). | pending — Part B |

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
