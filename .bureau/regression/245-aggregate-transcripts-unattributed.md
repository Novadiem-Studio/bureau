name: aggregate-transcripts emits an identity-passing S3 failure exactly once as unattributed
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); RUN_PATH="$TMPF/run"; TARGET="$TMPF/target"; PROJECTS="$TMPF/projects"; SID="delegate-unattr"
  M=$(printf '%s' "$TARGET" | sed 's#[/.]#-#g'); SESSION="$PROJECTS/$M/$SID"; mkdir -p "$RUN_PATH" "$SESSION/subagents"
  printf '{"runtime":"claude"}\n' > "$RUN_PATH/model-routing.json"; jq -cn --arg target "$TARGET" '{target_repo:$target}' > "$RUN_PATH/state.json"
  jq -cn --arg sid "$SID" '{delegate_session_id:$sid,run_started_at:"2026-08-13T00:00:01Z"}' > "$RUN_PATH/delegate-state.json"
  printf 'SPAWN-EVENT: {"role":"mage","attempt_id":"mage-1","status":"started"}\n' > "$RUN_PATH/log.md"
  jq -cn --arg run "$RUN_PATH" '{run_dir:$run,nonce:"nonce-u",written_at:"2026-08-13T00:00:00Z"}' > "$TMPF/pointer"
  printf '%s\n' '{"type":"assistant","message":{"id":"d","usage":{"input_tokens":1},"content":[]}}' > "$SESSION.jsonl"
  jq -cn --arg run "$RUN_PATH" '{type:"user",message:{content:("RUN_DIR: "+$run+"\nAttempt ID: scout-9\nRun nonce: nonce-u\n")}}' > "$SESSION/subagents/agent-scout.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"u","usage":{"input_tokens":8},"content":[]}}' >> "$SESSION/subagents/agent-scout.jsonl"
  jq -cn --arg run "$TMPF/sibling" '{type:"user",message:{content:("RUN_DIR: "+$run+"\nAttempt ID: scout-9\nRun nonce: nonce-u\n")}}' > "$SESSION/subagents/agent-sibling.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"s","usage":{"input_tokens":90},"content":[]}}' >> "$SESSION/subagents/agent-sibling.jsonl"
  out=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" BUREAU_POINTER_FILE="$TMPF/pointer" "$ROOT/scripts/aggregate-transcripts.sh" "$RUN_PATH" 2>/dev/null); rc=$?
  printf '%s' "$out" | jq -e '[.specialists[]|select(.attempt_id==null)] == [{attempt_id:null,role:null,agent_id:"scout",tokens:{input:8,cache_creation:0,cache_read:0,processed:8,output:0},turns:0,confidence:"inferred",_note:"run-scoped transcript has no matching SPAWN-EVENT; summed as unattributed"}] and ([.specialists[]|select(.agent_id=="sibling")]|length)==0' >/dev/null
  ok=$?; rm -rf "$TMPF"; [ "$rc" -eq 0 ] && [ "$ok" -eq 0 ] || exit 1; echo "PASS"
  # Mutation note: folding S3 into identity drops scout; removing S2 admits sibling. Either mutation fails.
expected: exit 0; stdout "PASS"; one null-attempt inferred record sums processed=8 and sibling remains excluded
phase: 01 · execute-plan
owner: Prompt 01 / aggregate-transcripts.sh unattributed seam
