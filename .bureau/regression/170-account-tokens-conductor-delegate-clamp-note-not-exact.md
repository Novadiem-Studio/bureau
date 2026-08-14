name: audit-r2 F3 (ii) — CONDUCTOR + DELEGATE events carrying a clamp _note rolling up to zero → the _note surfaces on each block + confidence not "exact"
retired: 07 · execute-plan — FR4 REPLACE retired this live-rail token-rollup assertion; post-hoc aggregation is the sole per-leg source
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  RP="$TMPF/f3"; mkdir -p "$RP"; echo '{}' > "$RP/state.json"

  # bureau-token-lib.sh compute_delta_line writes a clamp _note like
  # "clamped input (raw 100 < baseline 999) to 0" when a leg's raw cumulative is
  # below its baseline; every field can clamp to 0, giving a zero-token event WITH a
  # _note. Both events here are final:true (so the old code would call the block
  # "exact") but roll up to zero tokens with a clamp note. Before the fix the note was
  # dropped and the zeroed bucket wore "exact". That is F3.
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"c1","at":"2026-07-11T00:01:00Z","turns":0,"tokens":{"input":0,"cache_creation":0,"cache_read":0,"processed":0,"output":0},"final":true,"baseline":{"session_id":"c1","input":999,"cache_creation":0,"cache_read":0,"processed":999,"output":0,"turns":0},"_note":"clamped input (raw 100 < baseline 999) to 0"}' \
    'DELEGATE-TOKEN-EVENT: {"session_id":"d1","at":"2026-07-11T00:02:00Z","turns":0,"tokens":{"input":0,"cache_creation":0,"cache_read":0,"processed":0,"output":0},"final":true,"baseline":{"session_id":"d1","input":0,"cache_creation":0,"cache_read":99,"processed":99,"output":0,"turns":0},"_note":"clamped cache_read (raw 5 < baseline 99) to 0"}' \
    > "$RP/log.md"

  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { echo "FAIL: account-tokens exited nonzero"; exit 1; }

  # Conductor: clamp _note surfaces + confidence downgraded off "exact".
  echo "$out" | jq -e '.conductor_tokens._note | test("clamped input")' > /dev/null \
    || { echo "FAIL: conductor clamp _note not surfaced: $(echo "$out" | jq -c .conductor_tokens)"; exit 1; }
  echo "$out" | jq -e '.conductor_tokens.confidence == "partial"' > /dev/null \
    || { echo "FAIL: conductor confidence should be partial, got $(echo "$out" | jq -r .conductor_tokens.confidence)"; exit 1; }
  echo "$out" | jq -e '.conductor_tokens.tokens.processed == 0' > /dev/null || { echo "FAIL: cond processed not 0"; exit 1; }

  # Delegate: clamp _note surfaces + confidence downgraded off "exact".
  echo "$out" | jq -e '.delegate_tokens._note | test("clamped cache_read")' > /dev/null \
    || { echo "FAIL: delegate clamp _note not surfaced: $(echo "$out" | jq -c .delegate_tokens)"; exit 1; }
  echo "$out" | jq -e '.delegate_tokens.confidence == "partial"' > /dev/null \
    || { echo "FAIL: delegate confidence should be partial, got $(echo "$out" | jq -r .delegate_tokens.confidence)"; exit 1; }
  echo "$out" | jq -e '.delegate_tokens.tokens.processed == 0' > /dev/null || { echo "FAIL: del processed not 0"; exit 1; }

  echo "PASS"
  # Mutation note: drop the $cond_zero_with_note / $del_zero_with_note downgrade (let
  # the conf branch return "exact" when all legs final) → both blocks come back
  # "exact" on the zeroed-with-clamp-note bucket → the confidence assertions fail.
  # Drop $cond_event_notes / $del_event_notes from the combined-note fold → the clamp
  # notes are not surfaced → the _note assertions fail.
expected: exit 0; stdout "PASS"; a CONDUCTOR and a DELEGATE event each carrying a clamp _note that rolls its block up to zero tokens surfaces the clamp note on that block and is confidence "partial" (not "exact"); processed stays 0 on each. Mutation-test: removing the zero-with-note downgrade or the event-note fold fails this fixture.
phase: 04 · feature — audit round 2, Finding 3
owner: account-tokens.sh conductor/delegate-block _note carry + zero-with-note confidence downgrade
