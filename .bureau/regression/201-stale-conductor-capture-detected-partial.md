name: stale conductor capture detected — final:true at T with hook-stamped SPAWN-TOKEN-EVENT at T+30m → confidence "partial" + stale _note
retired: 07 · execute-plan — FR4 REPLACE retired this live-rail token-rollup assertion; post-hoc aggregation is the sole per-leg source
phase: 05 · conductor-capture-lifecycle (Lever 1)
owner: scripts/account-tokens.sh — staleness guard
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  mkdir -p "$RP"
  printf '%s\n' '{"accounting":{"status":"complete"}}' > "$RP/state.json"
  # Corpus: conductor final:true at 19:52 + hook-stamped SPAWN-TOKEN-EVENT at 20:41
  # (the preferred unfakeable anchor). Expected: confidence "partial" + stale _note.
  # This is the canonical synthetic version of the mot archive defect scenario.
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-A","at":"2026-07-16T19:52:49Z","turns":67,"tokens":{"input":1974,"cache_creation":269575,"cache_read":22366276,"processed":22637825,"output":148112},"final":true}' \
    'SPAWN-EVENT: {"role":"systemsmith","agent":"The Systemsmith","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"systemsmith-1","status":"started","at":"2026-07-16T20:22:54Z"}' \
    'SPAWN-TOKEN-EVENT: {"agent_id":"agt-systemsmith-1","attempt_id":"systemsmith-1","at":"2026-07-16T20:41:12Z","turns":30,"tokens":{"input":500,"cache_creation":50000,"cache_read":800000,"processed":850500,"output":12000}}' \
    'SPAWN-EVENT: {"role":"systemsmith","agent":"The Systemsmith","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"systemsmith-1","status":"complete","at":"2026-07-16T20:41:12Z","started_at":"2026-07-16T20:41:12Z"}' \
    > "$RP/log.md"
  out=$(PATH=/usr/bin:$PATH bash "$ROOT/scripts/account-tokens.sh" "$RP" 2>/dev/null) \
    || { rm -rf "$TMPF"; exit 1; }
  cond_conf=$(printf '%s' "$out" | jq -r '.conductor_tokens.confidence')
  cond_note=$(printf '%s' "$out" | jq -r '.conductor_tokens._note // ""')
  pt_conf=$(printf '%s' "$out" | jq -r '.tokens.processed_total.confidence')
  # Must be partial with a stale note
  [ "$cond_conf" = "partial" ] || { echo "FAIL: conductor_tokens.confidence = $cond_conf (expected partial)"; rm -rf "$TMPF"; exit 1; }
  printf '%s' "$cond_note" | PATH=/usr/bin:$PATH grep -qi "stale" \
    || { echo "FAIL: _note does not mention stale: $cond_note"; rm -rf "$TMPF"; exit 1; }
  # processed_total must also degrade (constraint v)
  [ "$pt_conf" = "partial" ] || { echo "FAIL: processed_total.confidence = $pt_conf (expected partial)"; rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: remove the $cond_stale guard from the $cond_conf assignment so
  # $all_legs_final alone grants "exact". Then cond_conf = "exact" and the
  # confidence assertion fails.
expected: exit 0; stdout "PASS"; conductor_tokens.confidence="partial" with stale _note; processed_total.confidence="partial"
