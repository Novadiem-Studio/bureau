name: stale guard state (b) — final:true with unparseable/absent at + later hook-stamped SPAWN-TOKEN-EVENT → "partial" + indeterminate note (W1 rework)
phase: 05 · conductor-capture-lifecycle (Lever 1 W1 rework)
owner: scripts/account-tokens.sh — staleness guard state (b)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  mkdir -p "$RP"
  printf '%s\n' '{"accounting":{"status":"complete"}}' > "$RP/state.json"

  # Case A: final:true with garbage (unparseable) at field + later hook-stamped
  # SPAWN-TOKEN-EVENT. tsnum("not-a-timestamp") → null, so $cond_final_max_at = null.
  # $later_activity_at IS parseable. $all_legs_final = true.
  # Expected: state (b) fires → confidence "partial" + indeterminate note.
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-A","at":"not-a-timestamp","turns":67,"tokens":{"input":1974,"cache_creation":269575,"cache_read":22366276,"processed":22637825,"output":148112},"final":true}' \
    'SPAWN-EVENT: {"role":"systemsmith","agent":"The Systemsmith","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"systemsmith-1","status":"started","at":"2026-07-16T20:22:54Z"}' \
    'SPAWN-TOKEN-EVENT: {"agent_id":"agt-systemsmith-1","attempt_id":"systemsmith-1","at":"2026-07-16T20:41:12Z","turns":30,"tokens":{"input":500,"cache_creation":50000,"cache_read":800000,"processed":850500,"output":12000}}' \
    'SPAWN-EVENT: {"role":"systemsmith","agent":"The Systemsmith","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"systemsmith-1","status":"complete","at":"2026-07-16T20:41:12Z","started_at":"2026-07-16T20:41:12Z"}' \
    > "$RP/log.md"
  out=$(PATH=/usr/bin:$PATH bash "$ROOT/scripts/account-tokens.sh" "$RP" 2>/dev/null) \
    || { rm -rf "$TMPF"; exit 1; }
  cond_conf=$(printf '%s' "$out" | jq -r '.conductor_tokens.confidence')
  cond_note=$(printf '%s' "$out" | jq -r '.conductor_tokens._note // ""')
  pt_conf=$(printf '%s' "$out" | jq -r '.tokens.processed_total.confidence')
  [ "$cond_conf" = "partial" ] \
    || { echo "FAIL Case A: conductor_tokens.confidence = $cond_conf (expected partial)"; rm -rf "$TMPF"; exit 1; }
  printf '%s' "$cond_note" | PATH=/usr/bin:$PATH grep -qi "indeterminate" \
    || { echo "FAIL Case A: _note does not mention indeterminate: $cond_note"; rm -rf "$TMPF"; exit 1; }
  [ "$pt_conf" = "partial" ] \
    || { echo "FAIL Case A: processed_total.confidence = $pt_conf (expected partial)"; rm -rf "$TMPF"; exit 1; }

  # Case B: final:true with absent at field (null) + later hook-stamped SPAWN-TOKEN-EVENT.
  # tsnum(null) → null, so $cond_final_max_at = null. Same state (b) logic.
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-B","turns":50,"tokens":{"input":1000,"cache_creation":100000,"cache_read":5000000,"processed":6100000,"output":50000},"final":true}' \
    'SPAWN-TOKEN-EVENT: {"agent_id":"agt-mage-1","attempt_id":"mage-1","at":"2026-07-16T21:00:00Z","turns":20,"tokens":{"input":200,"cache_creation":20000,"cache_read":400000,"processed":420200,"output":8000}}' \
    > "$RP/log.md"
  printf '%s\n' '{"accounting":{"status":"complete"}}' > "$RP/state.json"
  out2=$(PATH=/usr/bin:$PATH bash "$ROOT/scripts/account-tokens.sh" "$RP" 2>/dev/null) \
    || { rm -rf "$TMPF"; exit 1; }
  cond_conf2=$(printf '%s' "$out2" | jq -r '.conductor_tokens.confidence')
  cond_note2=$(printf '%s' "$out2" | jq -r '.conductor_tokens._note // ""')
  [ "$cond_conf2" = "partial" ] \
    || { echo "FAIL Case B: conductor_tokens.confidence = $cond_conf2 (expected partial)"; rm -rf "$TMPF"; exit 1; }
  printf '%s' "$cond_note2" | PATH=/usr/bin:$PATH grep -qi "indeterminate" \
    || { echo "FAIL Case B: _note does not mention indeterminate: $cond_note2"; rm -rf "$TMPF"; exit 1; }

  # Case C: byte-identity control — final:true WITH parseable at predating activity
  # → state (a) fires, not (b). Outcome: "partial" + stale note (not indeterminate).
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-C","at":"2026-07-16T19:00:00Z","turns":30,"tokens":{"input":500,"cache_creation":50000,"cache_read":500000,"processed":550500,"output":5000},"final":true}' \
    'SPAWN-TOKEN-EVENT: {"agent_id":"agt-mage-2","attempt_id":"mage-2","at":"2026-07-16T20:00:00Z","turns":10,"tokens":{"input":100,"cache_creation":10000,"cache_read":200000,"processed":210100,"output":2000}}' \
    > "$RP/log.md"
  printf '%s\n' '{"accounting":{"status":"complete"}}' > "$RP/state.json"
  out3=$(PATH=/usr/bin:$PATH bash "$ROOT/scripts/account-tokens.sh" "$RP" 2>/dev/null) \
    || { rm -rf "$TMPF"; exit 1; }
  cond_note3=$(printf '%s' "$out3" | jq -r '.conductor_tokens._note // ""')
  printf '%s' "$cond_note3" | PATH=/usr/bin:$PATH grep -qi "stale" \
    || { echo "FAIL Case C: state (a) did not fire stale note: $cond_note3"; rm -rf "$TMPF"; exit 1; }
  printf '%s' "$cond_note3" | PATH=/usr/bin:$PATH grep -qi "indeterminate" \
    && { echo "FAIL Case C: indeterminate note fired spuriously: $cond_note3"; rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation proof: revert the state (b) branch (remove $cond_coverage_indeterminate
  # from $cond_conf and $cond_ok) so a garbage/absent final-at keeps "exact".
  # Then Cases A and B get confidence "exact", and their "partial" assertions fail.
expected: exit 0; stdout "PASS"; Cases A and B: conductor_tokens.confidence="partial" + indeterminate note + processed_total.confidence="partial"; Case C: stale note fires (not indeterminate)
