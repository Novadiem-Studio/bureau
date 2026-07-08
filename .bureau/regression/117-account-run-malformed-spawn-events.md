name: malformed SPAWN-EVENT lines — skip-and-note, not abort (10 malformed cases, 2 valid survivors)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/malformed-spawn"
  mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{}}' > "$RP/state.json"
  {
    printf '# log\n'
    printf '\n'
    printf '(a) not-JSON payload:\n'
    printf 'SPAWN-EVENT: {not valid json}\n'
    printf '(b) missing attempt_id:\n'
    printf 'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"status":"started"}\n'
    printf '(c) wrong attempt type:\n'
    printf 'SPAWN-EVENT: {"role":"challenger","agent":"The Challenger","configured_model":"opus","actual_model":"opus","attempt":"two","attempt_id":"challenger-two","status":"started"}\n'
    printf '(d) attempt_id mismatch:\n'
    printf 'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-99","status":"started"}\n'
    printf '(e) illegal status:\n'
    printf 'SPAWN-EVENT: {"role":"cleric","agent":"The Cleric","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"cleric-1","status":"bogus"}\n'
    printf '(f) duplicate started (two identical started lines for analyst-1):\n'
    printf 'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"started"}\n'
    printf 'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"started"}\n'
    printf '(g) duplicate terminal (one started + two complete for spellwright-1):\n'
    printf 'SPAWN-EVENT: {"role":"spellwright","agent":"The Spellwright","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"spellwright-1","status":"started"}\n'
    printf 'SPAWN-EVENT: {"role":"spellwright","agent":"The Spellwright","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"spellwright-1","status":"complete"}\n'
    printf 'SPAWN-EVENT: {"role":"spellwright","agent":"The Spellwright","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"spellwright-1","status":"complete"}\n'
    printf '(h) orphan terminal (complete for backend-1 with no started):\n'
    printf 'SPAWN-EVENT: {"role":"backend","agent":"The Systemsmith","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"backend-1","status":"complete"}\n'
    printf '(i) valid-JSON non-objects:\n'
    printf 'SPAWN-EVENT: null\n'
    printf 'SPAWN-EVENT: false\n'
    printf 'SPAWN-EVENT: 0\n'
    printf 'SPAWN-EVENT: ""\n'
    printf 'SPAWN-EVENT: []\n'
    printf '(j) empty/whitespace/multi:\n'
    printf 'SPAWN-EVENT:\n'
    printf 'SPAWN-EVENT:    \n'
    printf 'SPAWN-EVENT: {} {}\n'
    printf 'ONE valid event (analyst-1 complete to pair with the kept started):\n'
    printf 'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"complete"}\n'
  } > "$RP/log.md"
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.specialist_spawns | length == 3' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  jq -e '([.specialist_spawns[].role.value] | sort) == ["analyst","mage","spellwright"]' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  jq -e '[.specialist_spawns[] | select(.role.value == "mage")][0].reported_status.value == "started"' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  jq -e '._specialist_spawns_note | length > 0' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  jq -e '._specialist_spawns_note | test("duplicate terminal for spellwright-1")' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; specialist_spawns length==3 (mage orphan-started + analyst complete + spellwright complete); roles sorted==["analyst","mage","spellwright"]; mage reported_status=="started"; _specialist_spawns_note non-empty and contains "duplicate terminal for spellwright-1"
phase: 02 · execute-plan
owner: Prompt 02 / account-run base-engine battle-test (multi-sub-case)
