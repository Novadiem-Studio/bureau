name: preflight --phase final flags a terminal SPAWN-EVENT with no matching status:started (orphan terminal silently dropped from specialist_spawns[])
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RD="$TMPF/run"
  mkdir -p "$RD"
  echo '{"workflow":"execute-plan"}' > "$RD/state.json"
  : > "$RD/spec.md"; : > "$RD/plan.md"; : > "$RD/prompts.md"
  # A properly paired specialist, an orphan terminal (the defect), and a
  # conductor leg that starts and never terminates (legitimate — excluded).
  {
    printf 'SPAWN-EVENT: %s\n' '{"role":"conductor","agent":"The Conductor","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"conductor-bootstrap-1","status":"started","at":"2026-09-10T06:20:33Z"}'
    printf 'SPAWN-EVENT: %s\n' '{"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"started","at":"2026-09-10T06:23:45Z"}'
    printf 'SPAWN-EVENT: %s\n' '{"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"complete","at":"2026-09-10T07:03:13Z"}'
    printf 'SPAWN-EVENT: %s\n' '{"role":"systemsmith","agent":"The Systemsmith","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"systemsmith-c2-2","status":"complete","at":"2026-09-10T15:12:00Z"}'
  } > "$RD/log.md"

  out=$(bash "$ROOT/scripts/preflight-artifacts.sh" "$RD" --phase final 2>&1)

  # Exactly one spawn-pairing defect, naming the orphan.
  n=$(printf '%s\n' "$out" | grep -c 'spawn-pairing')
  [ "$n" = "1" ] || { echo "FAIL: expected 1 spawn-pairing defect, got $n"; rm -rf "$TMPF"; exit 1; }
  printf '%s\n' "$out" | grep -q "systemsmith-c2-2" \
    || { echo "FAIL: orphan attempt_id not named"; rm -rf "$TMPF"; exit 1; }
  # The conductor leg starts and never ends — must NOT be reported.
  printf '%s\n' "$out" | grep 'spawn-pairing' | grep -q 'conductor' \
    && { echo "FAIL: conductor leg wrongly flagged"; rm -rf "$TMPF"; exit 1; }
  # The properly paired specialist must NOT be reported.
  printf '%s\n' "$out" | grep 'spawn-pairing' | grep -q 'architect-1' \
    && { echo "FAIL: paired spawn wrongly flagged"; rm -rf "$TMPF"; exit 1; }

  # Negative control: remove the orphan line, gate goes quiet on spawn-pairing.
  grep -v 'systemsmith-c2-2' "$RD/log.md" > "$RD/log.clean" && mv "$RD/log.clean" "$RD/log.md"
  out2=$(bash "$ROOT/scripts/preflight-artifacts.sh" "$RD" --phase final 2>&1)
  n2=$(printf '%s\n' "$out2" | grep -c 'spawn-pairing')
  [ "$n2" = "0" ] || { echo "FAIL: clean log still reports $n2 spawn-pairing defects"; rm -rf "$TMPF"; exit 1; }

  # round1 does not run this check (it fires at close-out, after the build tail).
  printf 'SPAWN-EVENT: %s\n' '{"role":"systemsmith","agent":"The Systemsmith","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"systemsmith-c2-2","status":"complete","at":"2026-09-10T15:12:00Z"}' >> "$RD/log.md"
  out3=$(bash "$ROOT/scripts/preflight-artifacts.sh" "$RD" --phase round1 2>&1)
  printf '%s\n' "$out3" | grep -q 'spawn-pairing' \
    && { echo "FAIL: round1 should not run the spawn-pairing check"; rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo PASS
expected: exit 0; stdout "PASS". A terminal SPAWN-EVENT whose attempt_id never had a status:started is reported once as a spawn-pairing defect at --phase final; a conductor start-with-no-terminal and a correctly paired specialist are not reported; removing the orphan silences the check; --phase round1 does not run it. Mutation: delete the check_spawn_pairing call (or its add_defect line) in scripts/preflight-artifacts.sh → the first assertion sees 0 defects and fails.
phase: eval follow-up — 2026-09-12 eight-run eval
owner: docs/evaluation/framework-evaluation-log.md § 2026-09-12 eight-run eval (open lever 2a, SPAWN-EVENT pairing); issue #26
