name: subagent-stop EC 7 — attempt_id absent from spawn prompt → exit 0, SPAWN-TOKEN-EVENT with attempt_id null and _note
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  # Real Claude Code schema: {"type":"user","message":{"role":"user","content":"<string>"}}
  # Transcript: first message has RUN_DIR but NO "Attempt ID:" line
  jq -cn --arg run_path "$RUN_PATH" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $run_path + "\nInstructions without attempt id")}}' \
    > "$TMPF/t.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"msg-X","usage":{"input_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":3},"content":[{"type":"text"}]}}' \
    >> "$TMPF/t.jsonl"
  echo '{"agent_transcript_path":"'"$TMPF/t.jsonl"'","agent_id":"agent-ec7-test"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  # Must have one SPAWN-TOKEN-EVENT line
  event=$(grep "^SPAWN-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  [ -n "$event" ] || { rm -rf "$TMPF"; exit 1; }
  payload="${event#SPAWN-TOKEN-EVENT: }"
  # attempt_id must be null
  echo "$payload" | jq -e '.attempt_id == null' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  # _note must be present
  echo "$payload" | jq -e 'has("_note")' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; log.md contains one SPAWN-TOKEN-EVENT where attempt_id is JSON null and _note key is present
phase: 02 · feature
owner: Prompt 2 / subagent-stop.sh EC 7 (regenerated with real nested user-line schema — Part A blocker fix)
