name: subagent-stop conductor wrong-TYPE baseline object — a parseable baseline slot with a non-number numeric field is treated as absent → fresh first leg, self-heal to clean JSON, correct event (audit F5, mirrors 145)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"pending"}}' > "$RUN_PATH/state.json"

  # Seed a baseline that is VALID JSON and an OBJECT with a slot for THIS agent,
  # but whose `input` field is a STRING ("oops"), not a number. Distinct from 145
  # (unparseable file): this file parses and passes the `type=="object"` state
  # gate, so only the numeric-field type-check rejects it. Under the bug the slot
  # was reused; `.input // 0` yielded "oops"; compute_delta_line's
  # `--argjson b_input "oops"` was invalid JSON → compose failed → ZERO events
  # appended and the corrupt baseline LEFT INTACT (permanent accounting loss).
  # Under the fix the wrong-type slot is treated as absent → fresh first leg →
  # self-heal the slot to clean JSON + emit a correct event.
  export BUREAU_SUBAGENT_BASELINE_FILE="$TMPF/wrongtype-baseline.json"
  AID="agent-cond-155"
  printf '{"%s":{"session_id":"%s","input":"oops","cache_creation":2,"cache_read":3,"processed":6,"output":4,"turns":5}}\n' \
    "$AID" "$AID" > "$BUREAU_SUBAGENT_BASELINE_FILE"

  jq -cn --arg rp "$RUN_PATH" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $rp + "\nBUREAU_ROLE: conductor\n")}}' \
    > "$TMPF/t.jsonl"
  # Cumulative: input 100, cache_creation 200, cache_read 300, processed 600, output 10, turns 1.
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":300,"output_tokens":10},"content":[{"type":"tool_use"}]}}' \
    >> "$TMPF/t.jsonl"

  echo '{"agent_transcript_path":"'"$TMPF/t.jsonl"'","agent_id":"'"$AID"'"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }

  # Exactly one CONDUCTOR-TOKEN-EVENT (the corrupt baseline no longer strands it).
  cond_n=$(grep -c "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" 2>/dev/null); cond_n=${cond_n:-0}
  [ "$cond_n" = "1" ] || { rm -rf "$TMPF"; exit 1; }

  event=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  payload="${event#CONDUCTOR-TOKEN-EVENT: }"
  # Treated as a fresh first leg: baseline == cumulative → delta processed == 0,
  # and the emitted baseline object carries this agent's cumulative (600).
  echo "$payload" | jq -e '
    .session_id == "'"$AID"'" and
    .tokens.processed == 0 and
    (.baseline.processed == 600)
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # Self-heal: the corrupt slot was rewritten to clean JSON with numeric fields.
  jq -e '
    (."'"$AID"'".input == 100) and
    ((."'"$AID"'".input | type) == "number") and
    (."'"$AID"'".cache_read == 300) and
    (."'"$AID"'".processed == 600) and
    (."'"$AID"'".turns == 1)
  ' "$BUREAU_SUBAGENT_BASELINE_FILE" > /dev/null || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: the load-bearing guard is the `map(numbers) | length == 6`
  # type-check added to the cond_bl_existing read. Remove it (revert to the plain
  # `type == "object"` slot guard) and the wrong-type slot is reused: `.input //
  # 0` = "oops" → compute_delta_line's `--argjson b_input "oops"` is invalid JSON
  # → event_line empty → the WARNING/skip path fires → cond_n == 0 → the "exactly
  # one event" assertion fails, and the corrupt baseline is never self-healed.
expected: exit 0; stdout "PASS"; a parseable wrong-type baseline slot is treated as a fresh first leg (delta processed=0, baseline.processed=600), self-healed to clean numeric JSON, exactly one CONDUCTOR-TOKEN-EVENT, no crash
phase: 02 · feature
owner: subagent-stop.sh conductor wrong-type baseline self-heal (audit F5)
