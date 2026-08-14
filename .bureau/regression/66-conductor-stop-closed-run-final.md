name: conductor-stop AC 17b — closed run (status:complete) → final:true appended, pointer removed (even if account-run.sh fails)
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/bureau-active-run"
  RUN_PATH="$TMPF/run-closed"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  # state.json with accounting.status: "complete" (closed run)
  echo '{"accounting":{"status":"complete","path":"accounting.json"}}' > "$RUN_PATH/state.json"
  NONCE="nonce-closed-xyz789"
  echo '{"run_dir":"'"$RUN_PATH"'","nonce":"'"$NONCE"'","written_at":"2026-07-05T00:00:00Z"}' \
    > "$BUREAU_POINTER_FILE"
  # Transcript: contains nonce and run_dir; one assistant usage line
  printf '%s\n' "RUN_DIR: $RUN_PATH" "Nonce: $NONCE" > "$TMPF/t.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":3},"content":[{"type":"text"}]}}' \
    >> "$TMPF/t.jsonl"
  echo '{"session_id":"sess-closed","transcript_path":"'"$TMPF/t.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  # final:true CONDUCTOR-TOKEN-EVENT must be in log.md
  # (must be present even if account-run.sh self-refresh fails)
  event=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  [ -n "$event" ] || { rm -rf "$TMPF"; exit 1; }
  payload="${event#CONDUCTOR-TOKEN-EVENT: }"
  echo "$payload" | jq -e '.final == true' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  # Pointer must be removed after hook exits
  [ ! -e "$BUREAU_POINTER_FILE" ] || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Ordering note: the final:true append (Step F) runs before the account-run.sh
  # call (Step G(2)) and before the rm (Step G(3)) — order is load-bearing per spec.
expected: exit 0; stdout "PASS"; CONDUCTOR-TOKEN-EVENT with "final":true in log.md; pointer file removed; final:true line present even if account-run.sh fails
phase: 03 · feature
owner: Prompt 3 / conductor-stop.sh AC 17b
