name: #27 NEW-D · the run nonce NEVER lands in log.md — a legit attributed specialist writes its SPAWN-TOKEN-EVENT but the nonce value appears NOWHERE in log.md, and orchestrator.md forbids the nonce on SPAWN-EVENT / in log.md
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  RUN_PATH="$TMPF/run-nonce-leak"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"

  # A legit, ATTRIBUTED specialist (state 1, gate opens) — the interesting case:
  # the nonce IS in the transcript, so it could accidentally be echoed to log.md.
  export BUREAU_POINTER_DIR="$TMPF/active-runs"
  mkdir -p "$BUREAU_POINTER_DIR"
  NONCE="LEAK-CANARY-NONCE-$(date +%s)-zzz"
  PTR_KEY=$(printf '%s' "$RUN_PATH" | sed 's#[/.]#-#g')
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-07-11T00:00:00Z","project_dir":"%s"}\n' \
    "$RUN_PATH" "$NONCE" "$TMPF" > "$BUREAU_POINTER_DIR/$PTR_KEY"
  jq -cn --arg rp "$RUN_PATH" --arg nonce "$NONCE" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $rp + "\nAttempt ID: systemsmith-1\nRun nonce: " + $nonce + "\n")}}' \
    > "$TMPF/t.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1},"content":[{"type":"text"}]}}' \
    >> "$TMPF/t.jsonl"
  echo '{"agent_transcript_path":"'"$TMPF/t.jsonl"'","agent_id":"agent-leak-1"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null

  # It WAS attributed (proves this is the live, nonce-in-transcript path)...
  grep -q "^SPAWN-TOKEN-EVENT:" "$RUN_PATH/log.md" \
    || { echo "FAIL: precondition — legit specialist was not attributed"; exit 1; }
  # ...but the nonce value appears NOWHERE in log.md. subagent-stop.sh writes the
  # token event, which carries agent_id/attempt_id/tokens — never the nonce.
  if grep -qF -- "$NONCE" "$RUN_PATH/log.md"; then
    echo "FAIL: the run nonce LEAKED into log.md"; grep -F -- "$NONCE" "$RUN_PATH/log.md"; exit 1
  fi

  # Static guard on the spawn-convention doctrine: orchestrator.md must forbid the
  # nonce on a SPAWN-EVENT line / in log.md (so a future edit can't reopen the hole).
  ORCH="$ROOT/agents/orchestrator.md"
  grep -q 'NEVER write the nonce to .log.md' "$ORCH" \
    || { echo "FAIL: orchestrator.md spawn note does not forbid writing the nonce to log.md"; exit 1; }
  grep -q 'run nonce is NEVER on a SPAWN-EVENT line' "$ORCH" \
    || { echo "FAIL: orchestrator.md SPAWN-EVENT section does not forbid the nonce on a SPAWN-EVENT line"; exit 1; }
  echo "PASS"
  # Mutation note: if subagent-stop.sh's SPAWN-TOKEN-EVENT jq were edited to include
  # the nonce, the `grep -qF -- "$NONCE" log.md` would match → fail. If the
  # orchestrator.md doctrine lines were deleted, the static greps fail.
expected: exit 0; stdout "PASS"; a legit attributed specialist (nonce in transcript) writes a SPAWN-TOKEN-EVENT yet the nonce value is absent from log.md, and orchestrator.md forbids the nonce on SPAWN-EVENT lines and in log.md. Mutation-test: emitting the nonce into the event, or deleting the orchestrator.md doctrine, fails the guard.
phase: 02 · feature — audit follow-up #27
owner: scripts/subagent-stop.sh + agents/orchestrator.md nonce-never-in-log guard (audit #27, Q3)
