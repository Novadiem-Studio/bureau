name: conductor-stop AC 7d / EC 14 — RUN_DIR in transcript but nonce absent → exit 0, nothing written
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/bureau-active-run"
  RUN_PATH="$TMPF/run-ec14"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"run_dir":"'"$RUN_PATH"'","nonce":"NONCE-NOT-IN-TRANSCRIPT","written_at":"2026-07-05T00:00:00Z"}' \
    > "$BUREAU_POINTER_FILE"
  # Transcript explicitly contains run_dir string but NOT the nonce
  printf '%s\n' "Session path includes: $RUN_PATH" "Nonce is absent from this transcript." \
    > "$TMPF/t.jsonl"
  # Verify fixture setup: run_dir in transcript, nonce not in transcript
  grep -q "$RUN_PATH" "$TMPF/t.jsonl" || { echo "fixture setup error: run_dir missing" >&2; rm -rf "$TMPF"; exit 1; }
  grep -q "NONCE-NOT-IN-TRANSCRIPT" "$TMPF/t.jsonl" && { echo "fixture setup error: nonce IS present" >&2; rm -rf "$TMPF"; exit 1; }
  echo '{"session_id":"sess-ec14","transcript_path":"'"$TMPF/t.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  [ ! -s "$RUN_PATH/log.md" ] || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; nothing appended (nonce grep fails; run_dir-only match does not trigger write — EC 14 is closed)
phase: 03 · feature
owner: Prompt 3 / conductor-stop.sh AC 7d EC 14
