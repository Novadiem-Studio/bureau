name: audit-r2 F1 (ii) CORE PROOF — FOREIGN transcript carries the public BUREAU_ROLE marker + RUN_DIR but agent_id != conductor_agent_id → NO event emitted (not conductor, not specialist), hook still exit 0
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"complete"}}' > "$RUN_PATH/state.json"

  # The live v2 run's real Conductor is agent-REAL. delegate-state.json names it.
  echo '{"topology":"integrated","conductor_agent_id":"agent-REAL","active_checkpoint":"01","revise_counts":{},"revision_cap":2}' > "$RUN_PATH/delegate-state.json"

  # FOREIGN transcript: it carries ONLY the two PUBLIC lines — RUN_DIR + the anchored
  # BUREAU_ROLE: conductor marker (both echo-able from the Delegate spawn prompt / log).
  # It has NO ownership credential. Its own agent_id is NOT the real conductor's.
  # Big spend (9999 in) that must NOT be attributed as the Conductor (dominant bucket).
  jq -cn --arg rp "$RUN_PATH" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $rp + "\ntopology: integrated\nBUREAU_ROLE: conductor\n")}}' \
    > "$TMPF/t.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":9999,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":500},"content":[{"type":"tool_use"}]}}' \
    >> "$TMPF/t.jsonl"

  echo '{"agent_transcript_path":"'"$TMPF/t.jsonl"'","agent_id":"agent-FOREIGN"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
  rc=$?
  # Hooks always exit 0 (never disrupt unrelated sessions).
  [ "$rc" = "0" ] || { echo "FAIL: hook exited $rc (must be 0)"; exit 1; }

  # The gate is CLOSED: ZERO events of ANY kind. The foreigner's 9999 tokens land
  # NEITHER as a CONDUCTOR-TOKEN-EVENT (the bug) NOR as a fall-through SPAWN-TOKEN-EVENT.
  cond_n=$(grep -c "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" 2>/dev/null); cond_n=${cond_n:-0}
  spawn_n=$(grep -c "^SPAWN-TOKEN-EVENT:" "$RUN_PATH/log.md" 2>/dev/null); spawn_n=${spawn_n:-0}
  [ "$cond_n" = "0" ] || { echo "FAIL: foreign attributed as Conductor ($cond_n events)"; cat "$RUN_PATH/log.md"; exit 1; }
  [ "$spawn_n" = "0" ] || { echo "FAIL: foreign fell through to specialist ($spawn_n events)"; cat "$RUN_PATH/log.md"; exit 1; }

  # No conductor baseline dotfile should be written for a rejected foreigner either.
  [ ! -e "$RUN_PATH/.conductor-subagent-baseline.json" ] || { echo "FAIL: baseline written for rejected foreigner"; exit 1; }

  echo "PASS"
  # Mutation note: this is the CORE security proof of Finding 1. Delete the Step 8.0
  # identity gate (the `if [ "$agent_id" != "$_cond_expected_agent_id" ]; then ... exit 0`
  # rejection) and the foreigner's mention-only transcript is attributed as the
  # Conductor → cond_n=1 → this fixture fails. That is the ownership-by-marker hole.
expected: exit 0; stdout "PASS"; a foreign transcript carrying only the public BUREAU_ROLE marker + RUN_DIR but whose agent_id != delegate-state conductor_agent_id is rejected — zero events (neither CONDUCTOR nor SPAWN), no baseline written — while the hook still exits 0. Mutation-test: removing the Step 8.0 gate lets the foreigner be attributed as the Conductor and fails this fixture.
phase: 02 · feature — audit round 2, Finding 1
owner: scripts/subagent-stop.sh Step 8.0 conductor ownership gate (the closed-gate core proof)
