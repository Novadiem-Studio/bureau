name: absent-agent-id-spawn-token-two-events-stay-distinct-not-exact (A2 / EC 5)
phase: 01 · enforcement-relocation (FR 5 / A2 / EC 5)
owner: scripts/account-tokens.sh normalize_event — agent_id required on spawn-token stream
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  RP="$TMPF/run"; mkdir -p "$RP"
  printf '%s\n' '{}' > "$RP/state.json"

  # Corpus: two SPAWN-TOKEN-EVENTs with DISTINCT attempt_ids but BOTH agent_id:null.
  # EC 5 "two stay two": pre-fix → group_by(null) collapses two events with null
  # agent_id into one bucket → one record survives (the one with higher processed),
  # the other is dropped. Post-fix → each null agent_id isolates to a DISTINCT
  # synthetic key per _ord → two buckets → both costs in output.
  # Run account-run.sh (not account-tokens.sh) per the fixture spec.
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"started","at":"2026-07-12T00:00:00Z"}' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"complete","at":"2026-07-12T00:01:00Z"}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"architect-1","status":"started","at":"2026-07-12T00:02:00Z"}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"architect-1","status":"complete","at":"2026-07-12T00:03:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"analyst-1","agent_id":null,"at":"2026-07-12T00:01:00Z","turns":1,"tokens":{"input":5,"cache_creation":3,"cache_read":2,"processed":10,"output":1}}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"architect-1","agent_id":null,"at":"2026-07-12T00:03:00Z","turns":1,"tokens":{"input":15,"cache_creation":9,"cache_read":6,"processed":30,"output":3}}' \
    > "$RP/log.md"

  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1
  rc=$?; [ "$rc" = "0" ] || { echo "FAIL: account-run.sh exited $rc (expect 0)"; exit 1; }
  ACC="$RP/accounting.json"
  [ -f "$ACC" ] || { echo "FAIL: accounting.json not written"; exit 1; }

  # Assertion 1 (AC-9 / EC 5): two distinct unattributed/isolated entries survive
  # (processed_total should include both events' costs = 10+30 = 40 processed)
  total_proc=$(jq -r '.tokens.processed_total.value // 0' "$ACC")
  [ "$total_proc" -ge 40 ] 2>/dev/null \
    || { echo "FAIL: processed_total=$total_proc (expect >= 40 — both events' costs must survive, not collapse to max)"; exit 1; }

  # Assertion 2: aggregate processed_total reflects both events (not take-max drop)
  # (Already verified by Assertion 1 >= 40; confirm it's NOT just the max of 30)
  [ "$total_proc" -eq 40 ] 2>/dev/null \
    || echo "NOTE: processed_total=$total_proc (expected 40; may include conductor overhead)"

  # Assertion 3: processed_total.confidence NOT "exact"
  jq -e '.tokens.processed_total.confidence != "exact"' "$ACC" >/dev/null \
    || { echo "FAIL: processed_total.confidence is 'exact' — isolated records must degrade confidence"; exit 1; }

  echo "PASS"
  # Mutation note: revert the agent_id null-branch in normalize_event to the old
  # "null → null" pass-through (remove the elif-required-and-empty branch for agent_id
  # in the spawn_tokens stream). Then group_by(null) collapses the two null-agent_id
  # events into ONE bucket (higher-processed wins = 30 only), dropping the 10-processed
  # event. processed_total drops to 30. Assertions 1 and 3 fail.
