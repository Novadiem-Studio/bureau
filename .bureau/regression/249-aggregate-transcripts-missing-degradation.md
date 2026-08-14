name: aggregate-transcripts labels missing Conductor and specialist transcripts unavailable with notes
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); RUN_PATH="$TMPF/run"; TARGET="$TMPF/target"; PROJECTS="$TMPF/projects"; SID="delegate-missing"
  M=$(printf '%s' "$TARGET" | sed 's#[/.]#-#g'); SESSION="$PROJECTS/$M/$SID"; mkdir -p "$RUN_PATH" "$SESSION/subagents"
  printf '{"runtime":"claude"}\n' > "$RUN_PATH/model-routing.json"; jq -cn --arg target "$TARGET" '{target_repo:$target}' > "$RUN_PATH/state.json"
  jq -cn --arg sid "$SID" '{delegate_session_id:$sid,conductor_agent_id:"gone",conductor_agent_ids:["gone"],run_started_at:"2026-08-13T00:00:01Z"}' > "$RUN_PATH/delegate-state.json"
  printf 'SPAWN-EVENT: {"role":"challenger","attempt_id":"challenger-1","status":"started"}\n' > "$RUN_PATH/log.md"
  jq -cn --arg run "$RUN_PATH" '{run_dir:$run,nonce:"nonce-missing",written_at:"2026-08-13T00:00:00Z"}' > "$TMPF/pointer"
  printf '%s\n' '{"type":"assistant","message":{"id":"d","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' > "$SESSION.jsonl"
  out=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" BUREAU_POINTER_FILE="$TMPF/pointer" "$ROOT/scripts/aggregate-transcripts.sh" "$RUN_PATH"); rc=$?
  printf '%s' "$out" | jq -e '.conductor.confidence=="unavailable" and .conductor.tokens.processed==0 and (.conductor._note|contains("agent-gone.jsonl")) and .specialists[0].confidence=="unavailable" and .specialists[0].tokens.processed==0 and (.specialists[0]._note|contains("no run-scoped transcript"))' >/dev/null
  ok=$?; rm -rf "$TMPF"; [ "$rc" -eq 0 ] && [ "$ok" -eq 0 ] || exit 1; echo "PASS"
  # Mutation note: exact-washing either missing zero or omitting either note fails the contract assertion.
expected: exit 0; stdout "PASS"; missing legs are unavailable zeroes with path/recovery notes and never exact
phase: 01 · execute-plan
owner: Prompt 01 / aggregate-transcripts.sh missing-transcript degradation seam
