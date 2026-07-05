name: conductor-stop AC 17c — pointer pre-loaded with different nonce (newer run enrolled) → pointer not removed, hook exits 0
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/bureau-active-run"
  RUN_PATH_A="$TMPF/run-A"
  mkdir -p "$RUN_PATH_A"
  touch "$RUN_PATH_A/log.md"
  echo '{"accounting":{"status":"complete","path":"accounting.json"}}' > "$RUN_PATH_A/state.json"
  NONCE_A="nonce-run-A-111"
  NONCE_B="nonce-run-B-222"
  # Transcript for run A: contains nonce-A and run-A path
  printf '%s\n' "RUN_DIR: $RUN_PATH_A" "Nonce: $NONCE_A" > "$TMPF/t.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":20,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1},"content":[{"type":"text"}]}}' \
    >> "$TMPF/t.jsonl"
  # Pointer is pre-loaded with a DIFFERENT nonce (run B has already enrolled).
  # The hook reads nonce-B from the pointer; nonce-B is not in the transcript;
  # the ownership check fails at Step C → hook exits 0, pointer untouched.
  # This is the single-shot, race-free form of AC 17c (as per carried item:
  # "Fixture 10 (AC 17c): author single-shot with pre-loaded wrong-nonce pointer").
  echo '{"run_dir":"'"$TMPF/run-B"'","nonce":"'"$NONCE_B"'","written_at":"2026-07-05T00:00:01Z"}' \
    > "$BUREAU_POINTER_FILE"
  echo '{"session_id":"sess-run-A","transcript_path":"'"$TMPF/t.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  # Pointer must still be present (not removed by this run-A fire)
  [ -e "$BUREAU_POINTER_FILE" ] || { rm -rf "$TMPF"; exit 1; }
  # Pointer must still name run B with nonce B (unchanged)
  current_nonce=$(jq -r '.nonce' "$BUREAU_POINTER_FILE" 2>/dev/null)
  [ "$current_nonce" = "$NONCE_B" ] || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; pointer file present and unchanged (still names run B / nonce B); run A's hook fire did not disturb run B's pointer
phase: 03 · feature
owner: Prompt 3 / conductor-stop.sh AC 17c
