name: subagent-stop conductor single-leg — BUREAU_ROLE marker → CONDUCTOR-TOKEN-EVENT (not SPAWN), baseline recorded (AC-3)
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  # Closed run so final:true is exercised too.
  echo '{"accounting":{"status":"complete"}}' > "$RUN_PATH/state.json"

  # First user message: real Claude Code schema, carrying RUN_DIR + topology +
  # the BUREAU_ROLE: conductor marker the Delegate spawn prompt emits.
  jq -cn --arg rp "$RUN_PATH" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $rp + "\ntopology: integrated\nBUREAU_ROLE: conductor\n")}}' \
    > "$TMPF/t.jsonl"

  # Two deduped assistant messages (one group each, both tool_use):
  #   input = 100+50 = 150, cache_creation = 200+80 = 280,
  #   cache_read = 300+120 = 420, processed = 150+280+420 = 850, output = 15, turns = 2
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":300,"output_tokens":10},"content":[{"type":"tool_use"}]}}' \
    '{"type":"assistant","message":{"id":"msg-B","usage":{"input_tokens":50,"cache_creation_input_tokens":80,"cache_read_input_tokens":120,"output_tokens":5},"content":[{"type":"tool_use"}]}}' \
    >> "$TMPF/t.jsonl"

  echo '{"agent_transcript_path":"'"$TMPF/t.jsonl"'","agent_id":"agent-cond-138"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }

  # Exactly one CONDUCTOR-TOKEN-EVENT, and ZERO SPAWN-TOKEN-EVENT (not misfiled).
  # (grep -c always prints a number, exit 1 on zero matches — no `|| echo 0`,
  # which would append a second line and break the `= "0"` compare.)
  cond_n=$(grep -c "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" 2>/dev/null); cond_n=${cond_n:-0}
  spawn_n=$(grep -c "^SPAWN-TOKEN-EVENT:" "$RUN_PATH/log.md" 2>/dev/null); spawn_n=${spawn_n:-0}
  [ "$cond_n" = "1" ] || { rm -rf "$TMPF"; exit 1; }
  [ "$spawn_n" = "0" ] || { rm -rf "$TMPF"; exit 1; }

  event=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  payload="${event#CONDUCTOR-TOKEN-EVENT: }"
  # session_id == agent_id; first leg → delta processed == 0 (baseline == cumulative);
  # final:true from state.json accounting.status=="complete".
  echo "$payload" | jq -e '
    .session_id == "agent-cond-138" and
    .tokens.processed == 0 and
    .final == true and
    (.baseline.processed == 850)
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # Baseline dotfile written, keyed by agent_id, with the cumulative.
  bl="$RUN_PATH/.conductor-subagent-baseline.json"
  [ -r "$bl" ] || { rm -rf "$TMPF"; exit 1; }
  jq -e '
    (."agent-cond-138".input == 150) and
    (."agent-cond-138".cache_read == 420) and
    (."agent-cond-138".processed == 850) and
    (."agent-cond-138".turns == 2)
  ' "$bl" > /dev/null || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: remove the Step-4.5 classify branch (force is_conductor=false)
  # → the line comes out as SPAWN-TOKEN-EVENT → cond_n=0/spawn_n=1 → fixture fails.
expected: exit 0; stdout "PASS"; exactly one CONDUCTOR-TOKEN-EVENT (zero SPAWN-TOKEN-EVENT) with session_id="agent-cond-138", tokens.processed=0 (first-leg delta), final:true, baseline.processed=850; RUN_DIR/.conductor-subagent-baseline.json written keyed by agent_id
phase: 02 · feature
owner: subagent-stop.sh conductor single-leg capture (v2-conductor-capture)
