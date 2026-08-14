name: subagent-stop conductor final — state.json accounting.status drives final:true/false (AC-5, DQ-2)
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"

  run_leg() {
    # $1 = state.json contents (or the literal "ABSENT" to omit state.json)
    local state="$1" tmpf rp payload
    tmpf=$(mktemp -d)
    rp="$tmpf/run"
    mkdir -p "$rp"
    touch "$rp/log.md"
    if [ "$state" != "ABSENT" ]; then
      printf '%s\n' "$state" > "$rp/state.json"
    fi
    jq -cn --arg r "$rp" \
      '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $r + "\nBUREAU_ROLE: conductor\n")}}' \
      > "$tmpf/t.jsonl"
    printf '%s\n' \
      '{"type":"assistant","message":{"id":"m","usage":{"input_tokens":10,"cache_creation_input_tokens":5,"cache_read_input_tokens":5,"output_tokens":1},"content":[{"type":"tool_use"}]}}' \
      >> "$tmpf/t.jsonl"
    echo '{"agent_transcript_path":"'"$tmpf/t.jsonl"'","agent_id":"agent-fin"}' \
      | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
    payload=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$rp/log.md" | head -1)
    payload="${payload#CONDUCTOR-TOKEN-EVENT: }"
    echo "$payload" | jq -r '.final'
    rm -rf "$tmpf"
  }

  # 1. Closed run (status:complete) → final:true
  [ "$(run_leg '{"accounting":{"status":"complete"}}')" = "true" ]  || { echo "complete!=true"; exit 1; }
  # 2. Open run (status:pending) → final:false
  [ "$(run_leg '{"accounting":{"status":"pending"}}')" = "false" ]  || { echo "pending!=false"; exit 1; }
  # 3. Absent state.json → final:false (fail-safe open)
  [ "$(run_leg 'ABSENT')" = "false" ]                               || { echo "absent!=false"; exit 1; }
  # 4. status:unavailable (a non-pending close reason) → final:true
  [ "$(run_leg '{"accounting":{"status":"unavailable"}}')" = "true" ] || { echo "unavailable!=true"; exit 1; }

  echo "PASS"
  # Mutation note: change the close test from `!= "pending"` to always-false
  # → cases 1 and 4 emit final:false → fixture fails. Change to always-true
  # → cases 2 and 3 emit final:true → fixture fails.
expected: exit 0; stdout "PASS"; CONDUCTOR-TOKEN-EVENT final:true when state.json accounting.status is present and not "pending" (complete, unavailable), final:false when pending or state.json absent (fail-safe open)
phase: 02 · feature
owner: subagent-stop.sh conductor final-from-state (v2-conductor-capture)
