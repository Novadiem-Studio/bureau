name: subagent-stop conductor multi-leg — pre-seeded baseline → delta processed, NO cache_read double-count (AC-4, exact-wash class)
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"pending"}}' > "$RUN_PATH/state.json"

  # Pre-seed the per-agent baseline as if a first leg already recorded it.
  # Baseline: input 20000000, cache_creation 8000000, cache_read 6000000,
  #           processed 34000000, output 300000, turns 5.
  AID="agent-cond-139"
  printf '{"%s":{"session_id":"%s","input":20000000,"cache_creation":8000000,"cache_read":6000000,"processed":34000000,"output":300000,"turns":5}}\n' \
    "$AID" "$AID" > "$RUN_PATH/.conductor-subagent-baseline.json"

  # Later-leg cumulative transcript (strictly larger than baseline):
  #   input 30000000, cache_creation 12000000, cache_read 10000000,
  #   output 400000, turns 8 (one tool_use group here).
  jq -cn --arg rp "$RUN_PATH" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $rp + "\nBUREAU_ROLE: conductor\n")}}' \
    > "$TMPF/t.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":30000000,"cache_creation_input_tokens":12000000,"cache_read_input_tokens":10000000,"output_tokens":400000},"content":[{"type":"tool_use"}]}}' \
    >> "$TMPF/t.jsonl"

  echo '{"agent_transcript_path":"'"$TMPF/t.jsonl"'","agent_id":"'"$AID"'"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }

  event=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  [ -n "$event" ] || { rm -rf "$TMPF"; exit 1; }
  payload="${event#CONDUCTOR-TOKEN-EVENT: }"

  # Delta = cumulative - baseline (NOT the raw cumulative):
  #   input          30000000 - 20000000 = 10000000
  #   cache_creation 12000000 -  8000000 =  4000000
  #   cache_read     10000000 -  6000000 =  4000000   ← NOT 10000000 (no double-count)
  #   processed      10000000 + 4000000 + 4000000 = 18000000
  echo "$payload" | jq -e '
    .session_id == "agent-cond-139" and
    .tokens.input == 10000000 and
    .tokens.cache_creation == 4000000 and
    .tokens.cache_read == 4000000 and
    .tokens.processed == 18000000 and
    (.baseline.processed == 34000000)
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # Explicit no-double-count guard: cache_read is the DELTA (4M), never the raw
  # cumulative (10M). This is the exact-wash-class hazard the baseline prevents.
  cr=$(echo "$payload" | jq -r '.tokens.cache_read')
  [ "$cr" = "4000000" ] || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: drop the baseline subtraction in the later-leg branch (force
  # cond_baseline_is_legacy=true) → processed comes out as the raw cumulative
  # 52000000 and cache_read as 10000000 → both assertions fail. This is the
  # load-bearing no-double-count proof.
expected: exit 0; stdout "PASS"; CONDUCTOR-TOKEN-EVENT with baseline-relative delta (input 10M, cache_creation 4M, cache_read 4M NOT 10M, processed 18M), baseline.processed=34M reused from the pre-seeded per-agent baseline file — no cross-leg double-count
phase: 02 · feature
owner: subagent-stop.sh conductor multi-leg delta / no-double-count (v2-conductor-capture)
