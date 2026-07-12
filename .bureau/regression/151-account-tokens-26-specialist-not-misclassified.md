name: account-tokens #26 — a plain specialist SPAWN-TOKEN-EVENT stays in the specialist bucket, never swept into delegate/reviewer (B4 no-misclassification)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"; mkdir -p "$RP"
  echo '{"critic_loops":{"mage":1}}' > "$RP/state.json"

  # A complete specialist spawn (started + terminal + SPAWN-TOKEN-EVENT) alongside
  # one conductor line. NO delegate/reviewer lines present. The new DELEGATE-/
  # REVIEWER- case arms must NOT capture the SPAWN-TOKEN-EVENT (disjoint prefixes).
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-11T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-11T00:01:00Z","started_at":"2026-07-11T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-m1","at":"2026-07-11T00:01:00Z","turns":2,"tokens":{"input":200,"cache_creation":150,"cache_read":150,"processed":500,"output":7}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"c1","at":"2026-07-11T00:02:00Z","turns":3,"tokens":{"input":10,"cache_creation":5,"cache_read":5,"processed":20,"output":2},"final":true}' \
    > "$RP/log.md"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }

  # Specialist processed lands in processed_total (spec 500 + cond 20 = 520).
  # Delegate and reviewer buckets are cleanly empty (unavailable, zero processed).
  echo "$out" | jq -e '
    .tokens.processed_total.value == 520 and
    .delegate_tokens.tokens.processed == 0 and
    .delegate_tokens.confidence == "unavailable" and
    .delegate_tokens.legs == 0 and
    .reviewer_tokens.tokens.processed == 0 and
    .reviewer_tokens.confidence == "unavailable" and
    .reviewer_tokens.spawns == 0 and
    .spawn_tokens["mage-1"].tokens.processed == 500
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: change the SPAWN-TOKEN-EVENT case arm to fall through to a
  # delegate/reviewer bucket → the specialist share vanishes from processed_total
  # (520 -> 20) and/or inflates delegate/reviewer → assertion fails. Confirms the
  # specialist prefix is unaffected by the two new arms.
expected: exit 0; stdout "PASS"; specialist SPAWN-TOKEN-EVENT stays in the specialist bucket (processed_total 520, spawn_tokens mage-1 500); delegate/reviewer buckets empty (unavailable, 0)
phase: 04 · feature
owner: account-tokens.sh #26 disjoint-prefix classifier — specialist not misclassified
