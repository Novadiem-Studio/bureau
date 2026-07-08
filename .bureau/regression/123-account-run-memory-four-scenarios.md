name: memory four scenarios — no key, empty object, non-object, mixed (FR 8a)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  # 15a: no memory key — memory block absent from accounting.json
  mkdir -p "$TMPF/no-mem"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{}}' > "$TMPF/no-mem/state.json"
  bash "$ROOT/scripts/account-run.sh" "$TMPF/no-mem" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e 'has("memory") | not' "$TMPF/no-mem/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  # 15b: empty memory object — all fields unavailable
  mkdir -p "$TMPF/empty-mem"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{},"memory":{}}' > "$TMPF/empty-mem/state.json"
  bash "$ROOT/scripts/account-run.sh" "$TMPF/empty-mem" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.memory.retrieval_count.confidence == "unavailable"' "$TMPF/empty-mem/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  # 15c: non-object memory — fields unavailable + _note present
  mkdir -p "$TMPF/bad-mem"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{},"memory":"yes"}' > "$TMPF/bad-mem/state.json"
  bash "$ROOT/scripts/account-run.sh" "$TMPF/bad-mem" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.memory."_note" | length > 0' "$TMPF/bad-mem/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  # 15d: mixed memory — retrieval_count exact, writes_proposed unavailable, digest_freshness exact
  mkdir -p "$TMPF/mixed-mem"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{},"memory":{"retrieval_count":3,"writes_proposed":"lots","digest_freshness":"PT2H"}}' > "$TMPF/mixed-mem/state.json"
  bash "$ROOT/scripts/account-run.sh" "$TMPF/mixed-mem" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.memory.retrieval_count.confidence == "exact" and .memory.writes_proposed.confidence == "unavailable" and .memory.digest_freshness.confidence == "exact"' "$TMPF/mixed-mem/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; 15a: no memory key; 15b: retrieval_count.confidence=="unavailable"; 15c: memory._note non-empty; 15d: retrieval_count exact, writes_proposed unavailable, digest_freshness exact
phase: 02 · execute-plan
owner: Prompt 02 / account-run base-engine battle-test (multi-sub-case)
