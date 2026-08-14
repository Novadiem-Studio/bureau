name: aggregate-transcripts conductor marker ordering distinguishes identity from a later mention
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); RUN_PATH="$TMPF/run"; TARGET="$TMPF/target"; PROJECTS="$TMPF/projects"; SID="delegate-order"
  M=$(printf '%s' "$TARGET" | sed 's#[/.]#-#g'); SESSION="$PROJECTS/$M/$SID"; mkdir -p "$RUN_PATH" "$SESSION/subagents"
  printf '{"runtime":"claude"}\n' > "$RUN_PATH/model-routing.json"; jq -cn --arg target "$TARGET" '{target_repo:$target}' > "$RUN_PATH/state.json"
  jq -cn --arg sid "$SID" '{delegate_session_id:$sid,conductor_agent_id:"recorded",conductor_agent_ids:["recorded"],run_started_at:"2026-08-13T00:00:01Z"}' > "$RUN_PATH/delegate-state.json"
  printf 'SPAWN-EVENT: {"role":"spellwright","attempt_id":"spellwright-1","status":"started"}\n' > "$RUN_PATH/log.md"
  jq -cn --arg run "$RUN_PATH" '{run_dir:$run,nonce:"nonce-order",written_at:"2026-08-13T00:00:00Z"}' > "$TMPF/pointer"
  printf '%s\n' '{"type":"assistant","message":{"id":"d","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' > "$SESSION.jsonl"
  jq -cn --arg run "$RUN_PATH" '{type:"user",message:{content:("BUREAU_ROLE: conductor\nRUN_DIR: "+$run+"\nRun nonce: nonce-order\n")}}' > "$SESSION/subagents/agent-recorded.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"c1","usage":{"input_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' >> "$SESSION/subagents/agent-recorded.jsonl"
  jq -cn --arg run "$RUN_PATH" '{type:"user",message:{content:("BUREAU_ROLE: conductor\nRUN_DIR: "+$run+"\nAttempt ID: incidental\n")}}' > "$SESSION/subagents/agent-discovered.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"c2","usage":{"input_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' >> "$SESSION/subagents/agent-discovered.jsonl"
  jq -cn --arg run "$RUN_PATH" '{type:"user",message:{content:("RUN_DIR: "+$run+"\nAttempt ID: spellwright-1\nRun nonce: nonce-order\nLater quotation: BUREAU_ROLE: conductor\n")}}' > "$SESSION/subagents/agent-specialist.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"s","usage":{"input_tokens":7,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' >> "$SESSION/subagents/agent-specialist.jsonl"
  out=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" BUREAU_POINTER_FILE="$TMPF/pointer" "$ROOT/scripts/aggregate-transcripts.sh" "$RUN_PATH"); rc=$?
  printf '%s' "$out" | jq -e '.conductor.tokens.processed==8 and .conductor.legs==2 and .conductor.confidence=="partial" and (.conductor._note|contains("discovered")) and .specialists[0].agent_id=="specialist" and .specialists[0].tokens.processed==7 and .specialists[0].confidence=="exact"' >/dev/null
  ok=$?; rm -rf "$TMPF"; [ "$rc" -eq 0 ] && [ "$ok" -eq 0 ] || exit 1; echo "PASS"
  # Mutation note: ignoring byte order misclassifies specialist; ignoring discovered markers loses five Conductor tokens.
expected: exit 0; stdout "PASS"; discovered Conductor is summed partial while later-marker specialist stays exact
phase: 01 · execute-plan
owner: Prompt 01 / aggregate-transcripts.sh conductor-marker order seam
