name: account-tokens F1 (audit) — two distinct agent_ids under ONE started attempt_id → only the max-processed one is summed, the foreign duplicate is routed to unattributed + a collision note, never exact-washed into the attempt
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"; mkdir -p "$RP"
  printf '%s\n' '{"critic_loops":{"mage":1}}' > "$RP/state.json"
  # ONE started/complete mage spawn (attempt_id mage-1). TWO SPAWN-TOKEN-EVENT
  # lines claim mage-1 but with DIFFERENT agent_ids: agent-legit (processed 1000,
  # the real subagent) and agent-foreign (processed 9000, a duplicate/foreign
  # subagent admitted on the mention gate). Both carry identity-consistent
  # components (so the F3 identity-note is not the thing under test). Before F1,
  # the per-agent_id take-max kept BOTH (distinct agent_ids) and — both having a
  # real, started attempt_id — the unattributed filter caught NEITHER, so
  # processed_total summed 1000 + 9000 + 100(cond) = 10100 as "exact". After F1
  # the 1:1 attempt_id→agent_id invariant keeps exactly the max-processed record
  # (agent-foreign 9000 wins the tie-break) and routes the other to unattributed;
  # only ONE specialist record is summed. The load-bearing point: the two records
  # are NOT both summed, AND the collision is surfaced (not silently blessed).
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-11T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-11T00:01:00Z","started_at":"2026-07-11T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-legit","at":"2026-07-11T00:01:00Z","turns":2,"tokens":{"input":200,"cache_creation":300,"cache_read":500,"processed":1000,"output":5}}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-foreign","at":"2026-07-11T00:01:02Z","turns":3,"tokens":{"input":3000,"cache_creation":3000,"cache_read":3000,"processed":9000,"output":7}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"c1","at":"2026-07-11T00:02:00Z","turns":5,"tokens":{"input":40,"cache_creation":30,"cache_read":30,"processed":100,"output":2},"final":true}' \
    > "$RP/log.md"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }

  # (1) Exactly ONE of the two duplicate records is summed into the specialist
  # share — NOT both. processed_total = max(1000, 9000)=9000 + 100(cond) = 9100,
  # NOT 10100 (which is the both-summed exact-wash the bug produced).
  echo "$out" | jq -e '.tokens.processed_total.value == 9100' > /dev/null \
    || { echo "FAIL: processed_total not 9100 (both summed?): $(echo "$out" | jq -c .tokens.processed_total.value)"; rm -rf "$TMPF"; exit 1; }
  # (2) The collision is SURFACED: the loser lands in unattributed_records, and a
  # top-level _notes entry names the attempt_id collision.
  echo "$out" | jq -e '
    ([.tokens.unattributed_records[] | select(.attempt_id == "mage-1")] | length) == 1
  ' > /dev/null || { echo "FAIL: foreign duplicate not routed to unattributed"; rm -rf "$TMPF"; exit 1; }
  echo "$out" | jq -e '(._notes | join(" ")) | test("mage-1") and test("distinct agent_ids")' > /dev/null \
    || { echo "FAIL: no collision note in _notes"; rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: remove the F1 1:1 attempt_id→agent_id block (let $stok be the
  # bare per-agent_id take-max set) → BOTH agent-legit(1000) and
  # agent-foreign(9000) sum into the specialist share → processed_total.value =
  # 10100 (both washed in) → assertion (1) fails; and with no collision surfaced,
  # assertions (2) fail too.
expected: exit 0; stdout "PASS"; two agent_ids under one started attempt_id → only the max-processed record summed (processed_total 9100, not 10100), the foreign duplicate routed to unattributed_records, a _notes collision entry naming mage-1 and the distinct agent_ids
phase: 04 · feature
owner: account-tokens.sh 1:1 attempt_id→agent_id invariant (audit F1)
