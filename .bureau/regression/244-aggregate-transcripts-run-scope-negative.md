name: aggregate-transcripts excludes a sibling run despite colliding Attempt ID (B1)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); RUN_PATH="$TMPF/run"; SIBLING="$TMPF/sibling"; TARGET="$TMPF/target"; PROJECTS="$TMPF/projects"; SID="delegate-b1"
  M=$(printf '%s' "$TARGET" | sed 's#[/.]#-#g'); SESSION="$PROJECTS/$M/$SID"; mkdir -p "$RUN_PATH" "$SESSION/subagents"
  printf '{"runtime":"claude"}\n' > "$RUN_PATH/model-routing.json"; jq -cn --arg target "$TARGET" '{target_repo:$target}' > "$RUN_PATH/state.json"
  jq -cn --arg sid "$SID" '{delegate_session_id:$sid}' > "$RUN_PATH/delegate-state.json"
  printf 'SPAWN-EVENT: {"role":"analyst","attempt_id":"analyst-1","status":"started"}\n' > "$RUN_PATH/log.md"
  printf '%s\n' '{"type":"assistant","message":{"id":"d","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' > "$SESSION.jsonl"
  jq -cn --arg run "$RUN_PATH" '{type:"user",message:{content:("RUN_DIR: "+$run+"\nAttempt ID: analyst-1\nRun nonce: own-old\n")}}' > "$SESSION/subagents/agent-own.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"own","usage":{"input_tokens":6,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' >> "$SESSION/subagents/agent-own.jsonl"
  jq -cn --arg run "$SIBLING" '{type:"user",message:{content:("RUN_DIR: "+$run+"\nAttempt ID: analyst-1\nRun nonce: sibling\n")}}' > "$SESSION/subagents/agent-sibling.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"sibling","usage":{"input_tokens":99,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' >> "$SESSION/subagents/agent-sibling.jsonl"
  stderr="$TMPF/stderr"; out=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" HOME="$TMPF/home" "$ROOT/scripts/aggregate-transcripts.sh" "$RUN_PATH" 2>"$stderr"); rc=$?
  printf '%s' "$out" | jq -e '.specialists|length==1 and .[0].agent_id=="own" and .[0].tokens.processed==6 and .[0].confidence=="exact"' >/dev/null && \
    printf '%s' "$out" | jq -e '._scope_note|contains("no write-once nonce")' >/dev/null && grep -q 'excluded 1 sibling/foreign' "$stderr"
  ok=$?; rm -rf "$TMPF"; [ "$rc" -eq 0 ] && [ "$ok" -eq 0 ] || exit 1; echo "PASS"
  # Mutation note: deleting the first-RUN_DIR membership filter creates a collision or sums 99 and fails.
expected: exit 0; stdout "PASS"; own analyst is exact processed=6, sibling is excluded, and legacy basis is named
phase: 01 · execute-plan
owner: Prompt 01 / aggregate-transcripts.sh run-scope B1 seam
