name: re-open cross-session safety — conductor-stop.sh EC-4 re-records fresh baseline when pointer baseline.session_id differs (pre-existing guard, pinned here)
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
phase: 05 · conductor-capture-lifecycle (Lever 2)
owner: scripts/conductor-stop.sh — Step E.5 EC-4 branch (session mismatch → fresh baseline)
# NOTE: this guard pre-existed run-reopen.sh. It is already pinned by fixture 95
# (delta-baseline-ec4-session-resume.md). This fixture pins the same invariant in the
# context of the re-open scenario: a recovered baseline from a prior session gets a fresh
# re-record when a new session fires against it. Behavioral proof is identical to fix 95;
# this fixture exists to keep the invariant visible in the run-reopen context.
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/ptr"
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  printf '%s\n' '{"accounting":{"status":"pending"}}' > "$RUN_PATH/state.json"
  NONCE="nonce-fixture-reopen-e2e"
  # Simulate the state after run-reopen.sh: pointer carries a baseline from
  # "old-session" (the planning phase session), but a NEW session is now firing.
  # Note: no project_dir in pointer (legacy bypass for C.0 gate, same as fixture 95).
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-07-16T19:52:49Z","baseline":{"session_id":"old-session","input":0,"cache_creation":0,"cache_read":0,"processed":0,"output":0,"turns":0}}\n' \
    "$RUN_PATH" "$NONCE" > "$BUREAU_POINTER_FILE"
  # Fake transcript with nonce + run_dir (ownership select) and some usage.
  printf '%s\n' \
    '{"type":"user","message":{"role":"user","content":"'"$NONCE"' RUN_DIR: '"$RUN_PATH"'"}}' \
    '{"type":"assistant","message":{"id":"msg-build-1","usage":{"input_tokens":50000,"cache_creation_input_tokens":10000,"cache_read_input_tokens":90000,"output_tokens":5000},"content":[{"type":"text","text":"ok"}]}}' \
    > "$TMPF/t.jsonl"
  printf '%s\n' '{"session_id":"new-session","transcript_path":"'"$TMPF/t.jsonl"'","stop_hook_active":false}' \
    | BUREAU_ACCOUNT_RUN_SH="$TMPF/noop.sh" bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  # Provide a no-op account-run.sh shim
  printf '#!/bin/sh\nexit 0\n' > "$TMPF/noop.sh" && chmod +x "$TMPF/noop.sh"
  # Re-run with the shim in place
  printf '%s\n' '{"session_id":"new-session","transcript_path":"'"$TMPF/t.jsonl"'","stop_hook_active":false}' \
    | BUREAU_ACCOUNT_RUN_SH="$TMPF/noop.sh" bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  # After EC-4 re-record, pointer.baseline.session_id must be "new-session"
  bl_sid=$(jq -r '.baseline.session_id // ""' "$BUREAU_POINTER_FILE" 2>/dev/null)
  [ "$bl_sid" = "new-session" ] \
    || { echo "FAIL: pointer baseline.session_id = $bl_sid (expected new-session after EC-4 re-record)"; rm -rf "$TMPF"; exit 1; }
  # And a CONDUCTOR-TOKEN-EVENT must have been appended to the log
  PATH=/usr/bin:$PATH grep -q '^CONDUCTOR-TOKEN-EVENT:' "$RUN_PATH/log.md" \
    || { echo "FAIL: no CONDUCTOR-TOKEN-EVENT appended"; rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: remove the EC-4 else branch in conductor-stop.sh (lines 400-413).
  # Then the pointer baseline stays "old-session" and bl_sid assertion fails.
  # (This guard already existed; fixture 95 is the primary pin. This is a secondary
  # pin in the re-open context.)
expected: exit 0; stdout "PASS"; pointer baseline.session_id = "new-session" after EC-4 re-record on mismatched session
