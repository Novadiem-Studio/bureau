name: append-reviewer-tokens #26b — RAW usage from claude -p envelope → REVIEWER-TOKEN-EVENT; two spawns same checkpoint each counted; missing .usage → zero-token + _note (AC 11, 12, 13)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/run"; mkdir -p "$RP"; touch "$RP/log.md"

  # (AC 11) A captured claude -p --output-format json envelope WITH .usage — the
  # helper reads .usage RAW (no baseline) and derives processed = in+cc+cr.
  ENV1='{"type":"result","subtype":"success","result":"{\"verdict\":\"proceed\"}","session_id":"rev-a","num_turns":4,"total_cost_usd":0.03,"usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":300,"output_tokens":15}}'
  bash "$ROOT/scripts/append-reviewer-tokens.sh" "$RP" "05" "05-1" "$ENV1" || { rm -rf "$TMPF"; exit 1; }

  # (AC 12) A SECOND reviewer spawn at the SAME checkpoint (e.g. a revise re-review)
  # with a DISTINCT spawn_id → must be counted separately, not collapsed.
  ENV2='{"type":"result","num_turns":1,"usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":2}}'
  bash "$ROOT/scripts/append-reviewer-tokens.sh" "$RP" "05" "05-2" "$ENV2" || { rm -rf "$TMPF"; exit 1; }

  # (AC 13) An envelope MISSING .usage → zero-token event with a _note, never dropped.
  ENV3='{"type":"result","subtype":"error"}'
  bash "$ROOT/scripts/append-reviewer-tokens.sh" "$RP" "06" "06-1" "$ENV3" || { rm -rf "$TMPF"; exit 1; }

  # Three REVIEWER-TOKEN-EVENT lines total.
  n=$(grep -c "^REVIEWER-TOKEN-EVENT:" "$RP/log.md"); [ "$n" = "3" ] || { rm -rf "$TMPF"; exit 1; }

  # Line 1: raw usage, processed = 100+200+300 = 600, keyed checkpoint 05 spawn 05-1.
  l1="$(grep '^REVIEWER-TOKEN-EVENT:' "$RP/log.md" | sed -n 1p)"; l1="${l1#REVIEWER-TOKEN-EVENT: }"
  echo "$l1" | jq -e '.checkpoint == "05" and .spawn_id == "05-1" and .turns == 4 and .tokens.processed == 600 and .tokens.output == 15 and (has("baseline") | not)' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  # Line 2: distinct spawn 05-2, processed = 10.
  l2="$(grep '^REVIEWER-TOKEN-EVENT:' "$RP/log.md" | sed -n 2p)"; l2="${l2#REVIEWER-TOKEN-EVENT: }"
  echo "$l2" | jq -e '.checkpoint == "05" and .spawn_id == "05-2" and .tokens.processed == 10' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  # Line 3: missing usage → zero tokens + _note.
  l3="$(grep '^REVIEWER-TOKEN-EVENT:' "$RP/log.md" | sed -n 3p)"; l3="${l3#REVIEWER-TOKEN-EVENT: }"
  echo "$l3" | jq -e '.checkpoint == "06" and .spawn_id == "06-1" and .tokens.processed == 0 and (._note | test("no .usage block"))' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # The rollup SUMS across spawn_ids (05-1 + 05-2 = 610 processed), not take-max-to-one.
  echo '{}' > "$RP/state.json"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out" | jq -e '.reviewer_tokens.tokens.processed == 610 and .reviewer_tokens.spawns == 3 and .reviewer_tokens.confidence == "exact"' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: drop the per-spawn discriminator (pass the same spawn_id "05" for
  # both spawns at checkpoint 05) → account-tokens.sh group_by(.spawn_id) take-max
  # collapses the two same-checkpoint spawns to one (600, not 610) → the
  # reviewer_tokens.processed==610 assertion fails.
expected: exit 0; stdout "PASS"; three REVIEWER-TOKEN-EVENT lines (raw usage, no baseline); two same-checkpoint spawns with distinct spawn_ids each counted (processed 600 + 10); missing-.usage → zero-token + _note; rollup sums to 610 across spawn_ids
phase: 04 · feature
owner: append-reviewer-tokens.sh + account-tokens.sh reviewer rollup (#26b)
