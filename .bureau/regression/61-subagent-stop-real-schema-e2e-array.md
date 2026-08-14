name: subagent-stop real-schema e2e (array-of-blocks content) — normaliser correctly joins blocks → SPAWN-TOKEN-EVENT lands with right attempt_id
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RUN_PATH="$TMPF/run-e2e-array"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  # #27 ownership gate: pointer (munged RUN_DIR key) with nonce + nonce in prompt.
  export BUREAU_POINTER_DIR="$TMPF/active-runs"
  mkdir -p "$BUREAU_POINTER_DIR"
  NONCE="e2e-array-nonce-$(date +%s)-445566"
  PTR_KEY=$(printf '%s' "$RUN_PATH" | sed 's#[/.]#-#g')
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-07-11T00:00:00Z","project_dir":"%s"}\n' \
    "$RUN_PATH" "$NONCE" "$TMPF" > "$BUREAU_POINTER_DIR/$PTR_KEY"
  # Real Claude Code schema — user line is nested, content is an array of blocks.
  # The normaliser (type=="array" → map(.text? // "")|join("")) must recover the text.
  # The nonce lives in the text block so the joined text carries it for the gate grep.
  jq -cn --arg run_path "$RUN_PATH" --arg nonce "$NONCE" \
    '{"type":"user","message":{"role":"user","content":[{"type":"text","text":("RUN_DIR: " + $run_path + "\nAttempt ID: systemsmith-1\nRun nonce: " + $nonce + "\n")}]}}' \
    > "$TMPF/t.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":80,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":4},"content":[{"type":"text"}]}}' \
    >> "$TMPF/t.jsonl"
  echo '{"agent_transcript_path":"'"$TMPF/t.jsonl"'","agent_id":"agent-e2e-array-schema"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  event=$(grep "^SPAWN-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  [ -n "$event" ] || { rm -rf "$TMPF"; exit 1; }
  payload="${event#SPAWN-TOKEN-EVENT: }"
  # attempt_id must be "systemsmith-1" (proves array-of-blocks normaliser worked)
  echo "$payload" | jq -e '.attempt_id == "systemsmith-1"' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: reverting the selector to .role? == "user" causes the hook
  # to find no user line, exit 0 with no write, and this fixture fails.
expected: exit 0; stdout "PASS"; SPAWN-TOKEN-EVENT appended with attempt_id="systemsmith-1" — proves array-of-blocks content shape correctly normalised
phase: 02 · feature
owner: Part A blocker fix / subagent-stop.sh real-schema e2e (array-of-blocks content shape)
