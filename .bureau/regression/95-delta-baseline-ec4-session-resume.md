name: delta-baseline EC 4 — pointer baseline tagged with old session_id → hook re-records for new session (AC 8)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/ptr"
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"pending"}}' > "$RUN_PATH/state.json"
  NONCE="nonce-fixture-d-ec4"
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-01-01T00:00:00Z","baseline":{"session_id":"old-session","input":100000000,"cache_creation":50000000,"cache_read":50000000,"output":1000000,"turns":100,"processed":200000000}}\n' "$RUN_PATH" "$NONCE" > "$BUREAU_POINTER_FILE"
  printf '%s\n' "RUN_DIR: $RUN_PATH" "NONCE: $NONCE" > "$TMPF/t.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"msg-D","usage":{"input_tokens":3000000,"cache_creation_input_tokens":1000000,"cache_read_input_tokens":1000000,"output_tokens":50000},"content":[{"type":"text"}]}}' >> "$TMPF/t.jsonl"
  echo '{"session_id":"new-session","transcript_path":"'"$TMPF/t.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  event=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  [ -n "$event" ] || { rm -rf "$TMPF"; exit 1; }
  payload="${event#CONDUCTOR-TOKEN-EVENT: }"
  echo "$payload" | jq -e '.tokens.processed >= 0 and .tokens.processed < 5000000' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  jq -e '.baseline.session_id == "new-session"' "$BUREAU_POINTER_FILE" >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo PASS
expected: exit 0; stdout "PASS"; tokens.processed>=0 and <5000000 (re-recorded baseline so delta is near-zero); pointer.baseline.session_id=="new-session" after hook (re-record confirmed). Warning: assertion 2 passes on both correct and mutant paths — assertion 3 (pointer check) is the load-bearing guard. Mutation guard: remove session-id check → re-record never fires → pointer.baseline.session_id stays "old-session" → assertion 3 fails.
phase: 03 · feature (execute build tail)
owner: prompts.md § Prompt 3 — Fixture D, delta-baseline EC 4 session resume (AC 8)
