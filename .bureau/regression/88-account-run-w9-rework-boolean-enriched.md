name: account-run W9 — rework boolean from spawn_tokens lands in specialist_spawns[] via the role+attempt pairing key
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/run-w9"
  mkdir -p "$RP"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-05T00:00:00Z","rework":true}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-zzz","at":"2026-07-05T00:01:00Z","turns":3,"tokens":{"input":100,"cache_creation":150,"cache_read":250,"processed":500,"output":20}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-w9","at":"2026-07-05T00:02:00Z","turns":5,"tokens":{"input":50,"cache_creation":60,"cache_read":90,"processed":200,"output":10},"final":true}' \
    > "$RP/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["mage"],"phase_status":"complete","critic_loops":{"mage":0}}' > "$RP/state.json"
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq empty "$RP/accounting.json" 2>/dev/null || { rm -rf "$TMPF"; exit 1; }
  jq -e '
    .specialist_spawns[0].rework == true and
    .tokens.processed_total.value == 700 and
    .tokens.processed_total.confidence == "exact"
  ' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: if the pairing key used attempt_id.value (null in specialist_spawns[])
  # instead of role.value+"-"+attempt.value, the enrichment skips every entry and
  # specialist_spawns[0].rework is absent/false — this fixture fails.
expected: exit 0; stdout "PASS"; specialist_spawns[0].rework==true; tokens.processed_total.value==700 confidence==exact
phase: 05 · feature
owner: Prompt 5 / account-run.sh specialist_spawns enrichment (W9)
