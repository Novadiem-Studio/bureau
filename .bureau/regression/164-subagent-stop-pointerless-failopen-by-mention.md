name: #27 NEW-C · specialist ownership gate carve-out — a pointer-LESS run (no pointer file for RUN_DIR) fails OPEN, attributing by mention with a stderr note; and this path is NOT foreigner-exploitable
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  RUN_PATH="$TMPF/run-legacy"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"

  # Directory mode with an EMPTY active-runs dir → NO pointer file resolves for
  # this RUN_DIR (state 2: legacy / archived-mid-flight). We do NOT write a pointer.
  export BUREAU_POINTER_DIR="$TMPF/active-runs"
  mkdir -p "$BUREAU_POINTER_DIR"

  # Transcript carries RUN_DIR + Attempt ID, NO nonce (a pre-#27 legacy spawn).
  jq -cn --arg rp "$RUN_PATH" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $rp + "\nAttempt ID: architect-1\n")}}' \
    > "$TMPF/t.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":42,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":3},"content":[{"type":"text"}]}}' \
    >> "$TMPF/t.jsonl"

  # Capture stderr to assert the fail-open note fired.
  echo '{"agent_transcript_path":"'"$TMPF/t.jsonl"'","agent_id":"agent-legacy-1"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2> "$TMPF/err.log"
  rc=$?
  [ "$rc" = "0" ] || { echo "FAIL: hook exited $rc"; exit 1; }

  # Fail-OPEN: the state-2 carve-out still attributes by mention → one event.
  n=$(grep -c "^SPAWN-TOKEN-EVENT:" "$RUN_PATH/log.md" 2>/dev/null); n=${n:-0}
  [ "$n" = "1" ] || { echo "FAIL: expected 1 SPAWN-TOKEN-EVENT (pointer-less fail-open), got $n"; exit 1; }
  event=$(grep "^SPAWN-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  echo "${event#SPAWN-TOKEN-EVENT: }" | jq -e '.attempt_id == "architect-1"' > /dev/null \
    || { echo "FAIL: attempt_id not architect-1"; exit 1; }
  # The stderr note names the pointer-less fail-open (pins the carve-out branch).
  grep -q 'no pointer file for RUN_DIR' "$TMPF/err.log" \
    || { echo "FAIL: pointer-less fail-open stderr note missing"; cat "$TMPF/err.log"; exit 1; }
  echo "PASS"
  # Mutation note: pins the migration carve-out. A later edit that hardened the
  # pointer-ABSENT branch into a REJECT (data-loss for archived runs) would make
  # n=0 and this fixture fail. NOTE the safety argument: the carve-out is keyed on
  # pointer EXISTENCE, which a foreigner cannot induce (it cannot delete the real
  # run's pointer) — so during any live run the gate is CLOSED (state 1, see 163),
  # and this fail-open only fires for a genuinely pointer-less legacy/archived run.
expected: exit 0; stdout "PASS"; when NO pointer file resolves for RUN_DIR, the gate fails open — attributes one SPAWN-TOKEN-EVENT (attempt_id="architect-1") by mention and emits the "no pointer file for RUN_DIR" stderr note. Mutation-test: hardening the pointer-absent branch into a reject makes n=0 and fails.
phase: 02 · feature — audit follow-up #27
owner: scripts/subagent-stop.sh Step 4.7 pointer-existence fail-open carve-out (audit #27)
