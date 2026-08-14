name: account-run `_notes` breadcrumb persistence — a scalar (non-object) `tokens` event surfaces a `_notes` array in accounting.json, and a clean run adds no `_notes` key
retired: 07 · execute-plan — FR4 REPLACE retired this live-rail token-rollup assertion; post-hoc aggregation is the sole per-leg source
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  # --- Case 1: a run WITH a scalar-`tokens` SPAWN-TOKEN-EVENT ------------------
  # account-tokens.sh counts the non-object event and emits a `_notes` array in its
  # stdout fragment. Before this fix, account-run.sh step (a) merged only
  # {tokens, conductor_tokens, wall_clock, checkpoints} and dropped `$tok._notes`,
  # so the final accounting.json had no persisted trace that a malformed event was
  # zeroed (only a transient stderr DEBUG line — pre-eval-hardening Challenger W1).
  # After the fix the `_notes` breadcrumb is carried into accounting.json.
  RP="$TMPF/scalar"
  mkdir -p "$RP"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"architect-1","agent_id":"agent-aaa","at":"2026-07-05T00:01:00Z","turns":5,"tokens":{"input":200,"cache_creation":300,"cache_read":500,"processed":1000,"output":50}}' \
    'SPAWN-EVENT: {"role":"challenger","agent":"The Challenger","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"challenger-1","status":"started","at":"2026-07-05T00:01:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"challenger","agent":"The Challenger","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"challenger-1","status":"complete","at":"2026-07-05T00:01:30Z","started_at":"2026-07-05T00:01:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"challenger-1","agent_id":"agent-bbb","at":"2026-07-05T00:01:30Z","turns":3,"tokens":96666}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-001","at":"2026-07-05T00:10:00Z","turns":42,"tokens":{"input":40,"cache_creation":60,"cache_read":100,"processed":200,"output":10},"final":true}' \
    > "$RP/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["architect","challenger"],"phase_status":"complete","critic_loops":{"architect":1,"challenger":1}}' > "$RP/state.json"
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  # The breadcrumb is now persisted: schema 2, a top-level `_notes` array of length >= 1
  # whose text names the non-object/scalar event. (Numbers still correct per fixture 129.)
  jq -e '
    .schema_version == 2 and
    (._notes | type) == "array" and
    (._notes | length) >= 1 and
    (._notes | join(" ") | test("non-object|scalar")) and
    .tokens.processed_total.value == 1200
  ' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  # --- Case 2: a CLEAN run (all object-form) adds NO `_notes` key --------------
  # The propagation is conditional (`($tok._notes // []) | length > 0`), so a run with
  # no malformed events stays byte-for-byte unchanged — no null/empty `_notes` key.
  CP="$TMPF/clean"
  mkdir -p "$CP"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"architect-1","agent_id":"agent-aaa","at":"2026-07-05T00:01:00Z","turns":5,"tokens":{"input":200,"cache_creation":300,"cache_read":500,"processed":1000,"output":50}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-001","at":"2026-07-05T00:10:00Z","turns":42,"tokens":{"input":40,"cache_creation":60,"cache_read":100,"processed":200,"output":10},"final":true}' \
    > "$CP/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["architect"],"phase_status":"complete","critic_loops":{"architect":0}}' > "$CP/state.json"
  bash "$ROOT/scripts/account-run.sh" "$CP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.schema_version == 2 and (has("_notes") | not)' "$CP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: remove the `+ (if (($tok._notes // []) | length) > 0 then {_notes: ...} ...)`
  # clause from account-run.sh step (a) and Case 1's `._notes` assertion fails (the
  # breadcrumb is dropped again). Case 2 guards the reverse: adding an unconditional
  # `_notes` key would fail the `has("_notes") | not` check on a clean run.
expected: exit 0; stdout "PASS"; Case 1 accounting.json carries a top-level _notes array naming the non-object/scalar event at schema 2; Case 2 (clean run) carries no _notes key — the propagation is conditional and byte-for-byte safe on valid input
phase: 04 · feature
owner: accounting breadcrumb persistence / account-run.sh _notes propagation
