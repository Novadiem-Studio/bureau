name: aggregate-transcripts AC1 wash-killed proof is honest on a hermetic shared session
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT
  TARGET="$TMPF/target"
  RUN_PATH="$TARGET/.bureau/runs/shared-run"
  SIBLING="$TARGET/.bureau/runs/sibling-run"
  PROJECTS="$TMPF/projects"
  SID="delegate-shared-run"
  M=$(printf '%s' "$TARGET" | sed 's#[/.]#-#g')
  SESSION="$PROJECTS/$M/$SID"
  mkdir -p "$RUN_PATH" "$SESSION/subagents"
  printf '{"runtime":"claude"}\n' > "$RUN_PATH/model-routing.json"
  jq -cn --arg target "$TARGET" '{target_repo:$target}' > "$RUN_PATH/state.json"
  jq -cn --arg sid "$SID" \
    '{delegate_session_id:$sid,conductor_agent_id:"cond-shared",conductor_agent_ids:["cond-shared"]}' \
    > "$RUN_PATH/delegate-state.json"
  : > "$RUN_PATH/log.md"
  jq -cn --arg own "$RUN_PATH" --arg sibling "$SIBLING" \
    '{type:"user",message:{content:("RUN_DIR: "+$own+"\nRUN_DIR: "+$sibling+"\n")}}' \
    > "$SESSION.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"shared-turn","usage":{"input_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' \
    >> "$SESSION.jsonl"
  jq -cn --arg own "$RUN_PATH" \
    '{type:"user",message:{content:("BUREAU_ROLE: conductor\nRUN_DIR: "+$own+"\n")}}' \
    > "$SESSION/subagents/agent-cond-shared.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"conductor-turn","usage":{"input_tokens":9,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' \
    >> "$SESSION/subagents/agent-cond-shared.jsonl"
  out=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" BUREAU_POINTER_FILE="$TMPF/no-pointer" "$ROOT/scripts/aggregate-transcripts.sh" "$RUN_PATH" 2>/dev/null) || exit 1
  printf '%s' "$out" | jq -e '
    .delegate.tokens.processed == 5 and
    .delegate.confidence == "partial" and
    .delegate.confidence != "exact" and
    (.delegate._note | type == "string" and length > 0) and
    (.delegate._note | contains("shared-session per-run window unavailable")) and
    .conductor.tokens.processed > 0
  ' >/dev/null || exit 1
  echo "PASS"
  # Mutation: delete the shared-session partial relabel and the confidence
  # assertion fails while the independent Conductor proof remains non-zero.
expected: exit 0; stdout "PASS"; synthetic shared-session Delegate is partial with a note and Conductor is non-zero
phase: 03 · execute-plan
owner: Prompt 03 / AC1 hermetic exact-zero-wash-killed proof
