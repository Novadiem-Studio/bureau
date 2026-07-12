name: account-tokens FR 4/FR 7 — all legs finalize -> confidence "exact" (73 successor)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  mkdir -p "$RP"
  printf '%s\n' '{}' > "$RP/state.json"
  # sess-A: 500 (final:false) then 900 (final:true) -> take-max 900, HAS a final.
  # sess-B: 400 (final:true) -> take-max 400, HAS a final. BOTH legs finalize ->
  # $all_legs_final = true -> confidence "exact". processed = 900 + 400 = 1300.
  # Components are identity-consistent (processed = input+cache_creation+cache_read)
  # so the ingest-derivation is a no-op; critically the take-max on the DERIVED
  # processed still picks sess-A's final:true record (900 > 500), so all_legs_final
  # stays true and confidence stays "exact".
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-A","at":"2026-07-05T00:01:00Z","turns":10,"tokens":{"input":100,"cache_creation":150,"cache_read":250,"processed":500,"output":1},"final":false}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-A","at":"2026-07-05T00:05:00Z","turns":20,"tokens":{"input":300,"cache_creation":300,"cache_read":300,"processed":900,"output":2},"final":true}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-B","at":"2026-07-05T00:09:00Z","turns":8,"tokens":{"input":100,"cache_creation":150,"cache_read":150,"processed":400,"output":3},"final":true}' \
    > "$RP/log.md"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out" | jq -e '
    .conductor_tokens.legs == 2 and
    .conductor_tokens.confidence == "exact" and
    .conductor_tokens.tokens.processed == 1300
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: revert $all_legs_final to false (e.g. force $leg_finals | all to false)
  # -> confidence becomes "partial" -> the confidence assertion fails.
expected: exit 0; stdout "PASS"; legs=2, confidence="exact" (both legs have a final:true), processed=1300 (A take-max 900 + B 400)
phase: 02 · feature
owner: Prompt 2 / account-tokens.sh FR 4 all-legs-final exact (73 successor)
