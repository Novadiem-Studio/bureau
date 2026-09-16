name: preflight --phase final flags a specialist SPAWN-EVENT that ran on the escalation-tier model with no hand-written MODEL-OVERRIDE reason (auto-reconciled does not count)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RD="$TMPF/run"
  mkdir -p "$RD"
  echo '{"workflow":"execute-plan"}' > "$RD/state.json"
  : > "$RD/spec.md"; : > "$RD/plan.md"; : > "$RD/prompts.md"
  write_log() {
    {
      # conductor legs are never specialist spawns — excluded even on fable
      printf 'SPAWN-EVENT: %s\n' '{"role":"conductor","agent":"The Conductor","configured_model":"opus","actual_model":"fable","attempt":1,"attempt_id":"conductor-bootstrap-1","status":"started","at":"2026-09-10T06:20:33Z"}'
      # (a) fable with a hand-written reason — allowed
      printf 'SPAWN-EVENT: %s\n' '{"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"fable","attempt":3,"attempt_id":"architect-3","status":"started","rework":true,"at":"2026-09-10T06:23:45Z"}'
      printf 'MODEL-OVERRIDE: %s\n' '{"role":"architect","attempt_id":"architect-3","configured":"opus","actual":"fable","reason":"bounce rule: second Challenger rejection of the same item; strong -> frontier","at":"2026-09-10T06:23:45Z"}'
      # (b) fable with only the account-run.sh auto line — the defect
      printf 'SPAWN-EVENT: %s\n' '{"role":"systemsmith","agent":"The Systemsmith","configured_model":"opus","actual_model":"fable","attempt":1,"attempt_id":"systemsmith-c2-1","status":"started","at":"2026-09-10T16:44:14Z"}'
      printf 'MODEL-OVERRIDE: %s\n' '{"role":"systemsmith","attempt_id":"systemsmith-c2-1","configured":"opus","actual":"fable","reason":"auto-reconciled from SPAWN-EVENT actual_model; no hand-written override","at":"2026-09-13T05:47:11Z"}'
      # (c) fable with no override at all — the defect
      printf 'SPAWN-EVENT: %s\n' '{"role":"challenger","agent":"The Challenger","configured_model":"opus","actual_model":"fable","attempt":1,"attempt_id":"challenger-1","status":"started","at":"2026-09-10T08:52:57Z"}'
      # (d) routing itself put the role on fable (active experiment) — silent
      printf 'SPAWN-EVENT: %s\n' '{"role":"critic","agent":"The Challenger","configured_model":"fable","actual_model":"fable","attempt":1,"attempt_id":"critic-r1-1","status":"started","at":"2026-09-10T08:52:57Z"}'
      # (e) an ordinary opus spawn and a sonnet reviewer downgrade — silent
      printf 'SPAWN-EVENT: %s\n' '{"role":"systemsmith","agent":"The Systemsmith","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"systemsmith-c1-1","status":"started","at":"2026-09-10T16:16:14Z"}'
      printf 'SPAWN-EVENT: %s\n' '{"role":"challenger","agent":"The Challenger","configured_model":"opus","actual_model":"sonnet","attempt":1,"attempt_id":"challenger-c1-diff","status":"started","at":"2026-09-10T16:28:38Z"}'
      # (f) fable with an override whose reason is blank — the defect
      printf 'SPAWN-EVENT: %s\n' '{"role":"mage","agent":"The Mage","configured_model":"opus","actual_model":"fable","attempt":1,"attempt_id":"mage-c4-1","status":"started","at":"2026-09-10T17:00:00Z"}'
      printf 'MODEL-OVERRIDE: %s\n' '{"role":"mage","attempt_id":"mage-c4-1","configured":"opus","actual":"fable","reason":"   ","at":"2026-09-10T17:00:00Z"}'
    } > "$RD/log.md"
  }
  write_log

  out=$(bash "$ROOT/scripts/preflight-artifacts.sh" "$RD" --phase final 2>&1)

  n=$(printf '%s\n' "$out" | grep -c 'fable-override')
  [ "$n" = "3" ] || { echo "FAIL: expected 3 fable-override defects, got $n"; printf '%s\n' "$out"; rm -rf "$TMPF"; exit 1; }
  printf '%s\n' "$out" | grep 'fable-override' | grep -q "mage-c4-1" \
    || { echo "FAIL: blank-reason override not flagged"; rm -rf "$TMPF"; exit 1; }
  printf '%s\n' "$out" | grep 'fable-override' | grep -q "systemsmith-c2-1" \
    || { echo "FAIL: auto-reconciled-only spawn not flagged"; rm -rf "$TMPF"; exit 1; }
  printf '%s\n' "$out" | grep 'fable-override' | grep -q "'challenger-1'" \
    || { echo "FAIL: override-less spawn not flagged"; rm -rf "$TMPF"; exit 1; }
  printf '%s\n' "$out" | grep 'fable-override' | grep -q "architect-3" \
    && { echo "FAIL: hand-written override wrongly flagged"; rm -rf "$TMPF"; exit 1; }
  printf '%s\n' "$out" | grep 'fable-override' | grep -q "conductor" \
    && { echo "FAIL: conductor leg wrongly flagged"; rm -rf "$TMPF"; exit 1; }
  printf '%s\n' "$out" | grep 'fable-override' | grep -q "critic-r1-1" \
    && { echo "FAIL: configured-fable spawn wrongly flagged"; rm -rf "$TMPF"; exit 1; }
  printf '%s\n' "$out" | grep 'fable-override' | grep -Eq "systemsmith-c1-1|challenger-c1-diff" \
    && { echo "FAIL: non-fable spawn wrongly flagged"; rm -rf "$TMPF"; exit 1; }

  # Host-neutral: with a Codex routing (gpt-5.6-sol serves BOTH strong and frontier,
  # gpt-6-astra is escalated), an Astra spawn is checked, a terra -> sol step is one
  # rung and is NOT treated as an escalation, and a fable spawn is not checked.
  cat > "$RD/model-routing.json" <<'JSON'
  {"runtime":"openai","tiers":{"cheap":{"model":"gpt-5.6-terra"},"standard":{"model":"gpt-5.6-terra"},"strong":{"model":"gpt-5.6-sol"},"frontier":{"model":"gpt-5.6-sol"},"escalated":{"model":"gpt-6-astra"}}}
  JSON
  printf 'SPAWN-EVENT: %s\n' '{"role":"architect","agent":"The Architect","configured_model":"gpt-5.6-sol","actual_model":"gpt-6-astra","attempt":1,"attempt_id":"architect-astra","status":"started","at":"2026-09-10T06:23:45Z"}' >> "$RD/log.md"
  printf 'SPAWN-EVENT: %s\n' '{"role":"analyst","agent":"Analizer 2000","configured_model":"gpt-5.6-terra","actual_model":"gpt-5.6-sol","attempt":1,"attempt_id":"analyst-one-rung","status":"started","at":"2026-09-10T06:23:45Z"}' >> "$RD/log.md"
  out2=$(bash "$ROOT/scripts/preflight-artifacts.sh" "$RD" --phase final 2>&1)
  printf '%s\n' "$out2" | grep 'fable-override' | grep -q "architect-astra" \
    || { echo "FAIL: escalated-tier model from model-routing.json not checked"; printf '%s\n' "$out2"; rm -rf "$TMPF"; exit 1; }
  printf '%s\n' "$out2" | grep 'fable-override' | grep -q "analyst-one-rung" \
    && { echo "FAIL: a model shared with a lower tier was treated as an escalation model"; rm -rf "$TMPF"; exit 1; }
  printf '%s\n' "$out2" | grep 'fable-override' | grep -q "'challenger-1'" \
    && { echo "FAIL: fable still checked when the routing names a different escalation model"; rm -rf "$TMPF"; exit 1; }
  rm -f "$RD/model-routing.json"

  # Negative control: give the three defects a hand-written reason; the check goes quiet.
  write_log
  printf 'MODEL-OVERRIDE: %s\n' '{"role":"mage","attempt_id":"mage-c4-1","configured":"opus","actual":"fable","reason":"bounce rule: second Challenger rejection of chunk 04; strong -> frontier","at":"2026-09-10T17:00:00Z"}' >> "$RD/log.md"
  printf 'MODEL-OVERRIDE: %s\n' '{"role":"systemsmith","attempt_id":"systemsmith-c2-1","configured":"opus","actual":"fable","reason":"Robin asked for fable on the secret-store chunk (kickoff brief 2026-09-09)","at":"2026-09-10T16:44:14Z"}' >> "$RD/log.md"
  printf 'MODEL-OVERRIDE: %s\n' '{"role":"challenger","attempt_id":"challenger-1","configured":"opus","actual":"fable","reason":"human-requested: final gate on fable per Robin","at":"2026-09-10T08:52:57Z"}' >> "$RD/log.md"
  out3=$(bash "$ROOT/scripts/preflight-artifacts.sh" "$RD" --phase final 2>&1)
  n3=$(printf '%s\n' "$out3" | grep -c 'fable-override')
  [ "$n3" = "0" ] || { echo "FAIL: explained spawns still report $n3 fable-override defects"; printf '%s\n' "$out3"; rm -rf "$TMPF"; exit 1; }

  # round1 does not run this check (it fires at close-out).
  write_log
  out4=$(bash "$ROOT/scripts/preflight-artifacts.sh" "$RD" --phase round1 2>&1)
  printf '%s\n' "$out4" | grep -q 'fable-override' \
    && { echo "FAIL: round1 should not run the fable-override check"; rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo PASS
expected: exit 0; stdout "PASS". At --phase final, a specialist SPAWN-EVENT whose actual_model is an escalation-tier model (fable, or whatever RUN_DIR/model-routing.json#tiers names for frontier/escalated that does not also serve cheap/standard/strong) while configured_model differs is reported once as a fable-override defect unless a MODEL-OVERRIDE with the same attempt_id and actual carries a non-blank reason that is not the account-run.sh auto-reconcile text. A hand-written override, a conductor leg, a spawn whose routing already configured fable, and non-escalation spawns are not reported; explaining the defects silences the check; --phase round1 does not run it. Mutation: delete the check_fable_override call (or its add_defect line) in scripts/preflight-artifacts.sh → the first assertion sees 0 defects and fails; delete the startswith("auto-reconciled") exclusion → case (b) passes and the count drops to 2; delete the blank-reason exclusion → case (f) passes and the count drops to 2; drop the lower-tier subtraction from the model set → the terra -> sol spawn is flagged.
phase: model policy — reviewer differs from author (issue #50)
owner: scripts/preflight-artifacts.sh check_fable_override; docs/model-routing-and-cast.md § Escalation ladder
