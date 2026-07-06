name: delta-baseline legacy — pointer with no baseline key → exit 0, 6-key line, no baseline key (AC 3, FR 6, FR 7)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/ptr"
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"pending"}}' > "$RUN_PATH/state.json"
  NONCE="nonce-fixture-c-legacy"
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-01-01T00:00:00Z"}\n' "$RUN_PATH" "$NONCE" > "$BUREAU_POINTER_FILE"
  printf '%s\n' "RUN_DIR: $RUN_PATH" "NONCE: $NONCE" > "$TMPF/t.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"msg-C","usage":{"input_tokens":30000000,"cache_creation_input_tokens":12000000,"cache_read_input_tokens":10000000,"output_tokens":400000},"content":[{"type":"text"}]}}' >> "$TMPF/t.jsonl"
  echo '{"session_id":"sess-C","transcript_path":"'"$TMPF/t.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  event=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  [ -n "$event" ] || { rm -rf "$TMPF"; exit 1; }
  payload="${event#CONDUCTOR-TOKEN-EVENT: }"
  echo "$payload" | jq -e 'has("baseline") | not' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  echo "$payload" | jq -e 'has("_note") | not' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  echo "$payload" | jq -e '.tokens.processed == 52000000' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo PASS
expected: exit 0; stdout "PASS"; CONDUCTOR-TOKEN-EVENT has no "baseline" key, no "_note" key, and tokens.processed==52000000 (raw session cumulative: 30M+12M+10M). Mutation guard: add "baseline" key emission to legacy branch → has("baseline")==true → assertion 2 fails.
phase: 03 · feature (execute build tail)
owner: prompts.md § Prompt 3 — Fixture C, delta-baseline legacy (AC 3, FR 6, FR 7)
