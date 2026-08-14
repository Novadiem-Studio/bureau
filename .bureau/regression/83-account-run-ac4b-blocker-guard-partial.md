name: account-run AC4(b) BLOCKER GUARD — no CONDUCTOR-TOKEN-EVENT → processed_total partial, not exact
retired: 07 · execute-plan — FR4 REPLACE retired this live-rail token-rollup assertion; post-hoc aggregation is the sole per-leg source
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/ac4b"
  mkdir -p "$RP"
  # Same close-out state as AC4(a) but WITHOUT the CONDUCTOR-TOKEN-EVENT — the exact
  # moment before the Stop hook fires. A build that labels this "exact" is broken.
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"architect-1","agent_id":"agent-aaa","at":"2026-07-05T00:01:00Z","turns":5,"tokens":{"input":200,"cache_creation":300,"cache_read":500,"processed":1000,"output":50}}' \
    > "$RP/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["architect"],"phase_status":"complete","critic_loops":{"architect":1}}' > "$RP/state.json"
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  # No final:true → processed_total.confidence MUST be "partial" with a _note naming
  # the pending conductor share, and conductor_tokens.confidence MUST be "unavailable"
  # (no CONDUCTOR-TOKEN-EVENT at all).
  jq -e '
    .tokens.processed_total.confidence == "partial" and
    (.tokens.processed_total._note | test("conductor-share-pending")) and
    .conductor_tokens.confidence == "unavailable"
  ' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: if the consumer labeled a missing-conductor total "exact", the
  # confidence check fails.
expected: exit 0; stdout "PASS"; tokens.processed_total.confidence=partial with conductor-share-pending _note; conductor_tokens.confidence=unavailable
phase: 05 · feature
owner: Prompt 5 / account-run.sh Bundle 11 merge (AC 4b — Blocker guard)
