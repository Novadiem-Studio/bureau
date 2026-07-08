name: account-run — terminal before started: two-pass ordering resolves complete correctly
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  # CRITICAL: two-pass ordering — terminal before started must still resolve complete
  TMPF=$(mktemp -d)
  RP="$TMPF/10-terminal-before-started"
  mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{}}' > "$RP/state.json"
  printf '%s\n' \
    '# log' \
    '' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"complete"}' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"started"}' \
    > "$RP/log.md"
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.specialist_spawns | length == 1' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  jq -e '.specialist_spawns[0].role.value == "analyst" and .specialist_spawns[0].reported_status.value == "complete"' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; specialist_spawns length=1, role.value=analyst, reported_status.value=complete (terminal before started resolved by two-pass)
phase: 01 · execute-plan
owner: Prompt 01 / account-run base-engine battle-test
