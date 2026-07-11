name: conductor-stop #25 — concurrent per-run pointers, no clobber; A's Stop selects A's pointer while B's is present; non-bureau transcript selects nothing (AC 1, 2)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_DIR="$TMPF/active-runs"
  mkdir -p "$BUREAU_POINTER_DIR"

  # Two overlapping runs A and B with DISTINCT run_dirs + nonces, each with its
  # own per-run pointer file keyed by the munged RUN_DIR (the same munge the
  # Conductor write-side does: every / and . -> -).
  RUN_A="$TMPF/run-A"; mkdir -p "$RUN_A"; touch "$RUN_A/log.md"
  echo '{"accounting":{"status":"pending"}}' > "$RUN_A/state.json"
  RUN_B="$TMPF/run-B"; mkdir -p "$RUN_B"; touch "$RUN_B/log.md"
  echo '{"accounting":{"status":"pending"}}' > "$RUN_B/state.json"
  KEY_A=$(printf '%s' "$RUN_A" | sed 's#[/.]#-#g')
  KEY_B=$(printf '%s' "$RUN_B" | sed 's#[/.]#-#g')
  NONCE_A="nonce-A-111aaa"; NONCE_B="nonce-B-222bbb"
  echo '{"run_dir":"'"$RUN_A"'","nonce":"'"$NONCE_A"'","written_at":"2026-07-11T00:00:00Z"}' > "$BUREAU_POINTER_DIR/$KEY_A"
  echo '{"run_dir":"'"$RUN_B"'","nonce":"'"$NONCE_B"'","written_at":"2026-07-11T00:00:00Z"}' > "$BUREAU_POINTER_DIR/$KEY_B"

  # Each transcript carries ONLY its own run's nonce + run_dir, plus one usage line.
  printf '%s\n' "RUN_DIR: $RUN_A" "Nonce: $NONCE_A" \
    '{"type":"assistant","message":{"id":"mA","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":2},"content":[{"type":"text"}]}}' \
    > "$TMPF/tA.jsonl"
  printf '%s\n' "RUN_DIR: $RUN_B" "Nonce: $NONCE_B" \
    '{"type":"assistant","message":{"id":"mB","usage":{"input_tokens":99,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":9},"content":[{"type":"text"}]}}' \
    > "$TMPF/tB.jsonl"

  # Fire A's Stop hook WHILE B's pointer is present in the directory.
  echo '{"session_id":"sA","transcript_path":"'"$TMPF/tA.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  [ "$?" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  # Fire B's Stop hook (independently).
  echo '{"session_id":"sB","transcript_path":"'"$TMPF/tB.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  [ "$?" = "0" ] || { rm -rf "$TMPF"; exit 1; }

  # A's log got EXACTLY its own event (input 10, session sA), never B's.
  na=$(grep -c "^CONDUCTOR-TOKEN-EVENT:" "$RUN_A/log.md"); [ "$na" = "1" ] || { rm -rf "$TMPF"; exit 1; }
  pa="$(grep '^CONDUCTOR-TOKEN-EVENT:' "$RUN_A/log.md" | head -1)"; pa="${pa#CONDUCTOR-TOKEN-EVENT: }"
  echo "$pa" | jq -e '.session_id == "sA" and .tokens.input == 10' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  # B's log got EXACTLY its own event (input 99, session sB), never A's.
  nb=$(grep -c "^CONDUCTOR-TOKEN-EVENT:" "$RUN_B/log.md"); [ "$nb" = "1" ] || { rm -rf "$TMPF"; exit 1; }
  pb="$(grep '^CONDUCTOR-TOKEN-EVENT:' "$RUN_B/log.md" | head -1)"; pb="${pb#CONDUCTOR-TOKEN-EVENT: }"
  echo "$pb" | jq -e '.session_id == "sB" and .tokens.input == 99' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # Third leg (AC 2): a non-bureau session whose transcript carries NO active
  # nonce selects NOTHING against the populated directory → exit 0, no event.
  printf '%s\n' "random session content, no bureau nonce or run_dir here" > "$TMPF/tX.jsonl"
  echo '{"session_id":"sX","transcript_path":"'"$TMPF/tX.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  [ "$?" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  # No new event appeared in either run's log from the non-bureau fire.
  [ "$(grep -c '^CONDUCTOR-TOKEN-EVENT:' "$RUN_A/log.md")" = "1" ] || { rm -rf "$TMPF"; exit 1; }
  [ "$(grep -c '^CONDUCTOR-TOKEN-EVENT:' "$RUN_B/log.md")" = "1" ] || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: revert the Step A.5/C selector to read a single fixed file
  # (e.g. POINTER_FILE="$BUREAU_POINTER_DIR" or the first candidate unconditionally)
  # → one of the two runs reads the other's pointer, its nonce grep misses, and
  # that run's token event vanishes (na or nb becomes 0) → fixture fails. This is
  # the exact clobber #25 removes.
expected: exit 0; stdout "PASS"; run A captures its own CONDUCTOR-TOKEN-EVENT (input 10, session sA) with B's pointer present; run B captures its own (input 99, session sB); a non-bureau transcript selects nothing and appends nothing
phase: 03 · feature
owner: conductor-stop.sh #25 per-run pointer directory — concurrent no-clobber select
