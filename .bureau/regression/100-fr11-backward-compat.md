name: FR 11 backward-compat — legacy log.md (no baseline) produces same values; key order in emitted line is unchanged (AC 2, AC 6, FR 6)
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/ptr"
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"pending"}}' > "$RUN_PATH/state.json"
  NONCE="nonce-fixture-h-legacy"
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-01-01T00:00:00Z"}\n' "$RUN_PATH" "$NONCE" > "$BUREAU_POINTER_FILE"
  printf '%s\n' "RUN_DIR: $RUN_PATH" "NONCE: $NONCE" > "$TMPF/t.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"msg-H-legacy","usage":{"input_tokens":20000000,"cache_creation_input_tokens":8000000,"cache_read_input_tokens":6000000,"output_tokens":300000},"content":[{"type":"text"}]}}' >> "$TMPF/t.jsonl"
  echo '{"session_id":"sess-H","transcript_path":"'"$TMPF/t.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  event=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  [ -n "$event" ] || { rm -rf "$TMPF"; exit 1; }
  payload="${event#CONDUCTOR-TOKEN-EVENT: }"
  # Part A: key-order guard — sole FR 11 / AC 6 guard on insertion order.
  # Do NOT use jq 'keys' (sorts alphabetically, proves nothing about order).
  printf '%s' "$payload" | jq -e 'keys_unsorted == ["session_id","at","turns","tokens","final"]' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  # Part B: account-tokens.sh backward compat — append a final:true line, run consumer.
  printf 'CONDUCTOR-TOKEN-EVENT: %s\n' '{"session_id":"sess-H","at":"2026-01-01T01:00:00Z","turns":121,"tokens":{"input":20000000,"cache_creation":8000000,"cache_read":6000000,"processed":34000000,"output":300000},"final":true}' >> "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"complete"}}' > "$RUN_PATH/state.json"
  result=$(bash "$ROOT/scripts/account-tokens.sh" "$RUN_PATH" 2>/dev/null)
  [ $? -eq 0 ] || { rm -rf "$TMPF"; exit 1; }
  printf '%s' "$result" | jq -e '.conductor_tokens.confidence == "exact"' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  printf '%s' "$result" | jq -e '.conductor_tokens.tokens.processed == 34000000' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo PASS
expected: exit 0; stdout "PASS"; Part A: legacy event keys_unsorted==["session_id","at","turns","tokens","final"] (insertion order preserved; jq 'keys' not used — it sorts and proves nothing). Part B: account-tokens.sh on legacy log.md gives confidence=="exact" and processed==34000000. Mutation: add "baseline":{} to legacy branch jq in a throwaway copy of conductor-stop.sh → keys_unsorted gains "baseline" → array != expected → Part A assertion fails.
phase: 07 · feature (execute build tail)
owner: prompts.md § Prompt 7 — Fixture H, FR 11 backward-compat + key-order guard (AC 2, AC 6, FR 11)
