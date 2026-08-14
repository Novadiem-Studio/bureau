name: subagent-stop DQ-5 negative — specialist (even prose "conductor" mention) → SPAWN-TOKEN-EVENT, never CONDUCTOR (AC-8)
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"complete"}}' > "$RUN_PATH/state.json"

  # #27 ownership gate: pointer (munged RUN_DIR key) with nonce + nonce in prompt,
  # so this real specialist passes the gate and still emits its SPAWN-TOKEN-EVENT.
  export BUREAU_POINTER_DIR="$TMPF/active-runs"
  mkdir -p "$BUREAU_POINTER_DIR"
  NONCE="plain-spec-nonce-$(date +%s)-778899"
  PTR_KEY=$(printf '%s' "$RUN_PATH" | sed 's#[/.]#-#g')
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-07-11T00:00:00Z","project_dir":"%s"}\n' \
    "$RUN_PATH" "$NONCE" "$TMPF" > "$BUREAU_POINTER_DIR/$PTR_KEY"

  # Adversarial first user message: carries RUN_DIR + Attempt ID + Run nonce (a real
  # specialist spawn) AND mentions the word "conductor" in prose, but NO
  # anchored `BUREAU_ROLE: conductor` line. The anchored-exact grep must NOT
  # match the prose mention.
  jq -cn --arg rp "$RUN_PATH" --arg nonce "$NONCE" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $rp + "\nRole mode: feature\nAttempt ID: mage-1\nRun nonce: " + $nonce + "\nReview the Conductor'"'"'s plan and report to the conductor loop.\n")}}' \
    > "$TMPF/t.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":300,"output_tokens":10},"content":[{"type":"tool_use"}]}}' \
    >> "$TMPF/t.jsonl"

  echo '{"agent_transcript_path":"'"$TMPF/t.jsonl"'","agent_id":"agent-mage-140"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }

  # Exactly one SPAWN-TOKEN-EVENT with attempt_id mage-1; ZERO CONDUCTOR lines.
  # (grep -c always prints a number, exit 1 on zero matches — no `|| echo 0`,
  # which would append a second line and break the `= "0"` compare.)
  spawn_n=$(grep -c "^SPAWN-TOKEN-EVENT:" "$RUN_PATH/log.md" 2>/dev/null); spawn_n=${spawn_n:-0}
  cond_n=$(grep -c "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" 2>/dev/null); cond_n=${cond_n:-0}
  [ "$spawn_n" = "1" ] || { rm -rf "$TMPF"; exit 1; }
  [ "$cond_n" = "0" ] || { rm -rf "$TMPF"; exit 1; }

  event=$(grep "^SPAWN-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  payload="${event#SPAWN-TOKEN-EVENT: }"
  echo "$payload" | jq -e '.attempt_id == "mage-1"' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # No baseline dotfile should be created for a specialist.
  [ ! -e "$RUN_PATH/.conductor-subagent-baseline.json" ] || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: loosen the marker grep to an unanchored `grep -q conductor`
  # → the prose "conductor" mention misfires → the line comes out as a
  # CONDUCTOR-TOKEN-EVENT → cond_n=1/spawn_n=0 → fixture fails. This is the
  # DQ-5 anchored-exact guard's own test.
expected: exit 0; stdout "PASS"; specialist subagent (prose "conductor" mention but no BUREAU_ROLE: line) still emits exactly one SPAWN-TOKEN-EVENT with attempt_id="mage-1", zero CONDUCTOR-TOKEN-EVENT, and no baseline dotfile
phase: 02 · feature
owner: subagent-stop.sh DQ-5 no-misclassification negative (v2-conductor-capture)
