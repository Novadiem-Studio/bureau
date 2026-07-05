name: account-tokens AC 18 — exact-wash guard (no final:true -> partial; add one -> exact)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  mkdir -p "$RP"
  printf '%s\n' '{"critic_loops":{"mage":1}}' > "$RP/state.json"
  # Every spawn matched, but the only conductor line is final:false (mid-run
  # cumulative). conductor_tokens + processed_total must both read "partial".
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-m1","at":"2026-07-05T00:01:00Z","turns":2,"tokens":{"input":1,"cache_creation":1,"cache_read":1,"processed":500,"output":1}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"s1","at":"2026-07-05T00:02:00Z","turns":5,"tokens":{"input":1,"cache_creation":1,"cache_read":1,"processed":100,"output":1},"final":false}' \
    > "$RP/log.md"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out" | jq -e '
    .conductor_tokens.confidence == "partial" and
    (.conductor_tokens._note | test("final-leg-capture-pending")) and
    .tokens.processed_total.confidence == "partial"
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  # Adding one final:true line flips both to "exact".
  printf '%s\n' 'CONDUCTOR-TOKEN-EVENT: {"session_id":"s2","at":"2026-07-05T00:03:00Z","turns":6,"tokens":{"input":1,"cache_creation":1,"cache_read":1,"processed":120,"output":1},"final":true}' >> "$RP/log.md"
  out2=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out2" | jq -e '
    .conductor_tokens.confidence == "exact" and
    .tokens.processed_total.confidence == "exact"
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: label the total exact on a mid-run-only log (drop the final:true
  # gate) and the first assertion fails -> the exact-wash guard is enforced.
expected: exit 0; stdout "PASS"; no-final -> conductor+processed_total "partial" (with final-leg-capture-pending note); adding final:true -> both "exact"
phase: 04 · feature
owner: Prompt 4 / account-tokens.sh AC 18 exact-wash guard
