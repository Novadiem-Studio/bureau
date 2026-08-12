name: account-run.sh — SPAWN-EVENT with canon role + persona-alias attempt_id prefix is captured once (not dropped); a genuine mismatch still fails
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  AR="$ROOT/scripts/account-run.sh"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT

  # ── (a) DRIFT ACCEPTED: role field is canon-correct ("critic"/"designer") but the
  # attempt_id uses the sibling persona/cast naming ("challenger-1"/"cleric-1"). Pre-fix
  # the strict `"${role}-"?*` gate dropped both the started and terminal lines, so the
  # spawn vanished from specialist_spawns[]. Post-fix the alias map accepts the prefix.
  # architect (whose attempt_id matches its own role) is the control that always survived.
  RP="$TMPF/drift"; mkdir -p "$RP"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"critic","agent":"The Challenger","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"challenger-1","status":"started","at":"2026-08-09T10:00:00Z"}' \
    'SPAWN-EVENT: {"role":"critic","agent":"The Challenger","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"challenger-1","status":"complete","at":"2026-08-09T10:05:00Z","started_at":"2026-08-09T10:00:00Z"}' \
    'SPAWN-EVENT: {"role":"designer","agent":"The Cleric","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"cleric-1","status":"started","at":"2026-08-09T10:06:00Z"}' \
    'SPAWN-EVENT: {"role":"designer","agent":"The Cleric","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"cleric-1","status":"complete","at":"2026-08-09T10:08:00Z","started_at":"2026-08-09T10:06:00Z"}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"started","at":"2026-08-09T10:10:00Z"}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"complete","at":"2026-08-09T10:12:00Z","started_at":"2026-08-09T10:10:00Z"}' \
    > "$RP/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["architect","critic","designer"],"phase_status":"complete","critic_loops":{}}' > "$RP/state.json"
  bash "$AR" "$RP" >/dev/null 2>&1 || { echo "FAIL: account-run (drift) non-zero"; exit 1; }
  # critic + designer + architect all present; each captured EXACTLY ONCE (no double-count
  # of the started/terminal pair).
  jq -e '
    ([.specialist_spawns[].role.value] | sort) == ["architect","critic","designer"]
    and ([.specialist_spawns[] | select(.role.value=="critic")]   | length) == 1
    and ([.specialist_spawns[] | select(.role.value=="designer")] | length) == 1
    and (.specialist_spawns[] | select(.role.value=="critic")   | .reported_status.value) == "complete"
    and (.specialist_spawns[] | select(.role.value=="designer") | .reported_status.value) == "complete"
  ' "$RP/accounting.json" > /dev/null || { echo "FAIL: aliased-prefix spawn dropped or double-counted: $(jq -c '[.specialist_spawns[].role.value]' "$RP/accounting.json")"; exit 1; }

  # ── (b) CONTROL: a genuinely mismatched attempt_id ("architect-1" on role:"critic")
  # maps to neither the role nor its alias ("challenger-"), so it STILL fails — the relaxed
  # check has not gone permissive-to-everything.
  RP2="$TMPF/mismatch"; mkdir -p "$RP2"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"critic","agent":"The Challenger","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"started","at":"2026-08-09T10:00:00Z"}' \
    'SPAWN-EVENT: {"role":"critic","agent":"The Challenger","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"complete","at":"2026-08-09T10:05:00Z","started_at":"2026-08-09T10:00:00Z"}' \
    > "$RP2/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["critic"],"phase_status":"complete","critic_loops":{}}' > "$RP2/state.json"
  bash "$AR" "$RP2" >/dev/null 2>&1 || { echo "FAIL: account-run (mismatch) non-zero"; exit 1; }
  jq -e '
    (.specialist_spawns | length) == 0
    and (._specialist_spawns_note | test("architect-1"))
    and (._specialist_spawns_note | test("not prefixed by role"))
  ' "$RP2/accounting.json" > /dev/null || { echo "FAIL: genuine mismatch wrongly captured or note missing: $(jq -c '{n:(.specialist_spawns|length),note:._specialist_spawns_note}' "$RP2/accounting.json")"; exit 1; }

  echo "PASS"
  # Mutation note: restore the strict single-arm gate in scripts/account-run.sh §6 —
  #   case "$attempt_id" in "${role}-"?*) : ;; *) ...skip... ;; esac
  # (i.e. drop the role_alias() alternate-prefix arm) → the critic/designer spawns whose
  # attempt_id is "challenger-1"/"cleric-1" are dropped again → (a) fails. The control (b)
  # is unaffected by the mutation (it fails both pre- and post-fix), so it guards against
  # an over-broad relaxation, not the mutation itself.
expected: exit 0; stdout "PASS"; a SPAWN-EVENT pair with role:"critic"+attempt_id:"challenger-1" (and role:"designer"+"cleric-1") is captured exactly once in specialist_spawns[] (persona/cast alias prefix accepted), while a genuine mismatch role:"critic"+attempt_id:"architect-1" still fails with a clear note.
phase: bug-fix · framework-instrumentation-fixes
owner: Bug 3 / scripts/account-run.sh §6 role-prefix gate + role_alias() persona↔cast map
