name: aggregate-transcripts zeroes a run-scoped attempt-id collision instead of double counting
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); RUN_PATH="$TMPF/run"; TARGET="$TMPF/target"; PROJECTS="$TMPF/projects"; SID="delegate-collision"
  M=$(printf '%s' "$TARGET" | sed 's#[/.]#-#g'); SESSION="$PROJECTS/$M/$SID"; mkdir -p "$RUN_PATH" "$SESSION/subagents"
  printf '{"runtime":"claude"}\n' > "$RUN_PATH/model-routing.json"; jq -cn --arg target "$TARGET" '{target_repo:$target}' > "$RUN_PATH/state.json"
  jq -cn --arg sid "$SID" '{delegate_session_id:$sid,run_started_at:"2026-08-13T00:00:01Z"}' > "$RUN_PATH/delegate-state.json"
  printf 'SPAWN-EVENT: {"role":"architect","attempt_id":"architect-1","status":"started"}\n' > "$RUN_PATH/log.md"
  jq -cn --arg run "$RUN_PATH" '{run_dir:$run,nonce:"nonce-c",written_at:"2026-08-13T00:00:00Z"}' > "$TMPF/pointer"
  printf '%s\n' '{"type":"assistant","message":{"id":"d","usage":{"input_tokens":1},"content":[]}}' > "$SESSION.jsonl"
  for id in alpha beta; do
    jq -cn --arg run "$RUN_PATH" '{type:"user",message:{content:("RUN_DIR: "+$run+"\nAttempt ID: architect-1\nRun nonce: nonce-c\n")}}' > "$SESSION/subagents/agent-$id.jsonl"
    printf '%s\n' '{"type":"assistant","message":{"id":"work","usage":{"input_tokens":12},"content":[]}}' >> "$SESSION/subagents/agent-$id.jsonl"
  done
  out=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" BUREAU_POINTER_FILE="$TMPF/pointer" "$ROOT/scripts/aggregate-transcripts.sh" "$RUN_PATH"); rc=$?
  printf '%s' "$out" | jq -e '.specialists == [{attempt_id:"architect-1",role:"architect",agent_id:null,tokens:{input:0,cache_creation:0,cache_read:0,processed:0,output:0},turns:0,confidence:"suspect",_note:"attempt-id collision after run-scoping: alpha,beta — not summed (over-count guard)"}]' >/dev/null
  ok=$?; rm -rf "$TMPF"; [ "$rc" -eq 0 ] && [ "$ok" -eq 0 ] || exit 1; echo "PASS"
  # Mutation note: selecting either claimant or summing both changes the suspect zero contract and fails.
expected: exit 0; stdout "PASS"; one suspect architect record has null agent, zero tokens, and names alpha,beta
phase: 01 · execute-plan
owner: Prompt 01 / aggregate-transcripts.sh collision seam
