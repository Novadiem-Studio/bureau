name: aggregate-transcripts degrades readable empty and all-zero usage legs with mandatory notes
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); RUN_PATH="$TMPF/run"; TARGET="$TMPF/target"; PROJECTS="$TMPF/projects"; SID="delegate-zero"
  M=$(printf '%s' "$TARGET" | sed 's#[/.]#-#g'); SESSION="$PROJECTS/$M/$SID"; mkdir -p "$RUN_PATH" "$SESSION/subagents"
  printf '{"runtime":"claude"}\n' > "$RUN_PATH/model-routing.json"; jq -cn --arg target "$TARGET" '{target_repo:$target}' > "$RUN_PATH/state.json"
  jq -cn --arg sid "$SID" '{delegate_session_id:$sid,conductor_agent_id:"cond-zero",conductor_agent_ids:["cond-zero"],run_started_at:"2026-08-13T00:00:01Z"}' > "$RUN_PATH/delegate-state.json"
  printf 'SPAWN-EVENT: {"role":"analyst","attempt_id":"analyst-zero","status":"started"}\n' > "$RUN_PATH/log.md"
  jq -cn --arg run "$RUN_PATH" '{run_dir:$run,nonce:"nonce-zero",written_at:"2026-08-13T00:00:00Z"}' > "$TMPF/pointer"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:02Z","type":"assistant","message":{"id":"delegate-empty","usage":{},"content":[]}}' > "$SESSION.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"conductor-zero","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' > "$SESSION/subagents/agent-cond-zero.jsonl"
  jq -cn --arg run "$RUN_PATH" '{type:"user",message:{role:"user",content:("RUN_DIR: "+$run+"\nAttempt ID: analyst-zero\nRun nonce: nonce-zero\n")}}' > "$SESSION/subagents/agent-specialist-zero.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"specialist-empty","usage":{},"content":[]}}' >> "$SESSION/subagents/agent-specialist-zero.jsonl"
  out=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" BUREAU_POINTER_FILE="$TMPF/pointer" "$ROOT/scripts/aggregate-transcripts.sh" "$RUN_PATH"); rc=$?
  printf '%s' "$out" | jq -e '
    [.delegate,.conductor,.specialists[0]]
    | all(.tokens == {input:0,cache_creation:0,cache_read:0,processed:0,output:0}
          and .confidence == "unavailable"
          and (._note | contains("empty or all-zero")))
  ' >/dev/null
  ok=$?; rm -rf "$TMPF"; [ "$rc" -eq 0 ] && [ "$ok" -eq 0 ] || exit 1; echo "PASS"
  # Mutation note: deleting json_usage's nonzero_usage guard exact-washes all three readable zero legs and fails this fixture.
expected: exit 0; stdout "PASS"; readable usage:{} and explicit all-zero usage produce unavailable zero legs with mandatory notes, never note-free exact legs
phase: 01 · execute-plan blocker repair BD-SF-001
owner: Prompt 01 repair / aggregate-transcripts.sh FR7 gap-zero honesty seam
