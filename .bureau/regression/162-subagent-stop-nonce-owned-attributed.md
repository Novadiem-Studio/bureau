name: #27 NEW-A · specialist ownership gate — a legit nonce-bearing specialist (pointer present with nonce N; transcript carries RUN_DIR + Attempt ID + N) is ATTRIBUTED with the correct attempt_id
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  RUN_PATH="$TMPF/run-owned"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"

  # Pointer present with nonce N, keyed by the munged RUN_DIR (#25 precedence).
  export BUREAU_POINTER_DIR="$TMPF/active-runs"
  mkdir -p "$BUREAU_POINTER_DIR"
  NONCE="owned-nonce-deadbeef-$(date +%s)"
  PTR_KEY=$(printf '%s' "$RUN_PATH" | sed 's#[/.]#-#g')
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-07-11T00:00:00Z","project_dir":"%s"}\n' \
    "$RUN_PATH" "$NONCE" "$TMPF" > "$BUREAU_POINTER_DIR/$PTR_KEY"

  # Legit specialist transcript: RUN_DIR + Attempt ID + the real nonce N.
  jq -cn --arg rp "$RUN_PATH" --arg nonce "$NONCE" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $rp + "\nAttempt ID: mage-1\nRun nonce: " + $nonce + "\n")}}' \
    > "$TMPF/t.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5},"content":[{"type":"text"}]}}' \
    >> "$TMPF/t.jsonl"

  echo '{"agent_transcript_path":"'"$TMPF/t.jsonl"'","agent_id":"agent-owned-1"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { echo "FAIL: hook exited $rc"; exit 1; }

  # The gate OPENED: exactly one SPAWN-TOKEN-EVENT with attempt_id mage-1.
  n=$(grep -c "^SPAWN-TOKEN-EVENT:" "$RUN_PATH/log.md" 2>/dev/null); n=${n:-0}
  [ "$n" = "1" ] || { echo "FAIL: expected 1 SPAWN-TOKEN-EVENT, got $n"; exit 1; }
  event=$(grep "^SPAWN-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  payload="${event#SPAWN-TOKEN-EVENT: }"
  echo "$payload" | jq -e '.attempt_id == "mage-1"' > /dev/null || { echo "FAIL: attempt_id not mage-1"; exit 1; }
  echo "PASS"
  # Mutation note: delete the `grep -qF -- "$_ptr_nonce"` state-1 attribute path
  # (or the whole Step 4.7 gate) and this still passes — this is the POSITIVE
  # counter-guard to NEW-B (162 must stay green while 163 proves the reject). The
  # load-bearing mutation for 162 is inverting the state-1 grep sense (attribute on
  # ABSENT), which would REJECT this legit spawn → n=0 → fail.
expected: exit 0; stdout "PASS"; a pointer-backed specialist whose transcript carries the run nonce is attributed with exactly one SPAWN-TOKEN-EVENT, attempt_id="mage-1" (the gate opens for a real spawn).
phase: 02 · feature — audit follow-up #27
owner: scripts/subagent-stop.sh Step 4.7 specialist ownership gate (audit #27, positive)
