name: audit-r2 F1 (i) real Conductor — delegate-state.json present, agent_id == conductor_agent_id, BUREAU_ROLE marker present → CONDUCTOR-TOKEN-EVENT emitted (happy path unchanged)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"complete"}}' > "$RUN_PATH/state.json"

  # delegate-state.json carries the conductor credential (as agents/delegate.md step 2
  # writes it). This subagent's own agent_id EQUALS conductor_agent_id → the real Conductor.
  echo '{"topology":"integrated","conductor_agent_id":"agent-cond-166","active_checkpoint":"01","revise_counts":{},"revision_cap":2}' > "$RUN_PATH/delegate-state.json"

  # First user message: real Claude Code schema, RUN_DIR + the public BUREAU_ROLE: conductor marker.
  jq -cn --arg rp "$RUN_PATH" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $rp + "\ntopology: integrated\nBUREAU_ROLE: conductor\n")}}' \
    > "$TMPF/t.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":300,"output_tokens":10},"content":[{"type":"tool_use"}]}}' \
    >> "$TMPF/t.jsonl"

  echo '{"agent_transcript_path":"'"$TMPF/t.jsonl"'","agent_id":"agent-cond-166"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { echo "FAIL: hook exited $rc"; exit 1; }

  # Gate PASSED (identity match) → exactly one CONDUCTOR-TOKEN-EVENT, zero SPAWN-TOKEN-EVENT.
  cond_n=$(grep -c "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" 2>/dev/null); cond_n=${cond_n:-0}
  spawn_n=$(grep -c "^SPAWN-TOKEN-EVENT:" "$RUN_PATH/log.md" 2>/dev/null); spawn_n=${spawn_n:-0}
  [ "$cond_n" = "1" ] || { echo "FAIL: expected 1 CONDUCTOR event, got $cond_n"; cat "$RUN_PATH/log.md"; exit 1; }
  [ "$spawn_n" = "0" ] || { echo "FAIL: expected 0 SPAWN event, got $spawn_n"; exit 1; }

  event=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  payload="${event#CONDUCTOR-TOKEN-EVENT: }"
  # session_id == agent_id; first-leg delta processed == 0; final:true from accounting.status.
  echo "$payload" | jq -e '.session_id == "agent-cond-166" and .tokens.processed == 0 and .final == true and (.baseline.processed == 600)' > /dev/null \
    || { echo "FAIL: conductor event payload wrong: $payload"; exit 1; }

  echo "PASS"
  # Mutation note: this is the real-conductor-attributed half of Finding 1. If the
  # Step 8.0 gate's identity check were inverted (require differ instead of equal),
  # the real Conductor would be rejected → cond_n=0 → this fixture fails. The gate
  # must let the identity-MATCHED subagent through unchanged.
expected: exit 0; stdout "PASS"; real Conductor (agent_id == delegate-state conductor_agent_id, BUREAU_ROLE marker present) emits exactly one CONDUCTOR-TOKEN-EVENT (zero SPAWN), session_id=agent-cond-166, first-leg processed=0, final:true — happy path unchanged by the new gate
phase: 02 · feature — audit round 2, Finding 1
owner: scripts/subagent-stop.sh Step 8.0 conductor ownership gate (real-conductor attributed)
