name: conductor-stop #26a — role:delegate pointer → DELEGATE-TOKEN-EVENT (not CONDUCTOR); a sibling role:conductor pointer still emits CONDUCTOR (AC 8, 9, 10)
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_DIR="$TMPF/active-runs"
  mkdir -p "$BUREAU_POINTER_DIR"

  # Two per-run pointers for the SAME run: the Delegate's role:delegate pointer
  # (key suffix .delegate) and a sibling role:conductor pointer (bare key). Only
  # the Delegate top session's transcript carries the .delegate nonce, so the
  # role branch is exercised by identity, not by mention.
  RUN_D="$TMPF/run"; mkdir -p "$RUN_D"; touch "$RUN_D/log.md"
  echo '{"accounting":{"status":"complete"}}' > "$RUN_D/state.json"
  KEY=$(printf '%s' "$RUN_D" | sed 's#[/.]#-#g')
  NONCE_DEL="nonce-del-aaa"; NONCE_CON="nonce-con-bbb"
  echo '{"run_dir":"'"$RUN_D"'","nonce":"'"$NONCE_DEL"'","written_at":"2026-07-11T00:00:00Z","baseline":null,"role":"delegate"}' \
    > "$BUREAU_POINTER_DIR/${KEY}.delegate"
  echo '{"run_dir":"'"$RUN_D"'","nonce":"'"$NONCE_CON"'","written_at":"2026-07-11T00:00:00Z","baseline":null,"role":"conductor"}' \
    > "$BUREAU_POINTER_DIR/${KEY}"

  # Delegate top transcript: carries ONLY the .delegate nonce + run_dir.
  printf '%s\n' "RUN_DIR: $RUN_D" "Nonce: $NONCE_DEL" \
    '{"type":"assistant","message":{"id":"mD","usage":{"input_tokens":40,"cache_creation_input_tokens":10,"cache_read_input_tokens":5,"output_tokens":4},"content":[{"type":"text"}]}}' \
    > "$TMPF/tDel.jsonl"
  # A separate (conductor) session transcript: carries ONLY the conductor nonce.
  printf '%s\n' "RUN_DIR: $RUN_D" "Nonce: $NONCE_CON" \
    '{"type":"assistant","message":{"id":"mC","usage":{"input_tokens":80,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":6},"content":[{"type":"text"}]}}' \
    > "$TMPF/tCon.jsonl"

  # Fire the Delegate top session's Stop → DELEGATE-TOKEN-EVENT (delta shape).
  echo '{"session_id":"sDel","transcript_path":"'"$TMPF/tDel.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  [ "$?" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  # Fire the conductor session's Stop → CONDUCTOR-TOKEN-EVENT.
  echo '{"session_id":"sCon","transcript_path":"'"$TMPF/tCon.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  [ "$?" = "0" ] || { rm -rf "$TMPF"; exit 1; }

  # Exactly one DELEGATE line (session sDel, delta shape w/ baseline) and exactly
  # one CONDUCTOR line (session sCon) — the Delegate's tokens never land in the
  # conductor bucket, and vice-versa.
  ndel=$(grep -c "^DELEGATE-TOKEN-EVENT:" "$RUN_D/log.md"); [ "$ndel" = "1" ] || { rm -rf "$TMPF"; exit 1; }
  ncon=$(grep -c "^CONDUCTOR-TOKEN-EVENT:" "$RUN_D/log.md"); [ "$ncon" = "1" ] || { rm -rf "$TMPF"; exit 1; }
  pd="$(grep '^DELEGATE-TOKEN-EVENT:' "$RUN_D/log.md" | head -1)"; pd="${pd#DELEGATE-TOKEN-EVENT: }"
  echo "$pd" | jq -e '.session_id == "sDel" and .final == true and (.baseline != null)' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  pc="$(grep '^CONDUCTOR-TOKEN-EVENT:' "$RUN_D/log.md" | head -1)"; pc="${pc#CONDUCTOR-TOKEN-EVENT: }"
  echo "$pc" | jq -e '.session_id == "sCon"' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: remove the `if [ "$role" = "delegate" ]` branch in Step F (always
  # EVENT_PREFIX=CONDUCTOR-TOKEN-EVENT) → the Delegate's line comes out as CONDUCTOR
  # → ndel=0 / ncon=2 → fixture fails. This is the role-branch that keeps the
  # Delegate-manager share in its own bucket.
expected: exit 0; stdout "PASS"; role:delegate pointer emits exactly one DELEGATE-TOKEN-EVENT (session sDel, delta w/ baseline); a sibling role:conductor pointer emits exactly one CONDUCTOR-TOKEN-EVENT (session sCon); neither leaks into the other bucket
phase: 04 · feature
owner: conductor-stop.sh #26a role branch — DELEGATE-TOKEN-EVENT by pointer role
