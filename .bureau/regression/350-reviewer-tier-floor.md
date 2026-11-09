name: preflight flags any Challenger SPAWN-EVENT on a sub-strong model (sonnet/haiku, or the routing's cheap/standard-only models) on both phases, with no override escape
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RD="$TMPF/run"
  mkdir -p "$RD"
  echo '{"workflow":"execute-plan"}' > "$RD/state.json"
  : > "$RD/spec.md"; : > "$RD/plan.md"; : > "$RD/prompts.md"
  write_log() {
    {
      # (a) quota downgrade with a hand-written reason — still the defect (no escape)
      printf 'SPAWN-EVENT: %s\n' '{"role":"critic","agent":"The Challenger","configured_model":"opus","actual_model":"sonnet","attempt":6,"attempt_id":"challenger-01b","status":"started","at":"2026-10-30T07:58:45Z"}'
      printf 'MODEL-OVERRIDE: %s\n' '{"role":"critic","configured":"opus","actual":"sonnet","reason":"quota budget_pressure; proportionate review of wiring diff","at":"2026-10-30T07:58:45Z"}'
      # (b) cast-key role on haiku — the defect
      printf 'SPAWN-EVENT: %s\n' '{"role":"challenger","agent":"The Challenger","configured_model":"opus","actual_model":"haiku","attempt":1,"attempt_id":"challenger-1","status":"started","at":"2026-10-30T08:00:00Z"}'
      # (c) the terminal line of a sub-strong spawn is not counted twice
      printf 'SPAWN-EVENT: %s\n' '{"role":"challenger","agent":"The Challenger","configured_model":"opus","actual_model":"haiku","attempt":1,"attempt_id":"challenger-1","status":"complete","at":"2026-10-30T08:10:00Z"}'
      # (d) strong and escalated Challengers — silent
      printf 'SPAWN-EVENT: %s\n' '{"role":"challenger","agent":"The Challenger","configured_model":"opus","actual_model":"opus","attempt":2,"attempt_id":"challenger-2","status":"started","at":"2026-10-30T08:20:00Z"}'
      printf 'SPAWN-EVENT: %s\n' '{"role":"challenger","agent":"The Challenger","configured_model":"opus","actual_model":"fable","attempt":3,"attempt_id":"challenger-3","status":"started","at":"2026-10-30T08:30:00Z"}'
      # (e) other roles on sonnet (a downgraded Conductor, a coder, the Spellwright) — silent
      printf 'SPAWN-EVENT: %s\n' '{"role":"conductor","agent":"The Conductor","configured_model":"opus","actual_model":"sonnet","attempt":1,"attempt_id":"conductor-resume-1","status":"started","at":"2026-10-30T07:45:58Z"}'
      printf 'SPAWN-EVENT: %s\n' '{"role":"mage","agent":"The Mage","configured_model":"opus","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-10-30T07:50:00Z"}'
      printf 'SPAWN-EVENT: %s\n' '{"role":"spellwright","agent":"The Spellwright","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"spellwright-1","status":"started","at":"2026-10-30T07:40:00Z"}'
    } > "$RD/log.md"
  }
  write_log

  for ph in final round1; do
    out=$(bash "$ROOT/scripts/preflight-artifacts.sh" "$RD" --phase "$ph" 2>&1)
    n=$(printf '%s\n' "$out" | grep -c 'reviewer-tier-floor')
    [ "$n" = "2" ] || { echo "FAIL ($ph): expected 2 reviewer-tier-floor defects, got $n"; printf '%s\n' "$out"; rm -rf "$TMPF"; exit 1; }
    printf '%s\n' "$out" | grep 'reviewer-tier-floor' | grep -q "'challenger-01b'" \
      || { echo "FAIL ($ph): critic-alias sonnet spawn with a quota override not flagged"; rm -rf "$TMPF"; exit 1; }
    printf '%s\n' "$out" | grep 'reviewer-tier-floor' | grep -q "'challenger-1'" \
      || { echo "FAIL ($ph): haiku Challenger not flagged"; rm -rf "$TMPF"; exit 1; }
    printf '%s\n' "$out" | grep 'reviewer-tier-floor' | grep -Eq "challenger-2|challenger-3|conductor|mage-1|spellwright-1" \
      && { echo "FAIL ($ph): a strong-tier Challenger or a non-reviewer role was flagged"; rm -rf "$TMPF"; exit 1; }
  done

  # Host-neutral: on a Codex routing, gpt-5.6-terra serves only cheap (flagged)
  # and gpt-5.6-sol serves standard AND strong (silent: shared with strong); sonnet is not in the set.
  cat > "$RD/model-routing.json" <<'JSON'
  {"runtime":"openai","tiers":{"cheap":{"model":"gpt-5.6-terra"},"standard":{"model":"gpt-5.6-sol"},"strong":{"model":"gpt-5.6-sol"},"frontier":{"model":"gpt-5.6-sol"},"escalated":{"model":"gpt-6-astra"}}}
  JSON
  printf 'SPAWN-EVENT: %s\n' '{"role":"challenger","agent":"The Challenger","configured_model":"gpt-5.6-sol","actual_model":"gpt-5.6-terra","attempt":4,"attempt_id":"challenger-terra","status":"started","at":"2026-10-30T09:00:00Z"}' >> "$RD/log.md"
  printf 'SPAWN-EVENT: %s\n' '{"role":"challenger","agent":"The Challenger","configured_model":"gpt-5.6-sol","actual_model":"gpt-5.6-sol","attempt":5,"attempt_id":"challenger-sol","status":"started","at":"2026-10-30T09:10:00Z"}' >> "$RD/log.md"
  out2=$(bash "$ROOT/scripts/preflight-artifacts.sh" "$RD" --phase final 2>&1)
  printf '%s\n' "$out2" | grep 'reviewer-tier-floor' | grep -q "challenger-terra" \
    || { echo "FAIL: standard-tier model from model-routing.json not flagged"; printf '%s\n' "$out2"; rm -rf "$TMPF"; exit 1; }
  printf '%s\n' "$out2" | grep 'reviewer-tier-floor' | grep -q "challenger-sol" \
    && { echo "FAIL: strong-tier Codex model wrongly flagged"; rm -rf "$TMPF"; exit 1; }
  printf '%s\n' "$out2" | grep 'reviewer-tier-floor' | grep -q "challenger-01b" \
    && { echo "FAIL: sonnet still treated as sub-strong under a routing that does not name it"; rm -rf "$TMPF"; exit 1; }
  rm -f "$RD/model-routing.json"

  # Negative control: every Challenger on the strong tier; the check goes quiet.
  {
    printf 'SPAWN-EVENT: %s\n' '{"role":"critic","agent":"The Challenger","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"challenger-01b","status":"started","at":"2026-10-30T07:58:45Z"}'
    printf 'SPAWN-EVENT: %s\n' '{"role":"challenger","agent":"The Challenger","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"challenger-1","status":"started","at":"2026-10-30T08:00:00Z"}'
  } > "$RD/log.md"
  out3=$(bash "$ROOT/scripts/preflight-artifacts.sh" "$RD" --phase final 2>&1)
  n3=$(printf '%s\n' "$out3" | grep -c 'reviewer-tier-floor')
  [ "$n3" = "0" ] || { echo "FAIL: strong-tier Challengers still report $n3 defects"; printf '%s\n' "$out3"; rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo PASS
expected: exit 0; stdout "PASS". On both --phase final and --phase round1, every Challenger SPAWN-EVENT (role challenger or the persona-stem alias critic) with status started whose actual_model serves only the cheap/standard tiers (haiku/sonnet with no routing, or whatever RUN_DIR/model-routing.json#tiers names for cheap/standard that does not also serve strong or above) is reported once as a reviewer-tier-floor defect, even when a MODEL-OVERRIDE gives a reason. Strong and escalated Challengers, terminal lines, and other roles on sonnet are not reported. Mutation: delete the check_reviewer_tier_floor call (or its add_defect line) in scripts/preflight-artifacts.sh → the first assertion sees 0 defects and fails; drop the critic alias from the role filter → challenger-01b passes and the count drops to 1; drop the strong-tier subtraction → challenger-sol is flagged.
phase: model policy — the Challenger never runs below strong (issue #133)
owner: scripts/preflight-artifacts.sh check_reviewer_tier_floor; config/model-policy.v2.json roles.challenger
