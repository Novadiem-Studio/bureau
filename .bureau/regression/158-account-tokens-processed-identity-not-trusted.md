name: account-tokens F3 (audit) — an event whose `processed` disagrees with input+cache_creation+cache_read is not trusted verbatim: the discrepancy is surfaced with a _note, and a legit identity-consistent run stays note-free
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)

  # --- Case 1: a SPAWN-TOKEN-EVENT with an INFLATED processed --------------------
  # components 200+300+500 = 1000, but the line states processed: 9999. Before F3
  # the consumer trusted 9999 verbatim with no trace. After F3 the mismatch is
  # surfaced: processed_total carries a _note naming the disagreement (the stated
  # number is not blessed as a trustworthy verbatim value), and a top-level _notes
  # breadcrumb records it. (The number itself is still summed — the fix closes
  # "trust the field silently", it does not silently rewrite totals.)
  RP="$TMPF/bad"; mkdir -p "$RP"
  printf '%s\n' '{"critic_loops":{"mage":1}}' > "$RP/state.json"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-11T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-11T00:01:00Z","started_at":"2026-07-11T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-legit","at":"2026-07-11T00:01:00Z","turns":2,"tokens":{"input":200,"cache_creation":300,"cache_read":500,"processed":9999,"output":5}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"c1","at":"2026-07-11T00:02:00Z","turns":5,"tokens":{"input":40,"cache_creation":30,"cache_read":30,"processed":100,"output":2},"final":true}' \
    > "$RP/log.md"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out" | jq -e '
    (.tokens.processed_total._note | test("disagrees with input\\+cache_creation\\+cache_read")) and
    ((._notes // []) | join(" ") | test("disagrees with input"))
  ' > /dev/null || { echo "FAIL: identity mismatch not surfaced"; rm -rf "$TMPF"; exit 1; }

  # --- Case 2: a legit identity-consistent run adds NO identity _note ------------
  # processed == input+cache_creation+cache_read for every event → F3 never fires.
  CP="$TMPF/ok"; mkdir -p "$CP"
  printf '%s\n' '{"critic_loops":{"mage":1}}' > "$CP/state.json"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-11T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-11T00:01:00Z","started_at":"2026-07-11T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-legit","at":"2026-07-11T00:01:00Z","turns":2,"tokens":{"input":200,"cache_creation":300,"cache_read":500,"processed":1000,"output":5}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"c1","at":"2026-07-11T00:02:00Z","turns":5,"tokens":{"input":40,"cache_creation":30,"cache_read":30,"processed":100,"output":2},"final":true}' \
    > "$CP/log.md"
  out2=$(bash "$ROOT/scripts/account-tokens.sh" "$CP") || { rm -rf "$TMPF"; exit 1; }
  # No identity note on either channel; processed_total stays exact.
  echo "$out2" | jq -e '
    ((.tokens.processed_total._note // "") | test("disagrees with input") | not) and
    (((._notes // []) | join(" ")) | test("disagrees with input") | not) and
    (.tokens.processed_total.confidence == "exact")
  ' > /dev/null || { echo "FAIL: identity note false-fired on a clean run"; rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: remove the F3 $processed_identity_note computation (or the arm
  # that folds it into $pt_notes / $extra_notes) → Case 1's mismatch is no longer
  # surfaced (processed_total._note lacks the "disagrees with input..." text and
  # _notes has no breadcrumb) → Case 1 fails. Case 2 guards the reverse: a legit
  # identity-consistent run must NOT gain the note (no false-fire).
expected: exit 0; stdout "PASS"; Case 1 (inflated processed) surfaces the identity mismatch via processed_total._note + a top-level _notes breadcrumb; Case 2 (identity-consistent) stays note-free with processed_total.confidence exact
phase: 04 · feature
owner: account-tokens.sh per-event processed re-derivation / identity check (audit F3)
