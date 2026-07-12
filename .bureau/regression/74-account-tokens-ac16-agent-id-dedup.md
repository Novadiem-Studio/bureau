name: account-tokens AC 16 — double SubagentStop fire deduped by agent_id (take-max, not degrade)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  mkdir -p "$RP"
  printf '%s\n' '{"critic_loops":{"mage":1}}' > "$RP/state.json"
  # Two SPAWN-TOKEN-EVENT lines share agent_id "agent-dup" (processed 400, 700):
  # a double SubagentStop fire. Take-max -> 700 once (not 1100). Conductor
  # final:true present + spawn matched -> total stays exact. Components are
  # identity-consistent (processed = input+cache_creation+cache_read) so the
  # ingest-derivation is a no-op and the asserted totals stay meaningful.
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-dup","at":"2026-07-05T00:01:00Z","turns":2,"tokens":{"input":100,"cache_creation":150,"cache_read":150,"processed":400,"output":1}}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-dup","at":"2026-07-05T00:01:05Z","turns":3,"tokens":{"input":200,"cache_creation":200,"cache_read":300,"processed":700,"output":2}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"s1","at":"2026-07-05T00:03:00Z","turns":5,"tokens":{"input":40,"cache_creation":30,"cache_read":30,"processed":100,"output":1},"final":true}' \
    > "$RP/log.md"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out" | jq -e '
    .tokens.processed_total.value == 800 and
    .tokens.processed_total.confidence == "exact"
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: remove the group_by(.agent_id)|max_by dedup and the dup counts twice
  # -> processed_total 1100+100=1200, not 800 -> fixture fails.
expected: exit 0; stdout "PASS"; processed_total=800 (700 take-max + 100 conductor), confidence exact
phase: 04 · feature
owner: Prompt 4 / account-tokens.sh AC 16 agent_id dedup
