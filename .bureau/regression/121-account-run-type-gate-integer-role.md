name: account-run — type-gate: SPAWN-EVENT with integer role yields 0 specialist_spawns and non-empty _specialist_spawns_note
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/13c-integer-role"
  mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{}}' > "$RP/state.json"
  printf '%s\n' \
    '# log' \
    '' \
    'SPAWN-EVENT: {"role":1,"agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"1-1","status":"started"}' \
    > "$RP/log.md"
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.specialist_spawns | length == 0' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  jq -e '._specialist_spawns_note | length > 0' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; specialist_spawns length=0, _specialist_spawns_note is non-empty string
phase: 01 · execute-plan
owner: Prompt 01 / account-run base-engine battle-test
