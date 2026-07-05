name: conductor-stop loop guard — stop_hook_active:true → exit 0 immediately, no writes
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/bureau-active-run"
  # Feed stop_hook_active:true — loop guard must fire before any other check
  stdout_out=$(echo '{"stop_hook_active":true,"session_id":"sess-loop","transcript_path":"'"$TMPF/t.jsonl"'"}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null)
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  [ -z "$stdout_out" ] || { rm -rf "$TMPF"; exit 1; }
  # No pointer must have been created (hook exits before reading pointer)
  [ ! -e "$BUREAU_POINTER_FILE" ] || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; hook exits 0 immediately with no stdout and no writes — loop guard (Step A) fires before any other check
phase: 03 · feature
owner: Prompt 3 / conductor-stop.sh loop guard
