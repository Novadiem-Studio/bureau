name: aggregate-transcripts resolves Conductor and specialist as flat sibling subagents (OQ1)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); RUN_PATH="$TMPF/run"; TARGET="$TMPF/target"; PROJECTS="$TMPF/projects"; SID="delegate-oq1"
  M=$(printf '%s' "$TARGET" | sed 's#[/.]#-#g'); SESSION="$PROJECTS/$M/$SID"; mkdir -p "$RUN_PATH" "$SESSION/subagents"
  printf '{"runtime":"claude"}\n' > "$RUN_PATH/model-routing.json"
  jq -cn --arg target "$TARGET" '{target_repo:$target}' > "$RUN_PATH/state.json"
  jq -cn --arg sid "$SID" '{delegate_session_id:$sid,conductor_agent_id:"cond-1",conductor_agent_ids:["cond-1"],run_started_at:"2026-08-13T00:00:01Z"}' > "$RUN_PATH/delegate-state.json"
  printf 'SPAWN-EVENT: {"role":"mage","attempt_id":"mage-1","status":"started"}\n' > "$RUN_PATH/log.md"
  jq -cn --arg run "$RUN_PATH" '{run_dir:$run,nonce:"nonce-oq1",written_at:"2026-08-13T00:00:00Z"}' > "$TMPF/pointer"
  printf '%s\n' '{"type":"assistant","message":{"id":"d","usage":{"input_tokens":1},"content":[]}}' > "$SESSION.jsonl"
  jq -cn --arg run "$RUN_PATH" '{type:"user",message:{content:("BUREAU_ROLE: conductor\nRUN_DIR: "+$run+"\nRun nonce: nonce-oq1\n")}}' > "$SESSION/subagents/agent-cond-1.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"c","usage":{"input_tokens":4,"cache_creation_input_tokens":5,"cache_read_input_tokens":6},"content":[{"type":"tool_use"}]}}' >> "$SESSION/subagents/agent-cond-1.jsonl"
  jq -cn --arg run "$RUN_PATH" '{type:"user",message:{content:("RUN_DIR: "+$run+"\nAttempt ID: mage-1\nRun nonce: nonce-oq1\n")}}' > "$SESSION/subagents/agent-mage-1.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"m","usage":{"input_tokens":2,"cache_creation_input_tokens":3,"cache_read_input_tokens":4},"content":[{"type":"tool_use"}]}}' >> "$SESSION/subagents/agent-mage-1.jsonl"
  out=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" BUREAU_POINTER_FILE="$TMPF/pointer" "$ROOT/scripts/aggregate-transcripts.sh" "$RUN_PATH")
  rc=$?
  printf '%s' "$out" | jq -e '.conductor.tokens.processed == 15 and .conductor.legs == 1 and .conductor.confidence == "exact" and (.specialists|length)==1 and .specialists[0].agent_id=="mage-1" and .specialists[0].tokens.processed==9' >/dev/null
  ok=$?; rm -rf "$TMPF"; [ "$rc" -eq 0 ] && [ "$ok" -eq 0 ] || exit 1; echo "PASS"
  # Mutation note: nesting specialists beneath the Conductor or failing to exclude cond-1 makes this fail.
expected: exit 0; stdout "PASS"; flat Conductor processed=15 and the distinct flat specialist processed=9
phase: 01 · execute-plan
owner: Prompt 01 / aggregate-transcripts.sh OQ1 nesting seam
