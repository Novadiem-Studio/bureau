name: delta-baseline hook-level — pointer with baseline object → hook emits delta processed (AC 1 hook half)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/ptr"
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"pending"}}' > "$RUN_PATH/state.json"
  NONCE="nonce-fixture-a-delta-hook"
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-01-01T00:00:00Z","baseline":{"session_id":"sess-A","input":20000000,"cache_creation":8000000,"cache_read":6000000,"output":300000,"turns":121,"processed":34000000}}\n' "$RUN_PATH" "$NONCE" > "$BUREAU_POINTER_FILE"
  printf '%s\n' "RUN_DIR: $RUN_PATH" "NONCE: $NONCE" > "$TMPF/t.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":30000000,"cache_creation_input_tokens":12000000,"cache_read_input_tokens":10000000,"output_tokens":400000},"content":[{"type":"text"}]}}' >> "$TMPF/t.jsonl"
  echo '{"session_id":"sess-A","transcript_path":"'"$TMPF/t.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  event=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  [ -n "$event" ] || { rm -rf "$TMPF"; exit 1; }
  payload="${event#CONDUCTOR-TOKEN-EVENT: }"
  echo "$payload" | jq -e '.tokens.processed == 18000000' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  echo "$payload" | jq -e '.baseline.processed == 34000000' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo PASS
expected: exit 0; stdout "PASS"; CONDUCTOR-TOKEN-EVENT in log.md with tokens.processed==18000000 (52M session cumulative minus 34M baseline) and top-level baseline.processed==34000000. Mutation guard: change pointer baseline.processed 34000000→0 → assertion (.baseline.processed==34000000) fails.
phase: 03 · feature (execute build tail)
owner: prompts.md § Prompt 3 — Fixture A, delta-baseline hook-level (AC 1 hook half)
