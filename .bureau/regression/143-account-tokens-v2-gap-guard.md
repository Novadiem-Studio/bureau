name: account-tokens v2-gap guard — integrated topology + zero conductor lines → _note names the gap; topology absent → inert (AC-11, DQ-4)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  mkdir -p "$RP"
  printf '%s\n' '{"critic_loops":{"mage":1}}' > "$RP/state.json"
  # Complete matched spawn set; ZERO conductor lines (the capture gap).
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-m1","at":"2026-07-05T00:01:00Z","turns":2,"tokens":{"input":1,"cache_creation":1,"cache_read":1,"processed":500,"output":1}}' \
    > "$RP/log.md"

  # --- Case A: v2-integrated topology present → guard FIRES ---
  echo '{"topology":"integrated","conductor_agent_id":"agent-c1","active_checkpoint":null,"revise_counts":{},"revision_cap":2}' > "$RP/delegate-state.json"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out" | jq -e '
    .conductor_tokens.confidence == "unavailable" and
    (.conductor_tokens._note | test("v2-integrated topology but zero CONDUCTOR-TOKEN-EVENT captured")) and
    (.conductor_tokens._note | test("BUREAU_ROLE: conductor"))
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # --- Case B: topology absent (no delegate-state.json) → guard INERT ---
  rm -f "$RP/delegate-state.json"
  out2=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out2" | jq -e '
    .conductor_tokens.confidence == "unavailable" and
    ((.conductor_tokens._note // "") | test("v2-integrated") | not)
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # --- Case C: v2-integrated BUT conductor lines present → guard SILENT ---
  echo '{"topology":"integrated"}' > "$RP/delegate-state.json"
  printf 'CONDUCTOR-TOKEN-EVENT: %s\n' '{"session_id":"agent-c1","at":"2026-07-05T00:02:00Z","turns":1,"tokens":{"input":10,"cache_creation":5,"cache_read":5,"processed":20,"output":2},"final":true}' >> "$RP/log.md"
  out3=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out3" | jq -e '
    .conductor_tokens.confidence == "exact" and
    ((.conductor_tokens._note // "") | test("v2-integrated") | not)
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: drop the ($delegate_topology == "integrated") condition (fire
  # always) → Case B (topology absent) gets the v2-integrated note → its "not"
  # assertion fails. Drop the ($cond_conf == "unavailable") condition → Case C
  # (lines present) gets the note → its "not" assertion fails.
expected: exit 0; stdout "PASS"; v2-gap _note present only when topology==integrated AND confidence==unavailable (Case A); inert when topology absent (Case B); silent when conductor lines present (Case C, confidence exact)
phase: 04 · feature
owner: account-tokens.sh v2 capture-gap backstop guard (v2-conductor-capture)
