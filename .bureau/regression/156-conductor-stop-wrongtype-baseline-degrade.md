name: conductor-stop wrong-TYPE baseline object — a same-session pointer baseline with a non-number numeric field self-heals (re-records a clean baseline) and emits a correct event, instead of stranding accounting (audit F5)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/ptr"
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"pending"}}' > "$RUN_PATH/state.json"
  NONCE="nonce-fixture-f5-wrongtype"
  # A pointer baseline object tagged with THIS session (sess-F5) — so it would take
  # the same-session reuse path — but whose `input` is a STRING, not a number. It
  # is valid JSON and an object, so it passes the `baseline | type == "object"`
  # state gate. Under the bug the reuse branch read `.input // 0` = "oops"; the
  # shared compute_delta_line then got `--argjson b_input "oops"` (invalid JSON)
  # → compose failed → event_line empty → the WARNING/skip path → ZERO events and
  # the corrupt baseline LEFT INTACT in the pointer (permanent accounting loss).
  # Under the fix the numeric-field type-check rejects it → the EC-4 re-record
  # branch rewrites a CLEAN baseline (self-heal) and emits a correct event.
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-01-01T00:00:00Z","baseline":{"session_id":"sess-F5","input":"oops","cache_creation":2,"cache_read":3,"processed":6,"output":4,"turns":5}}\n' "$RUN_PATH" "$NONCE" > "$BUREAU_POINTER_FILE"
  printf '%s\n' "RUN_DIR: $RUN_PATH" "NONCE: $NONCE" > "$TMPF/t.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"msg-F5","usage":{"input_tokens":3000000,"cache_creation_input_tokens":1000000,"cache_read_input_tokens":1000000,"output_tokens":50000},"content":[{"type":"text"}]}}' >> "$TMPF/t.jsonl"
  echo '{"session_id":"sess-F5","transcript_path":"'"$TMPF/t.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }

  # Exactly one CONDUCTOR-TOKEN-EVENT — not stranded.
  cond_n=$(grep -c "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" 2>/dev/null); cond_n=${cond_n:-0}
  [ "$cond_n" = "1" ] || { rm -rf "$TMPF"; exit 1; }

  event=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  payload="${event#CONDUCTOR-TOKEN-EVENT: }"
  # Re-recorded baseline == current cumulative → delta near-zero; the emitted
  # baseline object carries the cumulative processed (5000000).
  echo "$payload" | jq -e '
    .tokens.processed >= 0 and .tokens.processed < 5000000 and
    (.baseline.processed == 5000000)
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # Self-heal: the corrupt baseline in the pointer was rewritten to clean numeric
  # JSON keyed to this session — no string field survives.
  jq -e '
    (.baseline.session_id == "sess-F5") and
    ((.baseline.input | type) == "number") and
    (.baseline.input == 3000000) and
    (.baseline.processed == 5000000)
  ' "$BUREAU_POINTER_FILE" > /dev/null || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: the load-bearing guard is the `$_bl_numeric_ok`
  # (`map(numbers) | length == 6`) type-check gating the same-session reuse
  # branch. Remove it (revert to reuse whenever `_bl_sid == session_id`) and the
  # wrong-type baseline is reused: `.input // 0` = "oops" → compute_delta_line's
  # `--argjson b_input "oops"` is invalid JSON → event_line empty → skip path →
  # cond_n == 0 AND the pointer baseline still carries the "oops" string → both
  # the "exactly one event" and the self-heal assertions fail.
expected: exit 0; stdout "PASS"; a same-session wrong-type pointer baseline is rejected and re-recorded clean (self-heal), exactly one CONDUCTOR-TOKEN-EVENT with baseline.processed=5000000, pointer baseline rewritten to numeric JSON, no crash
phase: 03 · feature (execute build tail)
owner: conductor-stop.sh wrong-type baseline self-heal (audit F5)
