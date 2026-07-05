name: account-tokens AC 8 — two-leg conductor take-max within session, sum across legs
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  mkdir -p "$RP"
  printf '%s\n' '{}' > "$RP/state.json"
  # session A fires twice (500 then 900, both mid-run final:false); session B
  # fires once (400, final:true). Collapse A to 900 (take-max), sum across A+B.
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-A","at":"2026-07-05T00:01:00Z","turns":10,"tokens":{"input":1,"cache_creation":1,"cache_read":1,"processed":500,"output":1},"final":false}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-A","at":"2026-07-05T00:05:00Z","turns":20,"tokens":{"input":2,"cache_creation":2,"cache_read":2,"processed":900,"output":2},"final":false}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-B","at":"2026-07-05T00:09:00Z","turns":8,"tokens":{"input":3,"cache_creation":3,"cache_read":3,"processed":400,"output":3},"final":true}' \
    > "$RP/log.md"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out" | jq -e '
    .conductor_tokens.tokens.processed == 1300 and
    .conductor_tokens.legs == 2 and
    .conductor_tokens.confidence == "exact"
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: drop the per-session take-max and A double-counts to 1400 (500+900);
  # drop the cross-session sum and B's 400 is lost -> fixture fails either way.
expected: exit 0; stdout "PASS"; conductor_tokens.tokens.processed=1300, legs=2, confidence exact (A collapsed to 900, summed with B 400)
phase: 04 · feature
owner: Prompt 4 / account-tokens.sh AC 8 multi-leg conductor
