name: account-tokens zero-conductor gate — topology-agnostic FR 4 (replaces v2-only gate); no-pointer fires protocol-failure; pointer fires capture-pending; conductor lines present → silent
retired: 07 · execute-plan — FR4 REPLACE retired this live-rail token-rollup assertion; post-hoc aggregation is the sole per-leg source
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  mkdir -p "$RP"
  printf '%s\n' '{"critic_loops":{"mage":1}}' > "$RP/state.json"
  # Complete matched spawn set; ZERO conductor lines.
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-m1","at":"2026-07-05T00:01:00Z","turns":2,"tokens":{"input":1,"cache_creation":1,"cache_read":1,"processed":500,"output":1}}' \
    > "$RP/log.md"

  # --- Case A: no "Pointer enrolled" line, no conductor events → protocol failure ---
  # Topology does not matter; gate is topology-agnostic (FR 4).
  echo '{"topology":"integrated","conductor_agent_id":"agent-c1","active_checkpoint":null,"revise_counts":{},"revision_cap":2}' > "$RP/delegate-state.json"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out" | jq -e '
    .conductor_tokens.confidence == "unavailable" and
    (.conductor_tokens._note | test("pointer enrolment never ran"))
  ' > /dev/null || { echo "FAIL: Case A did not fire protocol-failure note"; rm -rf "$TMPF"; exit 1; }

  # --- Case B: topology absent, no "Pointer enrolled" line → same protocol-failure note ---
  # Previously the old gate was INERT here (topology-gated); new gate fires regardless.
  rm -f "$RP/delegate-state.json"
  out2=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out2" | jq -e '
    .conductor_tokens.confidence == "unavailable" and
    (.conductor_tokens._note | test("pointer enrolment never ran"))
  ' > /dev/null || { echo "FAIL: Case B did not fire protocol-failure note without topology"; rm -rf "$TMPF"; exit 1; }

  # --- Case C: "Pointer enrolled" line present, no conductor lines → capture-pending ---
  cp "$RP/log.md" "$RP/log.md.bak"
  printf '%s\n' \
    'Pointer enrolled — nonce written to pointer file and conductor transcript only. Reading this log does not confer ownership.' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-m1","at":"2026-07-05T00:01:00Z","turns":2,"tokens":{"input":1,"cache_creation":1,"cache_read":1,"processed":500,"output":1}}' \
    > "$RP/log.md"
  out3=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out3" | jq -e '
    .conductor_tokens.confidence == "unavailable" and
    (.conductor_tokens._note | test("Stop hook not yet fired|capture still pending"))
  ' > /dev/null || { echo "FAIL: Case C did not fire capture-pending note"; rm -rf "$TMPF"; exit 1; }
  echo "$out3" | jq -e '
    (.conductor_tokens._note | test("pointer enrolment never ran") | not)
  ' > /dev/null || { echo "FAIL: Case C incorrectly fired protocol-failure note"; rm -rf "$TMPF"; exit 1; }

  # --- Case D: conductor lines present → gate SILENT (regardless of topology) ---
  cp "$RP/log.md.bak" "$RP/log.md"
  echo '{"topology":"integrated"}' > "$RP/delegate-state.json"
  printf 'CONDUCTOR-TOKEN-EVENT: %s\n' '{"session_id":"agent-c1","at":"2026-07-05T00:02:00Z","turns":1,"tokens":{"input":10,"cache_creation":5,"cache_read":5,"processed":20,"output":2},"final":true}' >> "$RP/log.md"
  out4=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out4" | jq -e '
    .conductor_tokens.confidence == "exact" and
    ((.conductor_tokens._note // "") | test("pointer enrolment never ran|Stop hook not yet fired") | not)
  ' > /dev/null || { echo "FAIL: Case D: zero-conductor note fired with conductor lines present"; rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: revert $zero_conductor_note to always-null (remove the if-branch) →
  # Cases A and B no longer get the protocol-failure note → their test() assertions fail.
  # Revert the pointer_enrolled bash block to always set _pointer_enrolled="yes" →
  # Case A gets "capture still pending" instead of "pointer enrolment never ran" → fails.
expected: exit 0; stdout "PASS"; zero-conductor note fires on Cases A/B (no pointer enrolled → protocol-failure) and Case C (pointer enrolled → capture-pending); silent on Case D (conductor lines present)
phase: 01 · enforcement-relocation (FR 4)
owner: account-tokens.sh zero-conductor gate (topology-agnostic, replaces v2-only v2_gap_note)
