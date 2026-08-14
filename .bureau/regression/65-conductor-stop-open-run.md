name: conductor-stop AC 17a — open run (status:pending) → final:false appended, pointer stays
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/bureau-active-run"
  RUN_PATH="$TMPF/run-open"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  # state.json with accounting.status: "pending" (open run)
  echo '{"accounting":{"status":"pending","path":null}}' > "$RUN_PATH/state.json"
  NONCE="nonce-open-run-abc123"
  echo '{"run_dir":"'"$RUN_PATH"'","nonce":"'"$NONCE"'","written_at":"2026-07-05T00:00:00Z"}' \
    > "$BUREAU_POINTER_FILE"
  # Transcript: plain text containing both nonce and run_dir (ownership passes),
  # plus one assistant usage line for sum_transcript_usage
  printf '%s\n' "RUN_DIR: $RUN_PATH" "Nonce: $NONCE" > "$TMPF/t.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":2},"content":[{"type":"text"}]}}' \
    >> "$TMPF/t.jsonl"
  echo '{"session_id":"sess-open","transcript_path":"'"$TMPF/t.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  # Must have one CONDUCTOR-TOKEN-EVENT with "final":false
  event=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  [ -n "$event" ] || { rm -rf "$TMPF"; exit 1; }
  payload="${event#CONDUCTOR-TOKEN-EVENT: }"
  echo "$payload" | jq -e '.final == false' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  # Pointer must still be present
  [ -e "$BUREAU_POINTER_FILE" ] || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; one CONDUCTOR-TOKEN-EVENT with "final":false in log.md; pointer file still present after hook exits
phase: 03 · feature
owner: Prompt 3 / conductor-stop.sh AC 17a
