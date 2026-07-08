name: conductor-stop AC 1 / FR 9a — foreign-watcher exclusion: pointer project_dir=/proj/alpha, transcript under a BETA munged dir (mismatch) → Step C.0 exits 0, no CONDUCTOR-TOKEN-EVENT appended
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/bureau-active-run"
  RUN_PATH="$TMPF/run-open"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"pending","path":null}}' > "$RUN_PATH/state.json"
  NONCE="nonce-foreign-watcher-101"
  # Pointer carries project_dir=/proj/alpha  → munged owner cwd = -proj-alpha
  echo '{"run_dir":"'"$RUN_PATH"'","nonce":"'"$NONCE"'","written_at":"2026-07-05T00:00:00Z","project_dir":"/proj/alpha"}' \
    > "$BUREAU_POINTER_FILE"
  # Transcript lives under a BETA munged project-dir path: basename(dirname(transcript)) = -proj-beta
  TX_DIR="$TMPF/-proj-beta"
  mkdir -p "$TX_DIR"
  # Transcript DOES carry nonce + RUN_DIR (looks like the owner) so the W2 stderr diagnostic fires.
  printf '%s\n' "RUN_DIR: $RUN_PATH" "Nonce: $NONCE" > "$TX_DIR/t.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":2},"content":[{"type":"text"}]}}' \
    >> "$TX_DIR/t.jsonl"
  # NOTE: the munged project_dir (-proj-alpha) != the transcript parent dir (-proj-beta) → mismatch.
  # We do NOT redirect stderr here (the W2 diagnostic legitimately fires — do NOT assert empty stderr).
  echo '{"session_id":"sess-foreign","transcript_path":"'"$TX_DIR/t.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  # Foreign watcher was excluded at Step C.0 → NO event may be appended.
  if grep -q "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md"; then rm -rf "$TMPF"; exit 1; fi
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: delete Step C.0 mismatch exit 0 → nonce-grep passes (seeded) → event appended → fixture fails.
expected: exit 0; stdout "PASS"; NO CONDUCTOR-TOKEN-EVENT line in log.md (foreign transcript excluded by Step C.0 munged-cwd mismatch). Do NOT assert empty stderr — the W2 diagnostic fires here (nonce+RUN_DIR present, munged cwd mismatch).
phase: 01 · feature
owner: Prompt 1 / conductor-stop.sh Step C.0 (FR 2, FR 6, AC 1)
