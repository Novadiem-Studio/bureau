name: account-tokens FR 4 — mixed-final two-leg conductor -> confidence "partial" (per-leg all-final)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  mkdir -p "$RP"
  printf '%s\n' '{}' > "$RP/state.json"
  # sess-A fires twice, BOTH final:false (never finalizes). sess-B fires once
  # final:true. Under FR 4 (all legs must finalize), sess-A has no final:true ->
  # $all_legs_final = false -> confidence "partial". sess-A collapses to 900
  # (take-max), sess-B 400 -> cross-session sum 1300. This supersedes fixture 75's
  # second assertion and fixture 73's confidence assertion.
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-A","at":"2026-07-05T00:01:00Z","turns":10,"tokens":{"input":1,"cache_creation":1,"cache_read":1,"processed":500,"output":1},"final":false}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-A","at":"2026-07-05T00:05:00Z","turns":20,"tokens":{"input":2,"cache_creation":2,"cache_read":2,"processed":900,"output":2},"final":false}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-B","at":"2026-07-05T00:09:00Z","turns":8,"tokens":{"input":3,"cache_creation":3,"cache_read":3,"processed":400,"output":3},"final":true}' \
    > "$RP/log.md"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out" | jq -e '
    .conductor_tokens.confidence == "partial" and
    .conductor_tokens.legs == 2 and
    .conductor_tokens.tokens.processed == 1300
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: revert FR-4 to any-final logic ($conductor|map(.final==true)|any) ->
  # sess-B's final:true satisfies any-final -> confidence flips to "exact" -> the
  # first jq assertion fails.
expected: exit 0; stdout "PASS"; conductor_tokens.confidence="partial" (sess-A never finalizes, so not all legs final), legs=2, processed=1300 (A take-max 900 + B 400)
phase: 02 · feature
owner: Prompt 2 / account-tokens.sh FR 4 per-leg all-final (73/75 successor)
