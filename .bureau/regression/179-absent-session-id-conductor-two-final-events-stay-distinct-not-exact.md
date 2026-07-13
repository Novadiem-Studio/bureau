name: absent-session-id-conductor-two-final-events-stay-distinct-not-exact (A1)
phase: 01 · enforcement-relocation (FR 5 / A1)
owner: scripts/account-tokens.sh normalize_event($required) — session_id required on conductor stream
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  RP="$TMPF/run"; mkdir -p "$RP"
  printf '%s\n' '{}' > "$RP/state.json"

  # Corpus: two CONDUCTOR-TOKEN-EVENT lines, BOTH final:true, session_id null.
  # Pre-fix: group_by(null) collapsed both to one bucket → confidence "exact", legs==1.
  # Post-fix: each null isolates to a distinct synthetic key → two buckets → not "exact".
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":null,"final":true,"at":"2026-07-12T00:01:00Z","tokens":{"input":5,"cache_creation":3,"cache_read":2,"processed":10,"output":1}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":null,"final":true,"at":"2026-07-12T00:02:00Z","tokens":{"input":15,"cache_creation":9,"cache_read":6,"processed":30,"output":3}}' \
    > "$RP/log.md"

  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP" 2>/dev/null)
  [ -n "$out" ] || { echo "FAIL: account-tokens.sh emitted nothing"; exit 1; }

  # Assertion 1 (AC-7): conductor block NOT exact (two null ids must NOT collapse)
  echo "$out" | jq -e '.conductor_tokens.confidence != "exact"' >/dev/null \
    || { echo "FAIL: conductor_tokens.confidence is 'exact' — null session_ids collapsed (A1 defect)"; exit 1; }

  # Assertion 2: both events' processed tokens appear in the output (sum = 10+30 = 40;
  # both events contribute to processed_total, not just the max).
  # Check via conductor_tokens.tokens.processed (should reflect both = combined 40)
  # or via processed_total which includes conductor cost.
  cond_proc=$(echo "$out" | jq -r '.conductor_tokens.tokens.processed // 0')
  [ "$cond_proc" -ge 40 ] 2>/dev/null \
    || { echo "FAIL: conductor_tokens.tokens.processed=$cond_proc (expect >= 40 — both events reflected)"; exit 1; }

  # Assertion 3: conductor block note names "session_id" (isolation breadcrumb surfaced)
  echo "$out" | jq -e '(.conductor_tokens._note // "") | test("session_id")' >/dev/null \
    || { echo "FAIL: no note naming 'session_id' found — isolation breadcrumb not surfaced"; exit 1; }

  echo "PASS"
  # Mutation note: revert the session_id null-branch in normalize_event to the old
  # "null → null" pass-through (remove the elif-required-and-empty branch for session_id).
  # group_by(null) collapses both events into one bucket → legs==1 and confidence "exact".
  # Assertion 1 fails (was "exact", now required to be != "exact").
