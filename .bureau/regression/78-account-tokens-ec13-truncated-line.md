name: account-tokens EC 13 — truncated final event line skipped + _note, output valid JSON, exit 0
retired: 07 · execute-plan — FR4 REPLACE retired this live-rail token-rollup assertion; post-hoc aggregation is the sole per-leg source
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  mkdir -p "$RP"
  printf '%s\n' '{"critic_loops":{"mage":1}}' > "$RP/state.json"
  # Two clean SPAWN-EVENT lines, then a SPAWN-TOKEN-EVENT cut mid-JSON with no
  # trailing newline (a hook append observed in flight, or a hand-mangled line).
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    > "$RP/log.md"
  printf '%s' 'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-m1","at":"2026-07-05T00:01:00Z","turns":2,"tokens":{"input":1,"cache_creation":1,"cache_read":1,"processed' >> "$RP/log.md"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP")
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  echo "$out" | jq -e '
    (type == "object") and
    (._notes | length) >= 1 and
    (._notes[0] | test("unparseable SPAWN-TOKEN-EVENT"))
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: drop the per-line parse gate and jq would choke on the torn payload
  # -> non-zero exit / no _note -> fixture fails.
expected: exit 0; stdout "PASS"; script exits 0, output is valid JSON, _notes contains an "unparseable SPAWN-TOKEN-EVENT" entry naming the skipped line
phase: 04 · feature
owner: Prompt 4 / account-tokens.sh EC 13 torn-line tolerance
