name: account-run AC4(a) — completed run merges to schema 2 with processed_total + active_spawn_time exact
retired: 07 · execute-plan — FR4 REPLACE retired this live-rail token-rollup assertion; post-hoc aggregation is the sole per-leg source
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/ac4a"
  mkdir -p "$RP"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"architect-1","agent_id":"agent-aaa","at":"2026-07-05T00:01:00Z","turns":5,"tokens":{"input":200,"cache_creation":300,"cache_read":500,"processed":1000,"output":50}}' \
    'SPAWN-EVENT: {"role":"challenger","agent":"The Challenger","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"challenger-1","status":"started","at":"2026-07-05T00:01:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"challenger","agent":"The Challenger","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"challenger-1","status":"complete","at":"2026-07-05T00:01:30Z","started_at":"2026-07-05T00:01:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"challenger-1","agent_id":"agent-bbb","at":"2026-07-05T00:01:30Z","turns":3,"tokens":{"input":100,"cache_creation":150,"cache_read":250,"processed":500,"output":30}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-001","at":"2026-07-05T00:10:00Z","turns":42,"tokens":{"input":40,"cache_creation":60,"cache_read":100,"processed":200,"output":10},"final":true}' \
    > "$RP/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["architect","challenger"],"phase_status":"complete","critic_loops":{"architect":1,"challenger":1}}' > "$RP/state.json"
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  # final:true present AND every terminal SPAWN-EVENT matched → processed_total exact
  # (1000+500 specialist + 200 conductor = 1700); every duration parses → active exact.
  jq -e '
    .schema_version == 2 and
    .tokens.processed_total.value == 1700 and
    .tokens.processed_total.confidence == "exact" and
    .wall_clock.active_spawn_time_s.confidence == "exact"
  ' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: drop the final:true CONDUCTOR-TOKEN-EVENT line and processed_total
  # confidence flips to "partial" (AC4b) — this fixture fails.
expected: exit 0; stdout "PASS"; schema_version=2, tokens.processed_total.value=1700 confidence=exact, wall_clock.active_spawn_time_s.confidence=exact
phase: 05 · feature
owner: Prompt 5 / account-run.sh Bundle 11 merge (AC 4a)
