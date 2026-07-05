name: account-tokens AC 9 — output_total confidence is always "estimated"
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  mkdir -p "$RP"
  printf '%s\n' '{"critic_loops":{"mage":1}}' > "$RP/state.json"
  # A fully-exact run (final:true present, spawn matched) — output must STILL be
  # "estimated", never "exact" (large file writes bill as cache, not output).
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-m1","at":"2026-07-05T00:01:00Z","turns":2,"tokens":{"input":1,"cache_creation":1,"cache_read":1,"processed":500,"output":40}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"s1","at":"2026-07-05T00:02:00Z","turns":5,"tokens":{"input":1,"cache_creation":1,"cache_read":1,"processed":100,"output":10},"final":true}' \
    > "$RP/log.md"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out" | jq -e '
    .tokens.output_total.confidence == "estimated" and
    .tokens.processed_total.confidence == "exact"
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: label output "exact" alongside processed_total and the assertion fails.
expected: exit 0; stdout "PASS"; output_total.confidence="estimated" even though processed_total is "exact"
phase: 04 · feature
owner: Prompt 4 / account-tokens.sh AC 9 output estimated
