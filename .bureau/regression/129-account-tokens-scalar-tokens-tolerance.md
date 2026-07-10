name: account-tokens scalar-`tokens` tolerance — a scalar SPAWN-TOKEN-EVENT no longer crashes the parser; run stays schema_version 2 with object-form events summed
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/scalar-tokens"
  mkdir -p "$RP"
  # A normal run with two object-form SPAWN-TOKEN-EVENTs and a final conductor
  # leg — PLUS one SPAWN-TOKEN-EVENT whose `tokens` is a bare SCALAR number
  # (96666), the shape the Agent tool's <usage><subagent_tokens>N</subagent_tokens>
  # summary produces. Before the fix, jq's `.tokens.processed` on that scalar
  # threw "Cannot index number with string" → account-tokens.sh exit 5 →
  # account-run.sh WARNING path → accounting.json silently dropped to
  # schema_version 1 (this is exactly what happened on the #23 run and had to be
  # hand-fixed). After the fix, `(.tokens | objects | .<field>) // 0` treats the
  # scalar as contributing 0, the parser exits 0, and the merge bumps to schema 2.
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"architect-1","agent_id":"agent-aaa","at":"2026-07-05T00:01:00Z","turns":5,"tokens":{"input":200,"cache_creation":300,"cache_read":500,"processed":1000,"output":50}}' \
    'SPAWN-EVENT: {"role":"challenger","agent":"The Challenger","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"challenger-1","status":"started","at":"2026-07-05T00:01:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"challenger","agent":"The Challenger","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"challenger-1","status":"complete","at":"2026-07-05T00:01:30Z","started_at":"2026-07-05T00:01:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"challenger-1","agent_id":"agent-bbb","at":"2026-07-05T00:01:30Z","turns":3,"tokens":96666}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-001","at":"2026-07-05T00:10:00Z","turns":42,"tokens":{"input":40,"cache_creation":60,"cache_read":100,"processed":200,"output":10},"final":true}' \
    > "$RP/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["architect","challenger"],"phase_status":"complete","critic_loops":{"architect":1,"challenger":1}}' > "$RP/state.json"
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  # The load-bearing assertion: the scalar line did NOT crash the parser, so the
  # merge ran and schema_version is 2 (NOT the 1 the crash would have produced).
  # processed_total sums ONLY the object-form events: architect 1000 + conductor
  # 200 = 1200; the scalar challenger record contributes 0 (not fatal, just skipped
  # numerically). The challenger SPAWN-TOKEN-EVENT still exists and its terminal is
  # matched, so processed_total confidence stays "exact". The scalar `tokens` never
  # propagates into the enriched specialist_spawns[] entry (which would crash
  # account-run.sh's `$stk.tokens | with_entries`) — proven by the whole run
  # completing at schema 2.
  jq -e '
    .schema_version == 2 and
    .tokens.processed_total.value == 1200 and
    .tokens.processed_total.confidence == "exact" and
    (.tokens.output_total.value == 60)
  ' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: revert any `(.tokens | objects | .<field>) // 0` guard back to the
  # bare `.tokens.<field> // 0` and the scalar line throws "Cannot index number
  # with string" → account-tokens.sh exit 5 → account-run.sh WARNING → schema_version
  # 1 → this fixture's `.schema_version == 2` check fails.
expected: exit 0; stdout "PASS"; schema_version=2 (NOT 1), tokens.processed_total.value=1200 confidence=exact, output_total.value=60 — the scalar-`tokens` SPAWN-TOKEN-EVENT contributed 0 without crashing the parser
phase: 04 · feature
owner: pre-eval hardening / account-tokens.sh scalar-`tokens` tolerance
