name: delta-baseline EC 3 residual pin — take-max picks raw-cumulative over delta when first-fire baseline write failed (FR 12)
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  echo '{"accounting":{"status":"complete"}}' > "$RUN_PATH/state.json"
  printf 'CONDUCTOR-TOKEN-EVENT: %s\n' '{"session_id":"sess-E","at":"2026-01-01T00:00:00Z","turns":5,"tokens":{"input":30000000,"cache_creation":12000000,"cache_read":10000000,"processed":52000000,"output":400000},"final":false}' > "$RUN_PATH/log.md"
  printf 'CONDUCTOR-TOKEN-EVENT: %s\n' '{"session_id":"sess-E","at":"2026-01-01T01:00:00Z","turns":10,"tokens":{"input":10000000,"cache_creation":4000000,"cache_read":4000000,"processed":18000000,"output":100000},"baseline":{"session_id":"sess-E","input":20000000,"cache_creation":8000000,"cache_read":6000000,"processed":34000000,"output":300000,"turns":121},"final":true}' >> "$RUN_PATH/log.md"
  result=$(bash "$ROOT/scripts/account-tokens.sh" "$RUN_PATH" 2>/dev/null)
  [ $? -eq 0 ] || { rm -rf "$TMPF"; exit 1; }
  echo "$result" | jq -e '.conductor_tokens.tokens.processed == 52000000' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo PASS
expected: exit 0; stdout "PASS"; account-tokens.sh take-max picks 52000000 (line-1 raw-cumulative) over 18000000 (line-2 delta) for the same session_id. Pins EC-3 degrade: first-fire failure over-attributes identically to pre-Bundle-16 behaviour. Mutation (throwaway copy per FR 5): change max_by(.tokens.processed//0) to min_by(.tokens.processed//0) in a copy of account-tokens.sh → result.conductor_tokens.tokens.processed==18000000 → fixture fails.
phase: 03 · feature (execute build tail)
owner: prompts.md § Prompt 3 — Fixture E, EC 3 residual pin (FR 12)
