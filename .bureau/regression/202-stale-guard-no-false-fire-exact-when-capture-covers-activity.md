name: stale guard no false-fire — all activity predates final capture → confidence stays "exact"
phase: 05 · conductor-capture-lifecycle (Lever 1)
owner: scripts/account-tokens.sh — staleness guard byte-identity (guards the exact path)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  mkdir -p "$RP"
  printf '%s\n' '{}' > "$RP/state.json"
  # Corpus: SPAWN-TOKEN-EVENT at 19:30 (before the final:true at 19:52).
  # No qualifying later-activity timestamp postdates the final capture,
  # so the stale guard must NOT fire — confidence must stay "exact".
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"analyst-1","status":"started","at":"2026-07-16T19:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"agent_id":"agt-analyst-1","attempt_id":"analyst-1","at":"2026-07-16T19:30:00Z","turns":20,"tokens":{"input":1000,"cache_creation":5000,"cache_read":10000,"processed":16000,"output":500}}' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"analyst-1","status":"complete","at":"2026-07-16T19:30:00Z","started_at":"2026-07-16T19:00:00Z"}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-A","at":"2026-07-16T19:52:49Z","turns":67,"tokens":{"input":100,"cache_creation":200,"cache_read":300,"processed":600,"output":10},"final":true}' \
    > "$RP/log.md"
  out=$(PATH=/usr/bin:$PATH bash "$ROOT/scripts/account-tokens.sh" "$RP" 2>/dev/null) \
    || { rm -rf "$TMPF"; exit 1; }
  cond_conf=$(printf '%s' "$out" | jq -r '.conductor_tokens.confidence')
  cond_note=$(printf '%s' "$out" | jq -r '.conductor_tokens._note // "null"')
  [ "$cond_conf" = "exact" ] \
    || { echo "FAIL: conductor_tokens.confidence = $cond_conf (expected exact); note: $cond_note"; rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: swap the SPAWN-TOKEN-EVENT `at` to a value AFTER the final capture
  # (e.g. 2026-07-16T20:00:00Z). Then $later_activity_at > $cond_final_max_at and
  # the stale guard fires, confidence becomes "partial" and the assertion fails.
expected: exit 0; stdout "PASS"; conductor_tokens.confidence="exact" (all activity before final capture, stale guard silent)
