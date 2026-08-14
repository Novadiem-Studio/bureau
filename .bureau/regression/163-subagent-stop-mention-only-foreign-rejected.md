name: #27 NEW-B · specialist ownership gate CLOSED — a mention-only FOREIGN subagent (pointer present with nonce N; transcript carries RUN_DIR + Attempt ID but NOT N) is REJECTED (zero events appended), hook still exit 0
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  RUN_PATH="$TMPF/run-foreign"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"

  # Pointer present with nonce N (a live run). The foreigner never received N.
  export BUREAU_POINTER_DIR="$TMPF/active-runs"
  mkdir -p "$BUREAU_POINTER_DIR"
  NONCE="secret-nonce-only-owner-has-this-$(date +%s)"
  PTR_KEY=$(printf '%s' "$RUN_PATH" | sed 's#[/.]#-#g')
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-07-11T00:00:00Z","project_dir":"%s"}\n' \
    "$RUN_PATH" "$NONCE" "$TMPF" > "$BUREAU_POINTER_DIR/$PTR_KEY"

  # FOREIGN transcript: it "read log.md" and echoed RUN_DIR + Attempt ID (the audited
  # ownership-by-mention vector) but does NOT carry the secret nonce N. This is
  # exactly what a nested helper / re-spawn / self-run analysis spawn would look
  # like — same-run mention, no secret.
  jq -cn --arg rp "$RUN_PATH" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $rp + "\nAttempt ID: mage-1\n(quoted the spawn prompt from log.md; no nonce)\n")}}' \
    > "$TMPF/t.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":9999,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":500},"content":[{"type":"text"}]}}' \
    >> "$TMPF/t.jsonl"

  echo '{"agent_transcript_path":"'"$TMPF/t.jsonl"'","agent_id":"agent-foreign-1"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
  rc=$?
  # Hooks always exit 0 (never disrupt unrelated sessions).
  [ "$rc" = "0" ] || { echo "FAIL: hook exited $rc (must be 0)"; exit 1; }

  # The gate is CLOSED: ZERO SPAWN-TOKEN-EVENT lines appended. The foreigner's
  # 9999 tokens do NOT land under mage-1 (or anything).
  n=$(grep -c "^SPAWN-TOKEN-EVENT:" "$RUN_PATH/log.md" 2>/dev/null); n=${n:-0}
  [ "$n" = "0" ] || { echo "FAIL: expected 0 SPAWN-TOKEN-EVENT (foreign rejected), got $n"; cat "$RUN_PATH/log.md"; exit 1; }
  echo "PASS"
  # Mutation note: this is the CORE security proof. Delete the `grep -qF -- "$_ptr_nonce"`
  # rejection (or make Step 4.7 fall through to attribute when the nonce is absent)
  # and the foreigner's mention-only transcript emits a SPAWN-TOKEN-EVENT → n=1 →
  # fixture fails. That is the ownership-by-mention hole this idea closes.
expected: exit 0; stdout "PASS"; a same-run subagent carrying RUN_DIR + Attempt ID but NOT the run nonce is rejected — zero SPAWN-TOKEN-EVENT appended — while the hook still exits 0. Mutation-test: removing the nonce-grep rejection lets the mention-only foreigner be attributed and fails this fixture.
phase: 02 · feature — audit follow-up #27
owner: scripts/subagent-stop.sh Step 4.7 specialist ownership gate (audit #27, the closed-gate negative)
