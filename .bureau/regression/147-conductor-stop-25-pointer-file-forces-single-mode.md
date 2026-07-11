name: conductor-stop #25 — BUREAU_POINTER_FILE forces single-file mode; the pointer DIRECTORY is never consulted even when populated (AC 4 precedence keystone)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  # BOTH env vars set: the precedence rule says BUREAU_POINTER_FILE wins and the
  # directory is never enumerated. This documents the compatibility keystone
  # (every existing conductor-stop / delta-baseline fixture relies on it).
  export BUREAU_POINTER_FILE="$TMPF/single-active-run"
  export BUREAU_POINTER_DIR="$TMPF/active-runs"
  mkdir -p "$BUREAU_POINTER_DIR"

  RUN_A="$TMPF/run-A"; mkdir -p "$RUN_A"; touch "$RUN_A/log.md"
  echo '{"accounting":{"status":"pending"}}' > "$RUN_A/state.json"
  NONCE_A="nonce-single-A-42"
  echo '{"run_dir":"'"$RUN_A"'","nonce":"'"$NONCE_A"'","written_at":"2026-07-11T00:00:00Z"}' \
    > "$BUREAU_POINTER_FILE"
  # A DECOY pointer in the directory. If the directory were (wrongly) consulted in
  # single-file mode it would be a live candidate. Under the precedence rule it is
  # never read and must stay untouched.
  echo '{"run_dir":"'"$RUN_A"'","nonce":"decoy-must-not-be-read","written_at":"2026-07-11T00:00:00Z"}' \
    > "$BUREAU_POINTER_DIR/decoy"

  printf '%s\n' "RUN_DIR: $RUN_A" "Nonce: $NONCE_A" \
    '{"type":"assistant","message":{"id":"mA","usage":{"input_tokens":7,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1},"content":[{"type":"text"}]}}' \
    > "$TMPF/tA.jsonl"
  echo '{"session_id":"sA","transcript_path":"'"$TMPF/tA.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  [ "$?" = "0" ] || { rm -rf "$TMPF"; exit 1; }

  # Exactly one event, from the SINGLE file (input 7), behaving like a pre-#25 run.
  n=$(grep -c "^CONDUCTOR-TOKEN-EVENT:" "$RUN_A/log.md"); [ "$n" = "1" ] || { rm -rf "$TMPF"; exit 1; }
  p="$(grep '^CONDUCTOR-TOKEN-EVENT:' "$RUN_A/log.md" | head -1)"; p="${p#CONDUCTOR-TOKEN-EVENT: }"
  echo "$p" | jq -e '.session_id == "sA" and .tokens.input == 7 and .final == false' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  # The single file stays (run open); the directory decoy is untouched (never read).
  [ -e "$BUREAU_POINTER_FILE" ] || { rm -rf "$TMPF"; exit 1; }
  [ -e "$BUREAU_POINTER_DIR/decoy" ] || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: drop the `if [ -n "${BUREAU_POINTER_FILE:-}" ]` single-file
  # branch in Step A.5 (always enumerate BUREAU_POINTER_DIR) → the decoy becomes a
  # candidate; its run_dir grep passes on this transcript, so selection may pick
  # the decoy (wrong nonce, or ambiguous double-match) → assertions on the single
  # file's clean capture fail. That branch is what keeps every existing
  # single-file fixture byte-identical.
expected: exit 0; stdout "PASS"; BUREAU_POINTER_FILE set forces single-file mode — one event from the single file (input 7), the populated pointer directory is never consulted (decoy untouched)
phase: 03 · feature
owner: conductor-stop.sh #25 BUREAU_POINTER_FILE forced-single-file precedence
