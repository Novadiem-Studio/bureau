name: conductor-stop AC 7b — no pointer file → exit 0, no writes
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/bureau-active-run"
  # Ensure no pointer file exists
  printf '%s\n' "some content" > "$TMPF/t.jsonl"
  echo '{"session_id":"sess-no-ptr","transcript_path":"'"$TMPF/t.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  # No pointer must have been created
  [ ! -e "$BUREAU_POINTER_FILE" ] || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; hook exits 0 and creates no files (no pointer → step B exits immediately)
phase: 03 · feature
owner: Prompt 3 / conductor-stop.sh AC 7b
