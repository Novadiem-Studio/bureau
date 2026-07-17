name: run-reopen ceremony — status reset to pending, pointer written with recovered baseline, log line appended
phase: 05 · conductor-capture-lifecycle (Lever 2)
owner: scripts/run-reopen.sh
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  PF="$TMPF/ptr"
  mkdir -p "$RP"
  # state.json: accounting.status = "complete" (post-close-out)
  printf '%s\n' '{"accounting":{"status":"complete"}}' > "$RP/state.json"
  # log.md: one CONDUCTOR-TOKEN-EVENT with a baseline object (non-legacy shape)
  BASELINE_OBJ='{"session_id":"sess-A","input":0,"cache_creation":0,"cache_read":0,"processed":0,"output":0,"turns":0}'
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-A","at":"2026-07-16T19:52:49Z","turns":67,"tokens":{"input":1974,"cache_creation":269575,"cache_read":22366276,"processed":22637825,"output":148112},"final":true,"baseline":'"$BASELINE_OBJ"'}' \
    > "$RP/log.md"
  # Run the ceremony
  out=$(BUREAU_POINTER_FILE="$PF" bash "$ROOT/scripts/run-reopen.sh" "$RP" 2>/dev/null)
  rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: run-reopen.sh exited $rc"; rm -rf "$TMPF"; exit 1; }
  # (1) accounting.status must be "pending"
  status=$(jq -r '.accounting.status' "$RP/state.json" 2>/dev/null)
  [ "$status" = "pending" ] \
    || { echo "FAIL: accounting.status = $status (expected pending)"; rm -rf "$TMPF"; exit 1; }
  # (2) pointer written with five-field format AND recovered baseline (not null)
  [ -f "$PF" ] || { echo "FAIL: pointer file not written"; rm -rf "$TMPF"; exit 1; }
  bl_type=$(jq -r '.baseline | type' "$PF" 2>/dev/null)
  bl_sid=$(jq -r '.baseline.session_id // ""' "$PF" 2>/dev/null)
  [ "$bl_type" = "object" ] \
    || { echo "FAIL: pointer baseline type = $bl_type (expected object)"; rm -rf "$TMPF"; exit 1; }
  [ "$bl_sid" = "sess-A" ] \
    || { echo "FAIL: pointer baseline.session_id = $bl_sid (expected sess-A)"; rm -rf "$TMPF"; exit 1; }
  # nonce must be present and non-empty
  nonce=$(jq -r '.nonce // ""' "$PF" 2>/dev/null)
  [ -n "$nonce" ] || { echo "FAIL: pointer nonce absent"; rm -rf "$TMPF"; exit 1; }
  # stdout must echo the pointer (nonce credential)
  echo_nonce=$(printf '%s' "$out" | jq -r '.nonce // ""' 2>/dev/null)
  [ "$echo_nonce" = "$nonce" ] \
    || { echo "FAIL: stdout nonce ($echo_nonce) differs from pointer nonce ($nonce)"; rm -rf "$TMPF"; exit 1; }
  # (3) nonce-free log line appended (no nonce value in log)
  PATH=/usr/bin:$PATH grep -q "re-opened" "$RP/log.md" \
    || { echo "FAIL: re-open log line not appended"; rm -rf "$TMPF"; exit 1; }
  PATH=/usr/bin:$PATH grep -qF "$nonce" "$RP/log.md" \
    && { echo "FAIL: nonce appeared in log.md (must never appear)"; rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: remove the baseline-recovery block in run-reopen.sh so the pointer
  # always gets baseline:null. Then bl_type = "null" and the type assertion fails.
expected: exit 0; stdout "PASS"; accounting.status="pending"; pointer baseline is an object with session_id="sess-A"; nonce in stdout; nonce absent from log.md
