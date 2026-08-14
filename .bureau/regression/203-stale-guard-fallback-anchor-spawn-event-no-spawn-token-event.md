name: stale guard fallback anchor — no SPAWN-TOKEN-EVENT records but later SPAWN-EVENT started at → still detected stale
retired: 07 · execute-plan — FR4 REPLACE retired this live-rail token-rollup assertion; post-hoc aggregation is the sole per-leg source
phase: 05 · conductor-capture-lifecycle (Lever 1)
owner: scripts/account-tokens.sh — staleness guard SPAWN-EVENT fallback path
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  mkdir -p "$RP"
  printf '%s\n' '{"accounting":{"status":"complete"}}' > "$RP/state.json"
  # Corpus: NO SPAWN-TOKEN-EVENT lines; only a SPAWN-EVENT started at 20:22 (30m after
  # final:true at 19:52). Fallback anchor should be the SPAWN-EVENT started `at`.
  # Expected: stale guard fires, confidence "partial" + stale _note.
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-A","at":"2026-07-16T19:52:49Z","turns":67,"tokens":{"input":1974,"cache_creation":269575,"cache_read":22366276,"processed":22637825,"output":148112},"final":true}' \
    'SPAWN-EVENT: {"role":"systemsmith","agent":"The Systemsmith","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"systemsmith-1","status":"started","at":"2026-07-16T20:22:54Z"}' \
    > "$RP/log.md"
  out=$(PATH=/usr/bin:$PATH bash "$ROOT/scripts/account-tokens.sh" "$RP" 2>/dev/null) \
    || { rm -rf "$TMPF"; exit 1; }
  cond_conf=$(printf '%s' "$out" | jq -r '.conductor_tokens.confidence')
  cond_note=$(printf '%s' "$out" | jq -r '.conductor_tokens._note // ""')
  [ "$cond_conf" = "partial" ] \
    || { echo "FAIL: conductor_tokens.confidence = $cond_conf (expected partial)"; rm -rf "$TMPF"; exit 1; }
  printf '%s' "$cond_note" | PATH=/usr/bin:$PATH grep -qi "stale" \
    || { echo "FAIL: _note does not mention stale: $cond_note"; rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: remove the SPAWN-EVENT fallback path so $later_activity_at stays null
  # when no SPAWN-TOKEN-EVENTs exist. Then $cond_stale is false, confidence becomes
  # "exact" and the assertion fails.
expected: exit 0; stdout "PASS"; conductor_tokens.confidence="partial" with stale _note (fallback to SPAWN-EVENT started at)
