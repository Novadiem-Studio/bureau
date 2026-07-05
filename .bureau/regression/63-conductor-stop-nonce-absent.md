name: conductor-stop AC 7c — nonce absent from transcript content → exit 0, no log writes (stale-pointer / eval-session EC 14)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/bureau-active-run"
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  # Write pointer with a distinct nonce
  echo '{"run_dir":"'"$RUN_PATH"'","nonce":"SECRET-NONCE-XYZ","written_at":"2026-07-05T00:00:00Z"}' \
    > "$BUREAU_POINTER_FILE"
  # Transcript contains run_dir but NOT the nonce (eval/inspection session)
  printf '%s\n' "RUN_DIR: $RUN_PATH" "Context without nonce." > "$TMPF/t.jsonl"
  echo '{"session_id":"sess-no-nonce","transcript_path":"'"$TMPF/t.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  # log.md must be empty (nothing appended)
  [ ! -s "$RUN_PATH/log.md" ] || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; nothing appended to log.md (nonce absent from transcript — stale pointer or eval-session leak closed)
phase: 03 · feature
owner: Prompt 3 / conductor-stop.sh AC 7c EC 14
