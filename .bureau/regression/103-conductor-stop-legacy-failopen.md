name: conductor-stop EC 2 — legacy pointer fail-open: pointer has NO project_dir field → Step C.0 skipped → nonce-grep passes → CONDUCTOR-TOKEN-EVENT appended
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/bureau-active-run"
  RUN_PATH="$TMPF/run-open"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"pending","path":null}}' > "$RUN_PATH/state.json"
  NONCE="nonce-legacy-failopen-103"
  # LEGACY pointer: three fields only — run_dir / nonce / written_at. NO project_dir.
  echo '{"run_dir":"'"$RUN_PATH"'","nonce":"'"$NONCE"'","written_at":"2026-07-05T00:00:00Z"}' \
    > "$BUREAU_POINTER_FILE"
  # Transcript parent-dir basename is irrelevant here — project_dir absent means Step C.0 is skipped.
  TX_DIR="$TMPF/-any-dir"
  mkdir -p "$TX_DIR"
  printf '%s\n' "RUN_DIR: $RUN_PATH" "Nonce: $NONCE" > "$TX_DIR/t.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":2},"content":[{"type":"text"}]}}' \
    >> "$TX_DIR/t.jsonl"
  echo '{"session_id":"sess-legacy","transcript_path":"'"$TX_DIR/t.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  # project_dir absent → Step B fail-open (not a required key) → Step C.0 skipped → event appended.
  event=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  [ -n "$event" ] || { rm -rf "$TMPF"; exit 1; }
  payload="${event#CONDUCTOR-TOKEN-EVENT: }"
  echo "$payload" | jq -e '.final == false' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: add project_dir to Step B required-keys guard → legacy pointer rejected → no event appended → fixture fails.
expected: exit 0; stdout "PASS"; one CONDUCTOR-TOKEN-EVENT (final:false) present in log.md (project_dir-less legacy pointer passes via EC 2 fail-open — guards the 16 existing 62-71/92-98 fixtures)
phase: 01 · feature
owner: Prompt 1 / conductor-stop.sh Step B fail-open (EC 2)
