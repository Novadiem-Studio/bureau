name: account-run W1 — A2 enrichment pairs on the PARSED (descriptive) attempt_id, not a reconstructed composite
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/run-w1"
  mkdir -p "$RP"
  # Descriptive attempt_id (challenger-r1-1): §6 accepts it (role-prefixed, the 2026-07-01
  # relaxation), and the hooks / account-tokens.sh key spawn_tokens by that VERBATIM id.
  # The old A2 enricher rebuilt the strict composite "challenger-1" and missed it, silently
  # dropping per-spawn enrichment while tokens.processed_total stayed exact.
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"challenger","agent":"The Challenger","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"challenger-r1-1","status":"started","at":"2026-07-05T00:00:00Z","rework":true}' \
    'SPAWN-EVENT: {"role":"challenger","agent":"The Challenger","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"challenger-r1-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"challenger-r1-1","agent_id":"agent-c1","at":"2026-07-05T00:01:00Z","turns":3,"tokens":{"input":100,"cache_creation":150,"cache_read":250,"processed":500,"output":20}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-w1","at":"2026-07-05T00:02:00Z","turns":5,"tokens":{"input":50,"cache_creation":60,"cache_read":90,"processed":200,"output":10},"final":true}' \
    > "$RP/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["challenger"],"phase_status":"complete","critic_loops":{"challenger":1}}' > "$RP/state.json"
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq empty "$RP/accounting.json" 2>/dev/null || { rm -rf "$TMPF"; exit 1; }
  # Enrichment lands for the descriptive id AND attempt_id is still NOT a published leaf.
  jq -e '
    .specialist_spawns[0].rework == true and
    (.specialist_spawns[0] | has("attempt_id") | not) and
    .specialist_spawns[0].tokens.processed.value == 500 and
    .specialist_spawns[0].tokens.processed.confidence == "exact" and
    .specialist_spawns[0].tokens.output.confidence == "estimated" and
    .specialist_spawns[0].turns.value == 3 and
    .specialist_spawns[0].duration_s.value == 60 and
    .tokens.processed_total.value == 700 and
    .tokens.processed_total.confidence == "exact"
  ' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: reverting the A2 join to the composite reconstruction
  # (role.value+"-"+attempt.value → "challenger-1") misses the "challenger-r1-1" key, so
  # specialist_spawns[0] loses rework/tokens/turns/duration_s and this fixture fails —
  # while tokens.processed_total stays 700/exact (the exact live signature W1 flagged).
expected: exit 0; stdout "PASS"; specialist_spawns[0] enriched (rework==true, tokens.processed.value==500, turns==3, duration_s==60) for descriptive attempt_id challenger-r1-1; attempt_id absent as a leaf
phase: 05 · feature
owner: Prompt 5 / account-run.sh STEP A2 enrichment pairing (reviewed W1)
