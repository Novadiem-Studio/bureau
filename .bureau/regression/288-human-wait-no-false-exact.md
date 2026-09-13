name: human_wait_total_s never reports 0/"exact" when no checkpoint entries were recorded (jq `all` is true on an empty array)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  # Case A — a run with ZERO recorded checkpoints. Before the fix, jq's `all` on the
  # empty $cps array returned true, so hw_conf resolved to "exact" and the file
  # claimed human_wait_total_s: 0 with exact confidence on runs that really did
  # block on a human (S1 212min, S2 100min, devweb 3 gates).
  NOCP="$TMPF/nocp"
  mkdir -p "$NOCP"
  echo '{"accounting":{"status":"complete"},"checkpoints":[]}' > "$NOCP/state.json"
  printf 'SPAWN-EVENT: %s\n' '{"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"started","at":"2026-09-09T14:00:00Z"}' > "$NOCP/log.md"
  printf 'SPAWN-EVENT: %s\n' '{"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"complete","at":"2026-09-09T14:30:00Z"}' >> "$NOCP/log.md"
  a=$(bash "$ROOT/scripts/account-tokens.sh" "$NOCP" 2>/dev/null)
  [ $? -eq 0 ] || { rm -rf "$TMPF"; exit 1; }
  # The guarantee: not "exact", and not a bare 0 masquerading as a measurement.
  printf '%s' "$a" | jq -e '.checkpoints.human_wait_total_s.confidence == "unavailable"' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  printf '%s' "$a" | jq -e '.checkpoints.human_wait_total_s.confidence != "exact"' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  printf '%s' "$a" | jq -e '.checkpoints.human_wait_total_s.value == null' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  printf '%s' "$a" | jq -e '.checkpoints.human_wait_total_s._note | test("UNMEASURED, not zero")' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  # Case B — a run with one RAISED BUT UNRESOLVED checkpoint stays "partial",
  # not "unavailable": the distinction between "none recorded" and "recorded but
  # open" must survive the fix.
  OPENCP="$TMPF/opencp"
  mkdir -p "$OPENCP"
  echo '{"accounting":{"status":"complete"},"checkpoints":[]}' > "$OPENCP/state.json"
  printf 'CHECKPOINT-EVENT: %s\n' '{"id":"01","status":"raised","at":"2026-09-09T15:00:00Z"}' > "$OPENCP/log.md"
  b=$(bash "$ROOT/scripts/account-tokens.sh" "$OPENCP" 2>/dev/null)
  [ $? -eq 0 ] || { rm -rf "$TMPF"; exit 1; }
  printf '%s' "$b" | jq -e '.checkpoints.human_wait_total_s.confidence != "exact"' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo PASS
expected: exit 0; stdout "PASS". Case A (zero checkpoint entries): human_wait_total_s.confidence=="unavailable", value==null, _note names it UNMEASURED. Case B (one raised-unresolved checkpoint): confidence != "exact". Mutation: revert the $cp_none_recorded guard in scripts/account-tokens.sh so hw_conf is `if $cp_all_resolved then "exact" else "partial"` — jq's `all` returns true on the empty array, hw_conf becomes "exact", and Case A's first assertion fails.
phase: eval follow-up — 2026-09-12 eight-run eval
owner: docs/evaluation/framework-evaluation-log.md § 2026-09-12 eight-run eval (open lever 2, honesty labels); issue #22
