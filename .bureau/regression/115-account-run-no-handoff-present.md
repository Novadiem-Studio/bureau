name: account-run — no-handoff terminal: reported_status=no-handoff, actual_model.value=null confidence=unavailable
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/09-no-handoff"
  mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{}}' > "$RP/state.json"
  printf '%s\n' \
    '# log' \
    '' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":null,"attempt":1,"attempt_id":"architect-1","status":"started"}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":null,"attempt":1,"attempt_id":"architect-1","status":"no-handoff"}' \
    > "$RP/log.md"
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.specialist_spawns[0].reported_status.value == "no-handoff" and .specialist_spawns[0].actual_model.value == null and .specialist_spawns[0].actual_model.confidence == "unavailable"' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; specialist_spawns[0].reported_status.value=no-handoff, actual_model.value=null, actual_model.confidence=unavailable
phase: 01 · execute-plan
owner: Prompt 01 / account-run base-engine battle-test
