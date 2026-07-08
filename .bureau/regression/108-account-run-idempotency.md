name: account-run — idempotency: two runs on same dir both succeed, accounting.json is a JSON object
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/02-idempotent"
  mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":["analyst"],"critic_loops":{"analyst":1}}' > "$RP/state.json"
  printf '%s\n' \
    '# log' \
    '' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"started"}' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"complete"}' \
    > "$RP/log.md"
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e 'type == "object"' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; both invocations exit 0; accounting.json is a JSON object after second run
phase: 01 · execute-plan
owner: Prompt 01 / account-run base-engine battle-test
