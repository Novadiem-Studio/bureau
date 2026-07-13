name: stated-vs-derived-processed-disagreement-spawn-token (A6 sibling)
phase: 01 · enforcement-relocation (FR 6 / A6 sibling)
owner: scripts/account-tokens.sh normalize_event — processed disagreement forces partial on processed field
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  RP="$TMPF/run"; mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete"}' > "$RP/state.json"

  # Corpus: one SPAWN-TOKEN-EVENT with all four component fields present and numeric
  # (input:100, cache_creation:50, cache_read:30, output:20) but processed stated as 999
  # (vs derived sum = 100+50+30 = 180). The disagreement triggers _tokens_partial for
  # "processed" only — the other components are exact (numeric and present).
  # ADJUDICATED CORRECTION: must include a SPAWN-EVENT started+terminal pair.
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"started","at":"2026-07-12T00:00:00Z"}' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"complete","at":"2026-07-12T00:01:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"analyst-1","agent_id":"abc-agent","at":"2026-07-12T00:01:00Z","turns":1,"tokens":{"input":100,"cache_creation":50,"cache_read":30,"output":20,"processed":999}}' \
    > "$RP/log.md"

  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1
  rc=$?; [ "$rc" = "0" ] || { echo "FAIL: account-run.sh exited $rc (expect 0)"; exit 1; }
  ACC="$RP/accounting.json"
  [ -f "$ACC" ] || { echo "FAIL: accounting.json not written"; exit 1; }

  sp_len=$(jq '.specialist_spawns | length' "$ACC")
  [ "$sp_len" -ge 1 ] || { echo "FAIL: specialist_spawns is empty — SPAWN-EVENT pair not matched"; exit 1; }

  # Assertion 1: processed.confidence == "partial" (the disagreement field)
  jq -e '.specialist_spawns[0].tokens.processed.confidence == "partial"' "$ACC" >/dev/null \
    || { echo "FAIL: processed.confidence is not 'partial' (was: $(jq -r '.specialist_spawns[0].tokens.processed.confidence // "null"' "$ACC"))"; exit 1; }

  # Assertion 2: input.confidence == "exact" (present numeric — NOT degraded)
  jq -e '.specialist_spawns[0].tokens.input.confidence == "exact"' "$ACC" >/dev/null \
    || { echo "FAIL: input.confidence is not 'exact' (was: $(jq -r '.specialist_spawns[0].tokens.input.confidence // "null"' "$ACC")) — present numeric should not be degraded"; exit 1; }

  # Assertion 3: cache_creation.confidence == "exact"
  jq -e '.specialist_spawns[0].tokens.cache_creation.confidence == "exact"' "$ACC" >/dev/null \
    || { echo "FAIL: cache_creation.confidence is not 'exact'"; exit 1; }

  # Assertion 4: cache_read.confidence == "exact"
  jq -e '.specialist_spawns[0].tokens.cache_read.confidence == "exact"' "$ACC" >/dev/null \
    || { echo "FAIL: cache_read.confidence is not 'exact'"; exit 1; }

  # Assertion 5: output.confidence == "estimated"
  jq -e '.specialist_spawns[0].tokens.output.confidence == "estimated"' "$ACC" >/dev/null \
    || { echo "FAIL: output.confidence is not 'estimated'"; exit 1; }

  # Assertion 6: ._notes names "stated processed disagrees" or "component sum"
  jq -e '(._notes // []) | any(test("disagrees|component sum"))' "$ACC" >/dev/null \
    || { echo "FAIL: ._notes does not contain 'disagrees' or 'component sum' — disagreement note not surfaced"; exit 1; }

  echo "PASS"
  # Mutation note: revert the stated-vs-derived check in normalize_event — specifically
  # remove the (($tk._stated_processed != null) and ($tk._stated_processed != $tk.processed))
  # as $disagreement check and the `+ (if $disagreement then ["processed"] else [] end)`
  # addition to $absent_components in $a6_partial. Then _partial_fields never includes
  # "processed" when only the disagreement fires → processed reads "exact". Assertion 1 fails.
