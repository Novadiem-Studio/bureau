name: conductor-stop AC 2 / FR 9b — legitimate cwd match: pointer project_dir=/proj/alpha, transcript under the MATCHING munged dir (-proj-alpha) → Step C.0 falls through → CONDUCTOR-TOKEN-EVENT appended
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/bureau-active-run"
  RUN_PATH="$TMPF/run-open"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"pending","path":null}}' > "$RUN_PATH/state.json"
  NONCE="nonce-legit-match-102"
  # Pointer carries project_dir=/proj/alpha  → munged owner cwd = -proj-alpha
  echo '{"run_dir":"'"$RUN_PATH"'","nonce":"'"$NONCE"'","written_at":"2026-07-05T00:00:00Z","project_dir":"/proj/alpha"}' \
    > "$BUREAU_POINTER_FILE"
  # Transcript lives under the MATCHING munged project-dir: basename(dirname(transcript)) = -proj-alpha
  TX_DIR="$TMPF/-proj-alpha"
  mkdir -p "$TX_DIR"
  printf '%s\n' "RUN_DIR: $RUN_PATH" "Nonce: $NONCE" > "$TX_DIR/t.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":2},"content":[{"type":"text"}]}}' \
    >> "$TX_DIR/t.jsonl"
  echo '{"session_id":"sess-legit","transcript_path":"'"$TX_DIR/t.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  # Munged cwd matches → Step C.0 passes → nonce-grep passes → event MUST be appended.
  event=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  [ -n "$event" ] || { rm -rf "$TMPF"; exit 1; }
  payload="${event#CONDUCTOR-TOKEN-EVENT: }"
  echo "$payload" | jq -e '.final == false' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: invert Step C.0 to exit 0 on match → no event appended → fixture fails.
expected: exit 0; stdout "PASS"; one CONDUCTOR-TOKEN-EVENT (final:false) present in log.md (munged cwd matches → Step C.0 falls through to the nonce-grep)
phase: 01 · feature
owner: Prompt 1 / conductor-stop.sh Step C.0 (FR 2, AC 2)
