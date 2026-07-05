name: account-run AC10 — conductor tokens live in a top-level block, never inside a specialist_spawns entry
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/ac10"
  mkdir -p "$RP"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-m1","at":"2026-07-05T00:01:00Z","turns":4,"tokens":{"input":100,"cache_creation":150,"cache_read":250,"processed":500,"output":20}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-c","at":"2026-07-05T00:05:00Z","turns":30,"tokens":{"input":40,"cache_creation":60,"cache_read":100,"processed":200,"output":10},"final":true}' \
    > "$RP/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["mage"],"phase_status":"complete","critic_loops":{"mage":0}}' > "$RP/state.json"
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  # Top-level conductor_tokens present with the conductor's own processed (200),
  # and NO specialist_spawns entry carries a session_id / legs / final key (the
  # conductor-only fields) — its processed is the specialist's own (500), not 200.
  jq -e '
    (.conductor_tokens.tokens.processed == 200) and
    ([.specialist_spawns[] | (has("session_id") or has("legs") or has("final"))] | any | not) and
    (.specialist_spawns[0].tokens.processed.value == 500)
  ' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: if conductor totals were folded into the specialist entry, the
  # session_id/legs/final absence check or the processed==500 check fails.
expected: exit 0; stdout "PASS"; top-level conductor_tokens.tokens.processed=200; no specialist_spawns entry carries conductor fields; specialist processed=500
phase: 05 · feature
owner: Prompt 5 / account-run.sh conductor/specialist separation (AC 10)
