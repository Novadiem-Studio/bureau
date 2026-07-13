name: absent-tokens-field-conductor-event-not-exact-zero (A4)
phase: 01 · enforcement-relocation (FR 6 / A4)
owner: scripts/account-tokens.sh normalize_event — absent tokens on token stream sets _isolated
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  RP="$TMPF/run"; mkdir -p "$RP"
  printf '%s\n' '{}' > "$RP/state.json"

  # Corpus: one CONDUCTOR-TOKEN-EVENT, final:true, session_id present and valid,
  # NO "tokens" key. Pre-fix: absent tokens coerced to zero with confidence "exact".
  # Post-fix: $tokens_absent detected → _isolated:true → block confidence degraded.
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-valid-1","final":true,"at":"2026-07-12T00:01:00Z"}' \
    > "$RP/log.md"

  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP" 2>/dev/null)
  [ -n "$out" ] || { echo "FAIL: account-tokens.sh emitted nothing"; exit 1; }

  # Assertion 1 (AC-10): conductor_tokens.confidence NOT "exact"
  echo "$out" | jq -e '.conductor_tokens.confidence != "exact"' >/dev/null \
    || { echo "FAIL: conductor_tokens.confidence is 'exact' — absent tokens field was not isolated (A4 defect)"; exit 1; }

  # Assertion 2: block note names "absent/null tokens object on a token event"
  # (cause-accurate block note text from ddbd070 — verify against the actual text in code)
  echo "$out" | jq -e '(.conductor_tokens._note // "") | test("absent/null tokens object on a token event")' >/dev/null \
    || { echo "FAIL: block note does not contain 'absent/null tokens object on a token event' — cause-accurate note not emitted"; exit 1; }

  # Assertion 3: confidence is "partial" or lower (not zero exact)
  # "partial" is the confidence level for an isolated conductor block with zero processed
  echo "$out" | jq -e '[.conductor_tokens.confidence] | any(. == "partial" or . == "unavailable")' >/dev/null \
    || { echo "FAIL: confidence should be 'partial' or lower for an absent-tokens record, got: $(echo "$out" | jq -r .conductor_tokens.confidence)"; exit 1; }

  echo "PASS"
  # Mutation note: remove the A4 absent-tokens _isolated branch in normalize_event
  # (delete the two lines: $tokens_absent binding and the `| (if $tokens_absent then true
  # else $isolated end) as $isolated` override). With the branch absent, _isolated is
  # never set for a missing tokens field → the block treats absence as zero and reads
  # "exact". Assertion 1 fails (was "exact", now required to be != "exact").
