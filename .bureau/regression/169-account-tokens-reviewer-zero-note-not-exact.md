name: audit-r2 F2 (i) — a REVIEWER-TOKEN-EVENT with a _note + zero usage → reviewer_tokens carries the _note and is NOT "exact"
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  RP="$TMPF/rev"; mkdir -p "$RP"; echo '{}' > "$RP/state.json"

  # append-reviewer-tokens.sh writes exactly this on a `.usage`-less envelope: a
  # zero-token event carrying a _note so the spawn is never silently uncounted.
  # Before the fix, account-tokens.sh summed the reviewer bucket to zero and stamped
  # confidence "exact" — an exact-washed zero with the breadcrumb DROPPED. That is F2.
  printf '%s\n' \
    'REVIEWER-TOKEN-EVENT: {"checkpoint":"06","at":"2026-07-11T00:03:00Z","turns":0,"tokens":{"input":0,"cache_creation":0,"cache_read":0,"processed":0,"output":0},"spawn_id":"06-1","_note":"reviewer envelope had no .usage block — emitted zero-token event so the spawn is not silently uncounted"}' \
    > "$RP/log.md"

  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { echo "FAIL: account-tokens exited nonzero"; exit 1; }

  # (a) The event _note SURFACES on the reviewer block (never silently dropped).
  echo "$out" | jq -e '.reviewer_tokens._note | test("no .usage block")' > /dev/null \
    || { echo "FAIL: reviewer _note not surfaced: $(echo "$out" | jq -c .reviewer_tokens)"; exit 1; }
  # (b) A zeroed bucket carrying a _note is NOT blessed as exact — downgraded to partial.
  echo "$out" | jq -e '.reviewer_tokens.confidence == "partial"' > /dev/null \
    || { echo "FAIL: reviewer confidence should be partial, got $(echo "$out" | jq -r .reviewer_tokens.confidence)"; exit 1; }
  # (c) The processed sum is still 0 (the number itself is unchanged — only the
  #     confidence/breadcrumb changes, per the shipped don't-bless-a-zeroed-value rule).
  echo "$out" | jq -e '.reviewer_tokens.tokens.processed == 0' > /dev/null || { echo "FAIL: processed not 0"; exit 1; }

  echo "PASS"
  # Mutation note: revert the reviewer $rev_conf branch to the old unconditional
  # `if ($reviewers|length)>0 then "exact"` (drop the $rev_zero_with_note downgrade)
  # → confidence comes back "exact" on the zeroed-with-note bucket → assertion (b)
  # fails. Drop $rev_event_notes from $rev_combined_note → the _note is not surfaced →
  # assertion (a) fails.
expected: exit 0; stdout "PASS"; a REVIEWER-TOKEN-EVENT with a missing-usage _note and zero tokens surfaces its _note on reviewer_tokens and is confidence "partial" (not "exact"); processed stays 0. Mutation-test: restoring the unconditional-exact branch or dropping the event-note fold fails this fixture.
phase: 04 · feature — audit round 2, Finding 2
owner: account-tokens.sh reviewer-block _note carry + zero-with-note confidence downgrade
