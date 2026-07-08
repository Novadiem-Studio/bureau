name: account-tokens FR 5 — suspicious multi-leg note fires when legs > resumed_legs + 1
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  mkdir -p "$RP"
  # state.json has NO resumed_legs field -> resumed_legs read as 0.
  printf '%s\n' '{}' > "$RP/state.json"
  # Two distinct conductor sessions (legs=2), both final:true. With resumed_legs=0,
  # 2 > (0 + 1) is true -> $suspicious_multi_leg fires -> _note carries the
  # suspicious-multi-leg text. (Both final:true keeps $cond_block_note null so the
  # _note is the suspicious note alone; the assert is a substring grep either way.)
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-A","at":"2026-07-05T00:01:00Z","turns":10,"tokens":{"input":1,"cache_creation":1,"cache_read":1,"processed":500,"output":1},"final":true}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-B","at":"2026-07-05T00:05:00Z","turns":8,"tokens":{"input":2,"cache_creation":2,"cache_read":2,"processed":400,"output":2},"final":true}' \
    > "$RP/log.md"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  # Substring grep (NOT exact equality): when $suspicious_note and $cond_block_note
  # both fire, $combined_note joins them with "; ", so the full string varies;
  # only the substring "conductor legs detected" is a reliable signal.
  printf '%s' "$out" | jq -r '.conductor_tokens._note' | grep -q "conductor legs detected" \
    || { rm -rf "$TMPF"; exit 1; }
  echo "$out" | jq -e '.conductor_tokens.legs == 2' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: drop the $suspicious_multi_leg / $suspicious_note branch (or force
  # $suspicious_note to null) -> _note absent or missing the suspicious-legs text ->
  # the grep -q fails -> fixture fails.
expected: exit 0; stdout "PASS"; conductor_tokens._note CONTAINS substring "conductor legs detected" (via grep, not exact equality); legs=2. Full AC-5 text: "2 conductor legs detected with no resume evidence in state.json — verify all are legitimate conductor legs; a foreign session may have been captured."
phase: 02 · feature
owner: Prompt 2 / account-tokens.sh FR 5 suspicious-multi-leg note
