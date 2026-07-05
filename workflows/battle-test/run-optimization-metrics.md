# Battle-test matrix — run-optimization-metrics (Bundle 11)

**Canon surfaces touched:** `agents/orchestrator.md`, `docs/run-accounting.md`, `scripts/README.md`
**Promotion to canon:** yes (declared by The Challenger on this run)
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
| **ADVERSARIAL: Malformed/empty pointer JSON + corrupt state.json fail-safe (P3 review)** | Three sub-cases: (a) `$BUREAU_POINTER_FILE` exists but contains invalid JSON (e.g. `{`); (b) pointer file is empty (zero bytes); (c) pointer is valid JSON but `state.json` in the named `RUN_DIR` is invalid JSON (corrupt). | (a) and (b): `conductor-stop.sh` exits 0 silently — Step B's parse fails, hook exits at the pointer-validation fail-safe. No writes to `log.md`. (c): `conductor-stop.sh` exits 0 — Step E reads `state.json` for closure evidence; parse failure is treated as OPEN (final=false), so it appends a non-final `CONDUCTOR-TOKEN-EVENT` and skips Step G entirely (no pointer removal, no self-refresh). Verifies that malformed inputs never cause non-zero exits (would disrupt non-bureau Claude sessions). | pending — Part B |

---

## Waiver

None. All cases must pass before canon promotion.

---

## Notes

- Cases 1–5 map to specific AC/EC entries in the Bundle 11 spec and are verifiable by running `account-run.sh` against fixture log files.
- Cases 6–8 are adversarial integration tests that require shim scripts and `BUREAU_POINTER_FILE` isolation. They target the three highest-risk ordering and guard properties identified in the P3 (Prompt 3) review.
- The `## Run <date>` block and filled-in Actual result column will be added during Part B live execution after hooks are registered in `~/.claude/settings.json`.
