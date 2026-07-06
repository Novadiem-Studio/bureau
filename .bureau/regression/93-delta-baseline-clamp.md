name: delta-baseline clamp — baseline field exceeds raw → field emits 0 and _note present (AC 4)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/ptr"
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"pending"}}' > "$RUN_PATH/state.json"
  NONCE="nonce-fixture-b-clamp"
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-01-01T00:00:00Z","baseline":{"session_id":"sess-B","input":99999999,"cache_creation":0,"cache_read":0,"output":0,"turns":0,"processed":99999999}}\n' "$RUN_PATH" "$NONCE" > "$BUREAU_POINTER_FILE"
  printf '%s\n' "RUN_DIR: $RUN_PATH" "NONCE: $NONCE" > "$TMPF/t.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"msg-B","usage":{"input_tokens":30000000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":100},"content":[{"type":"text"}]}}' >> "$TMPF/t.jsonl"
  echo '{"session_id":"sess-B","transcript_path":"'"$TMPF/t.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  event=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  [ -n "$event" ] || { rm -rf "$TMPF"; exit 1; }
  payload="${event#CONDUCTOR-TOKEN-EVENT: }"
  echo "$payload" | jq -e '.tokens.input == 0' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  echo "$payload" | jq -e 'has("_note")' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo PASS
expected: exit 0; stdout "PASS"; CONDUCTOR-TOKEN-EVENT with tokens.input==0 (clamped from raw 30000000 - baseline 99999999 = -69999999) and _note key present naming the clamped field. Precondition: baseline.session_id=="sess-B"==hook session_id so same-session path fires (not EC-4 re-record). Mutation guard: remove input clamp → tokens.input==-69999999 → assertion fails.
phase: 03 · feature (execute build tail)
owner: prompts.md § Prompt 3 — Fixture B, delta-baseline clamp (AC 4)
