name: aggregate-transcripts treats a nonce written after run start as rotated legacy scope
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); RUN_PATH="$TMPF/run"; TARGET="$TMPF/target"; PROJECTS="$TMPF/projects"; SID="delegate-rotated"
  M=$(printf '%s' "$TARGET" | sed 's#[/.]#-#g'); SESSION="$PROJECTS/$M/$SID"; mkdir -p "$RUN_PATH" "$SESSION/subagents"
  printf '{"runtime":"claude"}\n' > "$RUN_PATH/model-routing.json"; jq -cn --arg target "$TARGET" '{target_repo:$target}' > "$RUN_PATH/state.json"
  jq -cn --arg sid "$SID" '{delegate_session_id:$sid,run_started_at:"2026-08-13T00:00:01Z"}' > "$RUN_PATH/delegate-state.json"
  printf 'SPAWN-EVENT: {"role":"cleric","attempt_id":"cleric-1","status":"started"}\n' > "$RUN_PATH/log.md"
  jq -cn --arg run "$RUN_PATH" '{run_dir:$run,nonce:"rotated-new",written_at:"2026-08-13T00:00:02Z"}' > "$TMPF/pointer"
  printf '%s\n' '{"type":"assistant","message":{"id":"d","usage":{"input_tokens":1},"content":[]}}' > "$SESSION.jsonl"
  jq -cn --arg run "$RUN_PATH" '{type:"user",message:{content:("RUN_DIR: "+$run+"\nAttempt ID: cleric-1\nRun nonce: original-old\n")}}' > "$SESSION/subagents/agent-cleric.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"c","usage":{"input_tokens":11},"content":[]}}' >> "$SESSION/subagents/agent-cleric.jsonl"
  out=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" BUREAU_POINTER_FILE="$TMPF/pointer" "$ROOT/scripts/aggregate-transcripts.sh" "$RUN_PATH"); rc=$?
  printf '%s' "$out" | jq -e '.specialists[0].agent_id=="cleric" and .specialists[0].tokens.processed==11 and .specialists[0].confidence=="exact" and (._scope_note|contains("nonce postdates run start — rotated"))' >/dev/null
  ok=$?; rm -rf "$TMPF"; [ "$rc" -eq 0 ] && [ "$ok" -eq 0 ] || exit 1; echo "PASS"
  # Mutation note: removing the written_at <= run_started_at check applies rotated-new strictly and makes the leg unavailable.
expected: exit 0; stdout "PASS"; original-nonce specialist remains exact processed=11 under named rotated legacy scope
phase: 01 · execute-plan
owner: Prompt 01 / aggregate-transcripts.sh rotated-nonce seam
