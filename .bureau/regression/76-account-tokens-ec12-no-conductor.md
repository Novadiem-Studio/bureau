name: account-tokens EC 12 — no CONDUCTOR-TOKEN-EVENT at all (conductor unavailable, total partial)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  mkdir -p "$RP"
  printf '%s\n' '{"critic_loops":{"mage":1}}' > "$RP/state.json"
  # Complete matched spawn set; zero conductor lines.
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-m1","at":"2026-07-05T00:01:00Z","turns":2,"tokens":{"input":1,"cache_creation":1,"cache_read":1,"processed":500,"output":1}}' \
    > "$RP/log.md"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out" | jq -e '
    .conductor_tokens.confidence == "unavailable" and
    .conductor_tokens.legs == 0 and
    .tokens.processed_total.confidence == "partial" and
    (.tokens.processed_total._note | test("conductor-share-pending"))
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: default an absent conductor share to "exact" and the assertions fail.
expected: exit 0; stdout "PASS"; conductor_tokens.confidence="unavailable", processed_total.confidence="partial" with conductor-share-pending note
phase: 04 · feature
owner: Prompt 4 / account-tokens.sh EC 12 no conductor
