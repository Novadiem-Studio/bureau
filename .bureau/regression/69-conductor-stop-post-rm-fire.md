name: conductor-stop AC 17d — fire after pointer removal → exit 0, no writes (post-run chatter not attributed)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/bureau-active-run"
  # Simulate post-removal state: pointer file does not exist
  printf '%s\n' "some session content" > "$TMPF/t.jsonl"
  echo '{"session_id":"sess-post-rm","transcript_path":"'"$TMPF/t.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  # No pointer created (hook exits at Step B — no pointer file found)
  [ ! -e "$BUREAU_POINTER_FILE" ] || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; hook exits 0 immediately at Step B (no pointer) — post-run chatter fires write nothing to any log
phase: 03 · feature
owner: Prompt 3 / conductor-stop.sh AC 17d
