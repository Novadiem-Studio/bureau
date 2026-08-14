name: aggregate-transcripts dedups repeated message.id usage before summing
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RUN_PATH="$TMPF/run"; TARGET="$TMPF/target"; PROJECTS="$TMPF/projects"; SID="delegate-dedup"
  M=$(printf '%s' "$TARGET" | sed 's#[/.]#-#g'); SESSION="$PROJECTS/$M/$SID"
  mkdir -p "$RUN_PATH" "$SESSION/subagents"
  printf '{"runtime":"claude"}\n' > "$RUN_PATH/model-routing.json"
  jq -cn --arg target "$TARGET" '{target_repo:$target}' > "$RUN_PATH/state.json"
  jq -cn --arg sid "$SID" '{delegate_session_id:$sid,run_started_at:"2026-08-13T00:00:01Z"}' > "$RUN_PATH/delegate-state.json"
  printf 'SPAWN-EVENT: {"role":"analyst","attempt_id":"analyst-1","status":"started"}\n' > "$RUN_PATH/log.md"
  jq -cn --arg run "$RUN_PATH" --arg nonce "nonce-dedup" '{run_dir:$run,nonce:$nonce,written_at:"2026-08-13T00:00:00Z"}' > "$TMPF/pointer"
  printf '%s\n' '{"type":"assistant","message":{"id":"delegate","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[{"type":"text"}]}}' > "$SESSION.jsonl"
  jq -cn --arg run "$RUN_PATH" '{type:"user",message:{role:"user",content:("RUN_DIR: "+$run+"\nAttempt ID: analyst-1\nRun nonce: nonce-dedup\n")}}' > "$SESSION/subagents/agent-a1.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"repeat","usage":{"input_tokens":2,"cache_creation_input_tokens":3,"cache_read_input_tokens":5,"output_tokens":7},"content":[{"type":"tool_use"}]}}' \
    '{"type":"assistant","message":{"id":"repeat","usage":{"input_tokens":2,"cache_creation_input_tokens":3,"cache_read_input_tokens":5,"output_tokens":7},"content":[{"type":"text"}]}}' \
    >> "$SESSION/subagents/agent-a1.jsonl"
  out=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" BUREAU_POINTER_FILE="$TMPF/pointer" "$ROOT/scripts/aggregate-transcripts.sh" "$RUN_PATH")
  rc=$?
  printf '%s' "$out" | jq -e '.specialists == [{attempt_id:"analyst-1",role:"analyst",agent_id:"a1",tokens:{input:2,cache_creation:3,cache_read:5,processed:10,output:7},turns:1,confidence:"exact"}]' >/dev/null
  ok=$?
  rm -rf "$TMPF"
  [ "$rc" -eq 0 ] && [ "$ok" -eq 0 ] || exit 1
  echo "PASS"
  # Mutation note: replacing sum_transcript_usage with a naive per-line sum makes processed=20 and fails.
expected: exit 0; stdout "PASS"; repeated message.id usage is counted once (processed=10, turns=1)
phase: 01 · execute-plan
owner: Prompt 01 / aggregate-transcripts.sh dedup seam
