name: account-tokens F3 (audit) — an event whose `processed` disagrees with input+cache_creation+cache_read is not trusted verbatim: the discrepancy is surfaced with a _note, and a legit identity-consistent run stays note-free
retired: 07 · execute-plan — FR4 REPLACE retired this live-rail token-rollup assertion; post-hoc aggregation is the sole per-leg source
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)

  # --- Case 1: a SPAWN-TOKEN-EVENT with an INFLATED processed --------------------
  # components 200+300+500 = 1000, but the line states processed: 9999. Before the
  # ingest-normalization the consumer trusted 9999 verbatim with no trace. Now the
  # normalization pass DERIVES processed authoritatively from the components at
  # ingest: the component sum (1000) REPLACES the stated 9999, and the disagreement
  # is surfaced as a _note — processed_total carries a _note naming the mismatch and
  # a top-level _notes breadcrumb records it. So processed_total.value is the DERIVED
  # 1000 (+ conductor 100 = 1100), NOT the inflated 9999: the component sum is
  # authoritative, the stated number is neither trusted nor summed verbatim.
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
    ((._notes // []) | join(" ") | test("disagrees with input")) and
    # The summed value is the DERIVED component sum (spec 200+300+500=1000 + conductor
    # 100 = 1100), NOT the inflated stated 9999 (which would give 9999+100=10099).
    (.tokens.processed_total.value == 1100)
  ' > /dev/null || { echo "FAIL: identity mismatch not surfaced or stated 9999 summed instead of derived 1000"; rm -rf "$TMPF"; exit 1; }

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
  # Mutation note: (a) remove the F3 $processed_identity_note computation (or the arm
  # that folds it into $pt_notes / $extra_notes) → Case 1's mismatch is no longer
  # surfaced (processed_total._note lacks the "disagrees with input..." text and
  # _notes has no breadcrumb) → Case 1 fails. (b) revert the ingest derivation (read
  # the stated .processed instead of deriving from components) → Case 1's inflated
  # 9999 is summed verbatim → processed_total.value == 10099, not 1100 → Case 1
  # fails. Case 2 guards the reverse: a legit identity-consistent run must NOT gain
  # the note (no false-fire) and its total stays exact.
expected: exit 0; stdout "PASS"; Case 1 (inflated processed) DERIVES the component sum (1000) in place of the stated 9999 — processed_total.value == 1100 (spec 1000 + conductor 100) — and surfaces the identity mismatch via processed_total._note + a top-level _notes breadcrumb; Case 2 (identity-consistent) stays note-free with processed_total.confidence exact
phase: 04 · feature
owner: account-tokens.sh per-event processed re-derivation / identity check (audit F3)
