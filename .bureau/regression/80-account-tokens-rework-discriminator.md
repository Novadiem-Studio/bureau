name: account-tokens rework discriminator (W5) — attempt:2 without rework:true is NOT rework
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  mkdir -p "$RP"
  printf '%s\n' '{"critic_loops":{"mage":1}}' > "$RP/state.json"
  # mage-2 has attempt:2 but rework:false — the SECOND sequential prompt build,
  # not a redo. An `attempt >= 2` heuristic would wrongly flag it as rework.
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-d11","at":"2026-07-05T00:01:00Z","turns":2,"tokens":{"input":100,"cache_creation":150,"cache_read":250,"processed":500,"output":20}}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":2,"attempt_id":"mage-2","status":"started","at":"2026-07-05T00:01:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":2,"attempt_id":"mage-2","status":"complete","at":"2026-07-05T00:02:00Z","started_at":"2026-07-05T00:01:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-2","agent_id":"agent-d22","at":"2026-07-05T00:02:00Z","turns":3,"tokens":{"input":80,"cache_creation":100,"cache_read":120,"processed":300,"output":15}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-disc","at":"2026-07-05T00:03:00Z","turns":10,"tokens":{"input":50,"cache_creation":60,"cache_read":90,"processed":200,"output":10},"final":true}' \
    > "$RP/log.md"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out" | jq -e '
    .tokens.rework_ratio.value == 0.0 and
    .tokens.rework_ratio.confidence == "exact" and
    .tokens.processed_total.value == 1000
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: switch the numerator to `attempt >= 2` and mage-2 (attempt:2)
  # counts as rework -> rework_ratio = 300/1000 = 0.3, not 0.0 -> fixture fails.
expected: exit 0; stdout "PASS"; rework_ratio.value=0.0 (neither spawn is rework:true), processed_total.value=1000
phase: 04 · feature
owner: Prompt 4 / account-tokens.sh rework discriminator (rework flag, not attempt counter)
