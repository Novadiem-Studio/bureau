name: conductor-stop — state.json absent → fail-safe treats run as OPEN → final:false, pointer stays
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/bureau-active-run"
  RUN_PATH="$TMPF/run-no-state"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  # Deliberately do NOT create state.json — fail-safe must treat as OPEN
  NONCE="nonce-no-state-def456"
  echo '{"run_dir":"'"$RUN_PATH"'","nonce":"'"$NONCE"'","written_at":"2026-07-05T00:00:00Z"}' \
    > "$BUREAU_POINTER_FILE"
  printf '%s\n' "RUN_DIR: $RUN_PATH" "Nonce: $NONCE" > "$TMPF/t.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":15,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1},"content":[{"type":"text"}]}}' \
    >> "$TMPF/t.jsonl"
  echo '{"session_id":"sess-no-state","transcript_path":"'"$TMPF/t.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  # Must have CONDUCTOR-TOKEN-EVENT with "final":false (fail-safe: missing state → OPEN)
  event=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  [ -n "$event" ] || { rm -rf "$TMPF"; exit 1; }
  payload="${event#CONDUCTOR-TOKEN-EVENT: }"
  echo "$payload" | jq -e '.final == false' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  # Pointer must still be present (OPEN run → pointer stays)
  [ -e "$BUREAU_POINTER_FILE" ] || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; CONDUCTOR-TOKEN-EVENT with "final":false in log.md; pointer still present (missing state.json → fail-safe → treated as OPEN)
phase: 03 · feature
owner: Prompt 3 / conductor-stop.sh state.json absent fail-safe
