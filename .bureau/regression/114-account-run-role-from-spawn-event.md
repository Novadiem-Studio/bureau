name: account-run — role attribution from SPAWN-EVENT: 1 spawn, role=analyst, reported_status=complete
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/08-spawn-events"
  mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{}}' > "$RP/state.json"
  printf '%s\n' \
    '{' \
    '  "resolvedAt": "2026-06-20T00:00:00Z",' \
    '  "roles": {' \
    '    "analyst":    {"role":"analyst","agent":"Analizer 2000","model":"sonnet","tier":"sonnet"},' \
    '    "architect":  {"role":"architect","agent":"The Architect","model":"opus","tier":"opus"},' \
    '    "challenger": {"role":"challenger","agent":"The Challenger","model":"opus","tier":"opus"},' \
    '    "spellwright":{"role":"spellwright","agent":"The Spellwright","model":"opus","tier":"opus"},' \
    '    "mage":       {"role":"mage","agent":"The Mage","model":"sonnet","tier":"sonnet"},' \
    '    "backend":    {"role":"backend","agent":"The Systemsmith","model":"sonnet","tier":"sonnet"}' \
    '  }' \
    '}' \
    > "$RP/model-routing.json"
  printf '%s\n' \
    '# log' \
    '' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"started"}' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"complete"}' \
    > "$RP/log.md"
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.specialist_spawns | length == 1' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  jq -e '.specialist_spawns[0].role.value == "analyst" and .specialist_spawns[0].reported_status.value == "complete"' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; specialist_spawns length=1, specialist_spawns[0].role.value=analyst, reported_status.value=complete
phase: 01 · execute-plan
owner: Prompt 01 / account-run base-engine battle-test
