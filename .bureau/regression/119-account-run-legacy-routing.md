name: account-run — legacy routing: model-tiers.json only (no model-routing.json) yields configured_model confidence=inferred
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/13-legacy-routing"
  mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{}}' > "$RP/state.json"
  printf '%s\n' \
    '{' \
    '  "resolvedAt": "2020-01-01T00:00:00Z",' \
    '  "roles": {' \
    '    "analyst": {"role":"analyst","agent":"Analizer 2000","tier":"sonnet","source":"default","lock":false,"allowed":["sonnet"]}' \
    '  }' \
    '}' \
    > "$RP/model-tiers.json"
  printf '%s\n' \
    '# log' \
    '' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"started"}' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"complete"}' \
    > "$RP/log.md"
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.specialist_spawns[0].configured_model.confidence == "inferred" and .specialist_spawns[0].configured_model.value == "sonnet"' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; specialist_spawns[0].configured_model.confidence=inferred, configured_model.value=sonnet
phase: 01 · execute-plan
owner: Prompt 01 / account-run base-engine battle-test
