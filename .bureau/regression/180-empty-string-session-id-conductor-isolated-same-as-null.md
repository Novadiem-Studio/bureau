name: empty-string-session-id-conductor-isolated-same-as-null (A3 / EC 4)
retired: 07 · execute-plan — FR4 REPLACE retired this live-rail token-rollup assertion; post-hoc aggregation is the sole per-leg source
phase: 01 · enforcement-relocation (FR 5 / A3 / EC 4)
owner: scripts/account-tokens.sh normalize_event — empty-string treated as absent for required fields
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  RP="$TMPF/run"; mkdir -p "$RP"
  printf '%s\n' '{}' > "$RP/state.json"

  # Corpus: two CONDUCTOR-TOKEN-EVENT lines, both final:true, session_id:"" (empty string).
  # EC 4: empty-string is treated identically to null for a required field.
  # Pre-fix: "" was passed through as a valid key → group_by("") collapsed both to one
  # bucket → confidence "exact". Post-fix: "" isolates identically to null → two buckets.
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"","final":true,"at":"2026-07-12T00:01:00Z","tokens":{"input":5,"cache_creation":3,"cache_read":2,"processed":10,"output":1}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"","final":true,"at":"2026-07-12T00:02:00Z","tokens":{"input":15,"cache_creation":9,"cache_read":6,"processed":30,"output":3}}' \
    > "$RP/log.md"

  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP" 2>/dev/null)
  [ -n "$out" ] || { echo "FAIL: account-tokens.sh emitted nothing"; exit 1; }

  # Assertion 1 (AC-8): conductor block NOT exact (empty-string session_ids must NOT collapse)
  echo "$out" | jq -e '.conductor_tokens.confidence != "exact"' >/dev/null \
    || { echo "FAIL: conductor_tokens.confidence is 'exact' — empty-string session_ids collapsed (A3/EC4 defect)"; exit 1; }

  # Assertion 2: both events' processed tokens reflected (sum = 10+30 = 40)
  cond_proc=$(echo "$out" | jq -r '.conductor_tokens.tokens.processed // 0')
  [ "$cond_proc" -ge 40 ] 2>/dev/null \
    || { echo "FAIL: conductor_tokens.tokens.processed=$cond_proc (expect >= 40 — both events reflected)"; exit 1; }

  # Assertion 3: conductor block note names "session_id"
  echo "$out" | jq -e '(.conductor_tokens._note // "") | test("session_id")' >/dev/null \
    || { echo "FAIL: no note naming 'session_id' — isolation breadcrumb not surfaced"; exit 1; }

  echo "PASS"
  # Mutation note: change the empty-string branch for session_id in normalize_event
  # back to pass-through (not isolate) — specifically remove the elif that checks
  # (($required | index("session_id")) != null) and (.session_id // "") == "".
  # Both "" values produce group_by("") → one collapsed bucket → confidence "exact".
  # Assertion 1 fails (was "exact", now required to be != "exact").
