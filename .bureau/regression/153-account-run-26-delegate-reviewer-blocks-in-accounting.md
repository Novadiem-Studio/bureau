name: account-run #26 e2e — delegate_tokens + reviewer_tokens reach accounting.json (forwarded at the merge alongside conductor_tokens); a pure-v2 run (no conductor line) still carries them
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)

  # --- Case 1: a full run with conductor + delegate + reviewer token events -----
  # account-tokens.sh emits all three role blocks; account-run.sh step (a) must
  # forward delegate_tokens and reviewer_tokens into accounting.json alongside
  # conductor_tokens (the drop-at-the-merge class the _notes breadcrumb fix
  # already established). Without the forwarding the two new blocks never reach
  # the final artifact — defeating #26's "done when".
  RP="$TMPF/full"
  mkdir -p "$RP"
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"c1","at":"2026-07-11T00:01:00Z","turns":5,"tokens":{"input":100,"cache_creation":50,"cache_read":25,"processed":175,"output":10},"final":true}' \
    'DELEGATE-TOKEN-EVENT: {"session_id":"d1","at":"2026-07-11T00:02:00Z","turns":3,"tokens":{"input":40,"cache_creation":20,"cache_read":10,"processed":70,"output":8},"final":true}' \
    'REVIEWER-TOKEN-EVENT: {"checkpoint":"05","at":"2026-07-11T00:03:00Z","turns":2,"tokens":{"input":30,"cache_creation":15,"cache_read":5,"processed":50,"output":6},"spawn_id":"05-1"}' \
    'REVIEWER-TOKEN-EVENT: {"checkpoint":"05","at":"2026-07-11T00:04:00Z","turns":1,"tokens":{"input":20,"cache_creation":10,"cache_read":0,"processed":30,"output":4},"spawn_id":"05-2"}' \
    > "$RP/log.md"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","critic_loops":{"mage":1}}' > "$RP/state.json"
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  # All three role blocks present in the FINAL artifact, with the right sums.
  jq -e '
    .schema_version == 2 and
    (.conductor_tokens.tokens.processed == 175) and
    (has("delegate_tokens")) and
    (.delegate_tokens.tokens.processed == 70) and
    (.delegate_tokens.legs == 1) and
    (has("reviewer_tokens")) and
    (.reviewer_tokens.tokens.processed == 80) and
    (.reviewer_tokens.spawns == 2) and
    (.tokens.output_total.value == 28)
  ' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # --- Case 2: a PURE-v2 run — delegate + reviewer only, NO conductor line -------
  # (the Conductor is captured elsewhere / absent). The token-data gate must still
  # recognize the delegate/reviewer data so the merge runs and the two blocks land.
  RP2="$TMPF/purev2"
  mkdir -p "$RP2"
  printf '%s\n' \
    'DELEGATE-TOKEN-EVENT: {"session_id":"d1","at":"2026-07-11T00:02:00Z","turns":3,"tokens":{"input":40,"cache_creation":20,"cache_read":10,"processed":70,"output":8},"final":true}' \
    'REVIEWER-TOKEN-EVENT: {"checkpoint":"05","at":"2026-07-11T00:03:00Z","turns":2,"tokens":{"input":30,"cache_creation":15,"cache_read":5,"processed":50,"output":6},"spawn_id":"05-1"}' \
    > "$RP2/log.md"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete"}' > "$RP2/state.json"
  bash "$ROOT/scripts/account-run.sh" "$RP2" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '
    .schema_version == 2 and
    (has("delegate_tokens")) and (.delegate_tokens.tokens.processed == 70) and
    (has("reviewer_tokens")) and (.reviewer_tokens.tokens.processed == 50)
  ' "$RP2/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: remove `delegate_tokens: $tok.delegate_tokens, reviewer_tokens:
  # $tok.reviewer_tokens` from account-run.sh step (a)'s merge → both blocks are
  # absent from accounting.json → Case 1's has("delegate_tokens") assertion fails.
  # Remove the delegate/reviewer conditions from the tokens_have_data gate → the
  # pure-v2 merge is skipped (schema stays 1, blocks absent) → Case 2 fails.
expected: exit 0; stdout "PASS"; accounting.json carries conductor_tokens + delegate_tokens (processed 70, legs 1) + reviewer_tokens (processed 80, spawns 2) with output_total 28; a pure-v2 run (no conductor line) still carries the delegate/reviewer blocks
phase: 05 · feature
owner: account-run.sh #26 forward delegate_tokens/reviewer_tokens into accounting.json
