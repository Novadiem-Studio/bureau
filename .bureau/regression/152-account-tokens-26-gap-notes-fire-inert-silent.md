name: account-tokens #26 — delegate/reviewer gap-notes fire (integrated + gap), inert (no topology), silent (lines present); reviewer gap gated on >=1 resolved checkpoint (AC 16)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"; mkdir -p "$RP"
  echo '{}' > "$RP/state.json"

  # --- Case A: integrated topology + >=1 resolved checkpoint + zero del/rev lines
  #     → BOTH gap notes FIRE. ---
  echo '{"topology":"integrated"}' > "$RP/delegate-state.json"
  printf '%s\n' \
    'CHECKPOINT-EVENT: {"id":"05","status":"raised","at":"2026-07-11T00:00:00Z"}' \
    'CHECKPOINT-EVENT: {"id":"05","status":"resolved","at":"2026-07-11T00:05:00Z","decision":"proceed"}' \
    > "$RP/log.md"
  a=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$a" | jq -e '
    .delegate_tokens.confidence == "unavailable" and
    (.delegate_tokens._note | test("zero DELEGATE-TOKEN-EVENT captured")) and
    .reviewer_tokens.confidence == "unavailable" and
    (.reviewer_tokens._note | test("zero REVIEWER-TOKEN-EVENT captured"))
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # --- Case B: topology absent → both gaps INERT (only the plain block note). ---
  rm -f "$RP/delegate-state.json"
  b=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$b" | jq -e '
    ((.delegate_tokens._note // "") | test("real gap") | not) and
    ((.reviewer_tokens._note // "") | test("real gap") | not)
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # --- Case C: integrated BUT del + rev lines present → both gaps SILENT. ---
  echo '{"topology":"integrated"}' > "$RP/delegate-state.json"
  printf '%s\n' \
    'DELEGATE-TOKEN-EVENT: {"session_id":"d1","at":"2026-07-11T00:02:00Z","turns":1,"tokens":{"input":1,"cache_creation":0,"cache_read":0,"processed":1,"output":1},"final":true}' \
    'REVIEWER-TOKEN-EVENT: {"checkpoint":"05","at":"2026-07-11T00:03:00Z","turns":1,"tokens":{"input":1,"cache_creation":0,"cache_read":0,"processed":1,"output":1},"spawn_id":"05-1"}' \
    >> "$RP/log.md"
  c=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$c" | jq -e '
    .delegate_tokens.confidence == "exact" and
    ((.delegate_tokens._note // "") | test("real gap") | not) and
    .reviewer_tokens.confidence == "exact" and
    ((.reviewer_tokens._note // "") | test("real gap") | not)
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # --- Case D: integrated + delegate missing + NO resolved checkpoint → the
  #     reviewer gap must NOT fire (gated on >=1 resolved checkpoint); the
  #     delegate gap still fires (it is not checkpoint-gated). ---
  echo '{"topology":"integrated"}' > "$RP/delegate-state.json"
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"c1","at":"2026-07-11T00:01:00Z","turns":1,"tokens":{"input":1,"cache_creation":0,"cache_read":0,"processed":1,"output":1},"final":true}' \
    > "$RP/log.md"
  d=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$d" | jq -e '
    (.delegate_tokens._note | test("zero DELEGATE-TOKEN-EVENT captured")) and
    ((.reviewer_tokens._note // "") | test("real gap") | not)
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: drop the ($del_conf == "unavailable") condition on the delegate
  # gap → Case C (lines present) gets the note → its "not" assertion fails. Drop
  # the ($resolved_cp_n > 0) gate on the reviewer gap → Case D (no resolved cp)
  # gets the reviewer note → its "not" assertion fails.
expected: exit 0; stdout "PASS"; delegate/reviewer gap notes fire only when integrated AND their bucket is unavailable (reviewer also needs >=1 resolved checkpoint); inert without topology; silent when lines present
phase: 04 · feature
owner: account-tokens.sh #26 sibling gap-notes (delegate + reviewer)
