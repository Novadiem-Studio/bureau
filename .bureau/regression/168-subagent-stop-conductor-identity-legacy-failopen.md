name: audit-r2 F1 (iii) legacy fail-open — BUREAU_ROLE marker present, NO delegate-state.json (pre-v2 run, no conductor credential) → still emits CONDUCTOR-TOKEN-EVENT as today
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"complete"}}' > "$RUN_PATH/state.json"

  # NO delegate-state.json at all — a pre-v2 / legacy run. There is no
  # conductor_agent_id credential to check against (and no conductor-subagent to
  # impersonate on such a run), so the gate must FAIL OPEN, not reject on a missing
  # credential. This mirrors #27's pointer-existence fail-open carve-out.

  jq -cn --arg rp "$RUN_PATH" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $rp + "\nBUREAU_ROLE: conductor\n")}}' \
    > "$TMPF/t.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":300,"output_tokens":10},"content":[{"type":"tool_use"}]}}' \
    >> "$TMPF/t.jsonl"

  echo '{"agent_transcript_path":"'"$TMPF/t.jsonl"'","agent_id":"agent-legacy-168"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { echo "FAIL: hook exited $rc"; exit 1; }

  # Fail-open: exactly one CONDUCTOR-TOKEN-EVENT emitted as today (the missing
  # credential does NOT reject the one real capture path a legacy run has).
  cond_n=$(grep -c "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" 2>/dev/null); cond_n=${cond_n:-0}
  spawn_n=$(grep -c "^SPAWN-TOKEN-EVENT:" "$RUN_PATH/log.md" 2>/dev/null); spawn_n=${spawn_n:-0}
  [ "$cond_n" = "1" ] || { echo "FAIL: legacy run not attributed (fail-open broken), got $cond_n"; cat "$RUN_PATH/log.md"; exit 1; }
  [ "$spawn_n" = "0" ] || { echo "FAIL: expected 0 SPAWN, got $spawn_n"; exit 1; }

  event=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  payload="${event#CONDUCTOR-TOKEN-EVENT: }"
  echo "$payload" | jq -e '.session_id == "agent-legacy-168" and .final == true' > /dev/null \
    || { echo "FAIL: legacy conductor event payload wrong: $payload"; exit 1; }

  echo "PASS"
  # Mutation note: change the Step 8.0 fail-open carve-out to REJECT when the
  # credential is absent (drop the `if [ -n "$_cond_expected_agent_id" ]` guard and
  # always require a match) → a legacy run with no delegate-state.json is rejected →
  # cond_n=0 → this fixture fails. The carve-out must fail open on a missing credential.
expected: exit 0; stdout "PASS"; a legacy/pre-v2 run (BUREAU_ROLE marker present, NO delegate-state.json → no conductor_agent_id credential) fails open and still emits exactly one CONDUCTOR-TOKEN-EVENT as today. Mutation-test: making the gate reject on an absent credential breaks legacy capture and fails this fixture.
phase: 02 · feature — audit round 2, Finding 1
owner: scripts/subagent-stop.sh Step 8.0 conductor ownership gate (legacy fail-open carve-out)
