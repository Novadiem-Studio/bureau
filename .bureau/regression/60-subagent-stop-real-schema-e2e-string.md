name: subagent-stop real-schema e2e (string content) — nested user-line correctly parsed → SPAWN-TOKEN-EVENT lands with right attempt_id
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RUN_PATH="$TMPF/run-e2e-string"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  # Real Claude Code schema — user line is nested, content is a plain string.
  # This is the schema the selector bug (.role? == "user") silently missed;
  # the fix (.type? == "user" + .message.content) must recover it.
  jq -cn --arg run_path "$RUN_PATH" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $run_path + "\nAttempt ID: architect-1\n")}}' \
    > "$TMPF/t.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5},"content":[{"type":"text"}]}}' \
    >> "$TMPF/t.jsonl"
  echo '{"agent_transcript_path":"'"$TMPF/t.jsonl"'","agent_id":"agent-e2e-real-schema"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  # SPAWN-TOKEN-EVENT must be present (proves RUN_DIR was extracted — hook did not no-op)
  event=$(grep "^SPAWN-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  [ -n "$event" ] || { rm -rf "$TMPF"; exit 1; }
  payload="${event#SPAWN-TOKEN-EVENT: }"
  # attempt_id must be "architect-1" (proves Attempt ID line was extracted too)
  echo "$payload" | jq -e '.attempt_id == "architect-1"' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: reverting the selector to .role? == "user" causes the hook
  # to find no user line, exit 0 with no write, so event is empty and fixture fails.
expected: exit 0; stdout "PASS"; SPAWN-TOKEN-EVENT appended to log.md with attempt_id="architect-1" — proves real-schema nested user-line (string content) was correctly parsed
phase: 02 · feature
owner: Part A blocker fix / subagent-stop.sh real-schema e2e (string content shape)
