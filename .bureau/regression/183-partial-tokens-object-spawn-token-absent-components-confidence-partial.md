name: partial-tokens-object-spawn-token-absent-components-confidence-partial (A6)
retired: 07 · execute-plan — FR4 REPLACE retired this live-rail token-rollup assertion; post-hoc aggregation is the sole per-leg source
phase: 01 · enforcement-relocation (FR 6 / A6)
owner: scripts/account-tokens.sh normalize_event + scripts/account-run.sh specialist_spawns projection
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  RP="$TMPF/run"; mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete"}' > "$RP/state.json"

  # Corpus: one SPAWN-TOKEN-EVENT with tokens:{processed:230, output:200} only
  # (input, cache_creation, cache_read all absent). ADJUDICATED CORRECTION: must include
  # a matching SPAWN-EVENT started+terminal pair for the attempt_id — without it
  # specialist_spawns is empty and the per-field assertion can never fire. The A6
  # machinery is verified correct WITH the pair present.
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"started","at":"2026-07-12T00:00:00Z"}' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"complete","at":"2026-07-12T00:01:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"analyst-1","agent_id":"abc-agent","at":"2026-07-12T00:01:00Z","turns":1,"tokens":{"processed":230,"output":200}}' \
    > "$RP/log.md"

  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1
  rc=$?; [ "$rc" = "0" ] || { echo "FAIL: account-run.sh exited $rc (expect 0)"; exit 1; }
  ACC="$RP/accounting.json"
  [ -f "$ACC" ] || { echo "FAIL: accounting.json not written"; exit 1; }

  # Verify specialist_spawns is non-empty before asserting on [0]
  sp_len=$(jq '.specialist_spawns | length' "$ACC")
  [ "$sp_len" -ge 1 ] || { echo "FAIL: specialist_spawns is empty — SPAWN-EVENT pair not matched"; exit 1; }

  # Assertion 1 (AC-16): input.confidence == "partial" (absent component, not "exact")
  jq -e '.specialist_spawns[0].tokens.input.confidence == "partial"' "$ACC" >/dev/null \
    || { echo "FAIL: specialist_spawns[0].tokens.input.confidence is not 'partial' (was: $(jq -r '.specialist_spawns[0].tokens.input.confidence // "null"' "$ACC"))"; exit 1; }

  # Assertion 2: cache_creation.confidence == "partial"
  jq -e '.specialist_spawns[0].tokens.cache_creation.confidence == "partial"' "$ACC" >/dev/null \
    || { echo "FAIL: specialist_spawns[0].tokens.cache_creation.confidence is not 'partial'"; exit 1; }

  # Assertion 3: cache_read.confidence == "partial"
  jq -e '.specialist_spawns[0].tokens.cache_read.confidence == "partial"' "$ACC" >/dev/null \
    || { echo "FAIL: specialist_spawns[0].tokens.cache_read.confidence is not 'partial'"; exit 1; }

  # Assertion 4: output.value == 200 AND output.confidence == "estimated"
  # (value flows through correctly, not zeroed)
  jq -e '.specialist_spawns[0].tokens.output.value == 200 and .specialist_spawns[0].tokens.output.confidence == "estimated"' "$ACC" >/dev/null \
    || { echo "FAIL: output.value=$(jq -r '.specialist_spawns[0].tokens.output.value // "null"' "$ACC") output.confidence=$(jq -r '.specialist_spawns[0].tokens.output.confidence // "null"' "$ACC") (expect value=200 confidence=estimated)"; exit 1; }

  # Assertion 5: processed.confidence == "partial"
  # (stated processed=230 disagrees with derived sum input+cache_creation+cache_read=0)
  jq -e '.specialist_spawns[0].tokens.processed.confidence == "partial"' "$ACC" >/dev/null \
    || { echo "FAIL: specialist_spawns[0].tokens.processed.confidence is not 'partial'"; exit 1; }

  # Assertion 6: accounting.json ._notes mentions "malformed field" (triggered by _norm_note)
  # The A6 partial-tokens path sets _norm_note on the record, which drives norm_total > 0
  # and surfaces in ._notes as "had a malformed field".
  jq -e '(._notes // []) | any(test("malformed field"))' "$ACC" >/dev/null \
    || { echo "FAIL: ._notes does not contain 'malformed field' — A6 _norm_note breadcrumb not surfaced in accounting.json"; exit 1; }

  echo "PASS"
  # Mutation note: revert $stk._partial_fields read in account-run.sh specialist_spawns
  # projection to the original `confidence: (if .key == "output" then "estimated" else
  # "exact" end)`. All absent components stamp {value:0,confidence:"exact"}. Assertions
  # 1-3 and 5 fail (confidence is "exact" instead of "partial"). Also revert the A6
  # _tokens_partial branch in normalize_event → _partial_fields never set → same result.
