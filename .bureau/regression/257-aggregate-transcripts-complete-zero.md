name: aggregate-transcripts distinguishes authoritative complete zero from incomplete gap zero
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); RUN_PATH="$TMPF/run"; TARGET="$TMPF/target"; PROJECTS="$TMPF/projects"; SID="delegate-complete-zero"
  M=$(printf '%s' "$TARGET" | sed 's#[/.]#-#g'); SESSION="$PROJECTS/$M/$SID"; mkdir -p "$RUN_PATH" "$SESSION/subagents"
  printf '{"runtime":"claude"}\n' > "$RUN_PATH/model-routing.json"; jq -cn --arg target "$TARGET" '{target_repo:$target}' > "$RUN_PATH/state.json"
  jq -cn --arg sid "$SID" '{delegate_session_id:$sid,conductor_agent_id:"cond-gap",conductor_agent_ids:["cond-gap"],run_started_at:"2026-08-13T00:00:01Z"}' > "$RUN_PATH/delegate-state.json"
  printf 'SPAWN-EVENT: {"role":"analyst","attempt_id":"analyst-gap","status":"started"}\n' > "$RUN_PATH/log.md"
  jq -cn --arg run "$RUN_PATH" '{run_dir:$run,nonce:"nonce-zero",written_at:"2026-08-13T00:00:00Z"}' > "$TMPF/pointer"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:02Z","type":"assistant","message":{"id":"delegate-complete","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' > "$SESSION.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"conductor-incomplete","usage":{"input_tokens":0},"content":[]}}' > "$SESSION/subagents/agent-cond-gap.jsonl"
  jq -cn --arg run "$RUN_PATH" '{type:"user",message:{content:("RUN_DIR: "+$run+"\nAttempt ID: analyst-gap\nRun nonce: nonce-zero\n")}}' > "$SESSION/subagents/agent-specialist-gap.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"specialist-empty","usage":{},"content":[]}}' >> "$SESSION/subagents/agent-specialist-gap.jsonl"
  out=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" BUREAU_POINTER_FILE="$TMPF/pointer" "$ROOT/scripts/aggregate-transcripts.sh" "$RUN_PATH"); rc=$?
  printf '%s' "$out" | jq -e '
    .delegate.tokens == {input:0,cache_creation:0,cache_read:0,processed:0,output:0}
    and .delegate.turns == 0 and .delegate.confidence == "exact" and (.delegate | has("_note") | not)
    and ([.conductor,.specialists[0]] | all(.confidence == "unavailable"
      and (._note | contains("empty or incomplete all-zero"))))
  ' >/dev/null
  ok=$?; rm -rf "$TMPF"; [ "$rc" -eq 0 ] && [ "$ok" -eq 0 ] || exit 1; echo "PASS"
  # Mutation note: rejecting all zeros breaks the exact Delegate assertion; accepting incomplete zeros exact-washes both gap legs.
expected: exit 0; stdout "PASS"; structurally complete numeric all-zero usage is exact while incomplete and empty zero usage remain unavailable with notes
phase: 01 · execute-plan blocker repair BD-SF-001
owner: Prompt 03 repair / aggregate-transcripts.sh FR7 genuine-complete-zero seam
