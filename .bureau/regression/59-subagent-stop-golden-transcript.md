name: subagent-stop golden-transcript — deduped token sums are correct (not naive per-line sum)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RUN_PATH="$TMPF/golden-run-XX"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"

  # #27 specialist ownership gate: write a per-run pointer (munged RUN_DIR key)
  # carrying a nonce, and put that nonce in the spawn prompt so the gate opens
  # (state 1: pointer present + nonce present in transcript → attribute).
  export BUREAU_POINTER_DIR="$TMPF/active-runs"
  mkdir -p "$BUREAU_POINTER_DIR"
  NONCE="golden-nonce-$(date +%s)-abcdef"
  PTR_KEY=$(printf '%s' "$RUN_PATH" | sed 's#[/.]#-#g')
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-07-11T00:00:00Z","project_dir":"%s"}\n' \
    "$RUN_PATH" "$NONCE" "$TMPF" > "$BUREAU_POINTER_DIR/$PTR_KEY"

  # Real Claude Code schema: {"type":"user","message":{"role":"user","content":"<string>"}}
  # Spawn prompt: RUN_DIR + Attempt ID + Run nonce
  jq -cn --arg run_path "$RUN_PATH" --arg nonce "$NONCE" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $run_path + "\nAttempt ID: mage-1\nRun nonce: " + $nonce + "\n")}}' \
    > "$TMPF/golden-transcript.jsonl"

  # msg-A: 3 lines (identical cumulative usage), one tool_use block
  # Expected: counts as 1 group, not 3
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":300,"output_tokens":10},"content":[{"type":"tool_use"}]}}' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":300,"output_tokens":10},"content":[{"type":"text"}]}}' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":300,"output_tokens":10},"content":[{"type":"text"}]}}' \
    >> "$TMPF/golden-transcript.jsonl"

  # msg-B: 1 line, one tool_use block
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-B","usage":{"input_tokens":50,"cache_creation_input_tokens":80,"cache_read_input_tokens":120,"output_tokens":5},"content":[{"type":"tool_use"}]}}' \
    >> "$TMPF/golden-transcript.jsonl"

  # msg-C: 2 lines (identical cumulative usage), no tool_use block
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-C","usage":{"input_tokens":30,"cache_creation_input_tokens":40,"cache_read_input_tokens":60,"output_tokens":3},"content":[{"type":"text"}]}}' \
    '{"type":"assistant","message":{"id":"msg-C","usage":{"input_tokens":30,"cache_creation_input_tokens":40,"cache_read_input_tokens":60,"output_tokens":3},"content":[{"type":"text"}]}}' \
    >> "$TMPF/golden-transcript.jsonl"

  echo '{"agent_transcript_path":"'"$TMPF/golden-transcript.jsonl"'","agent_id":"agent-golden-001"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }

  # Must have exactly one SPAWN-TOKEN-EVENT line
  line_count=$(grep -c "^SPAWN-TOKEN-EVENT:" "$RUN_PATH/log.md" 2>/dev/null || echo 0)
  [ "$line_count" = "1" ] || { rm -rf "$TMPF"; exit 1; }

  event=$(grep "^SPAWN-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  payload="${event#SPAWN-TOKEN-EVENT: }"

  # Verify exact deduped values (hand-derivable):
  #   input = 100+50+30 = 180 (one per group, not naive 6-line sum)
  #   cache_creation = 200+80+40 = 320
  #   cache_read = 300+120+60 = 480
  #   processed = 180+320+480 = 980
  #   output = 10+5+3 = 18
  #   turns = 2 (msg-A and msg-B have tool_use; msg-C does not)
  #   attempt_id = "mage-1"
  echo "$payload" | jq -e '
    .attempt_id == "mage-1" and
    .tokens.input == 180 and
    .tokens.cache_creation == 320 and
    .tokens.cache_read == 480 and
    .tokens.processed == 980 and
    .tokens.output == 18 and
    .turns == 2
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"

  # Mutation note: removing the group_by(.message.id)|map(.[0]) dedup step
  # would produce the naive sum: 3*600 + 1*250 + 2*130 = 2310 processed != 980
  # and this fixture would fail.
expected: exit 0; stdout "PASS"; SPAWN-TOKEN-EVENT has attempt_id="mage-1", tokens.input=180, tokens.cache_creation=320, tokens.cache_read=480, tokens.processed=980, tokens.output=18, turns=2
phase: 02 · feature
owner: Prompt 2 / subagent-stop.sh golden-transcript value correctness (regenerated with real nested user-line schema — Part A blocker fix)
