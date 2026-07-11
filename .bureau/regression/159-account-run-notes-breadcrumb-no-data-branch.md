name: account-run F4 (audit) — a scalar-only malformed token event (no conductor line, no usable data) keeps accounting.json at schema_version 1 BUT still carries the `_notes` breadcrumb; a genuine legacy no-token run stays note-free (AC5)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)

  # --- Case 1: scalar-only malformed event, no conductor line -------------------
  # The ONLY token line is a SPAWN-TOKEN-EVENT whose `tokens` is a bare scalar
  # (96666), with a null attempt_id and an unparseable `at`. account-tokens.sh
  # zeroes it and emits a `_notes` breadcrumb, but every numeric total is 0, there
  # is no conductor line, and no spawn has usable tokens — so account-run.sh's
  # tokens_have_data gate is FALSE and the schema-2 merge is skipped. Before F4
  # the `_notes` breadcrumb was dropped and this run was indistinguishable from a
  # genuine legacy no-token run. After F4 the breadcrumb is attached as a
  # top-level `_notes` while schema_version stays 1.
  RP="$TMPF/scalar"; mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phases_complete":["mage"],"phase_status":"complete","critic_loops":{"mage":0}}' > "$RP/state.json"
  printf '%s\n' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":null,"agent_id":"agent-x","at":"not-a-timestamp","turns":1,"tokens":96666}' \
    > "$RP/log.md"
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '
    .schema_version == 1 and
    (._notes | type) == "array" and
    (._notes | length) >= 1 and
    (._notes | join(" ") | test("non-object|scalar")) and
    (has("tokens") | not) and
    (has("conductor_tokens") | not)
  ' "$RP/accounting.json" > /dev/null || { echo "FAIL: schema1 _notes breadcrumb not present"; rm -rf "$TMPF"; exit 1; }

  # --- Case 2: a GENUINE legacy no-token run stays note-free (AC5) --------------
  # Old-format SPAWN-EVENT lines only, no token events at all → no fragment
  # `_notes` → the F4 conditional does not fire → schema 1 with NO `_notes` key,
  # byte-for-byte the pre-Bundle-11 baseline.
  LP="$TMPF/legacy"; mkdir -p "$LP"
  printf '%s\n' '{"workflow":"feature","phases_complete":["analyst"],"phase_status":"complete","critic_loops":{"analyst":0}}' > "$LP/state.json"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"started"}' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"complete"}' \
    > "$LP/log.md"
  bash "$ROOT/scripts/account-run.sh" "$LP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.schema_version == 1 and (has("_notes") | not)' "$LP/accounting.json" > /dev/null \
    || { echo "FAIL: legacy no-token run gained a spurious _notes / non-1 schema"; rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: remove the F4 `else` clause conditional (the
  # `if ... ((._notes // []) | length) > 0 ... jq '. + {_notes: $tok._notes}'`
  # block in account-run.sh's no-token-data branch) → Case 1's `_notes` is dropped
  # → the `._notes | type == "array"` assertion fails. Case 2 guards the reverse:
  # it must stay note-free, so an unconditional attach would fail `has("_notes")|not`.
expected: exit 0; stdout "PASS"; Case 1 scalar-only malformed event → accounting.json schema_version 1 WITH a top-level _notes breadcrumb (and no schema-2 blocks); Case 2 genuine legacy no-token run → schema 1, no _notes key
phase: 05 · feature
owner: account-run.sh _notes forwarding in the no-token-data / merge-skip branch (audit F4)
