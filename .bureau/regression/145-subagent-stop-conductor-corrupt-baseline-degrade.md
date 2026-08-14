name: subagent-stop conductor corrupt-baseline — unparseable dotfile → fresh first leg, self-heal to valid JSON, no crash (AC-7, EC-3 class)
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"pending"}}' > "$RUN_PATH/state.json"

  # Seed a CORRUPT-but-readable baseline file (unparseable, non-object JSON).
  # This is distinct from fixture 142 (unwritable): here the file exists and is
  # readable but its content cannot be parsed. The read guard (jq type=="object")
  # must treat it as absent → a fresh first leg → record + self-heal.
  export BUREAU_SUBAGENT_BASELINE_FILE="$TMPF/corrupt-baseline.json"
  printf '%s' '{{{ not json at all' > "$BUREAU_SUBAGENT_BASELINE_FILE"

  jq -cn --arg rp "$RUN_PATH" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $rp + "\nBUREAU_ROLE: conductor\n")}}' \
    > "$TMPF/t.jsonl"
  # Cumulative: input 100, cache_creation 200, cache_read 300, processed 600, output 10, turns 1.
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":300,"output_tokens":10},"content":[{"type":"tool_use"}]}}' \
    >> "$TMPF/t.jsonl"

  echo '{"agent_transcript_path":"'"$TMPF/t.jsonl"'","agent_id":"agent-cond-145"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }

  # Exactly one CONDUCTOR-TOKEN-EVENT (no crash, no garbage line).
  cond_n=$(grep -c "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" 2>/dev/null); cond_n=${cond_n:-0}
  [ "$cond_n" = "1" ] || { rm -rf "$TMPF"; exit 1; }

  event=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  payload="${event#CONDUCTOR-TOKEN-EVENT: }"
  # Treated as a fresh first leg: baseline == cumulative → delta processed == 0,
  # and the baseline object on the line carries this agent's cumulative (600).
  echo "$payload" | jq -e '
    .session_id == "agent-cond-145" and
    .tokens.processed == 0 and
    (.baseline.processed == 600)
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # Self-heal: the corrupt file was rewritten to VALID JSON, a top-level object
  # keyed by this agent_id carrying the recorded cumulative.
  jq -e '
    (type == "object") and
    (."agent-cond-145".input == 100) and
    (."agent-cond-145".cache_read == 300) and
    (."agent-cond-145".processed == 600) and
    (."agent-cond-145".turns == 1)
  ' "$BUREAU_SUBAGENT_BASELINE_FILE" > /dev/null || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: the load-bearing guard is the `type == "object"` reset in
  # _cond_bl_write_back — the line `... | jq -e 'type == "object"' ... || existing="{}"`
  # that discards corrupt existing content before the merge. Remove it and the
  # corrupt `{{{` flows into `jq '. + {($aid): $cand}'`, which parse-errors → the
  # write-back returns 1 → the file is NOT self-healed to valid JSON → the
  # self-heal assertion (baseline file is a valid object keyed by agent_id) fails.
  # (The read side already routes to first-leg regardless: jq parse-fails the
  # corrupt file, so cond_bl_existing is empty — the write-back guard is what makes
  # the self-heal safe and is the one this fixture pins.)
expected: exit 0; stdout "PASS"; a corrupt-but-readable baseline dotfile is treated as a fresh first leg (delta processed=0, baseline.processed=600), the dotfile is self-healed to valid JSON keyed by agent_id with the cumulative, exit 0, no crash
phase: 02 · feature
owner: subagent-stop.sh conductor corrupt-baseline self-heal (v2-conductor-capture)
