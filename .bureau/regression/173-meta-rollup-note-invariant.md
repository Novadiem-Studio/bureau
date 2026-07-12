name: class-closure Guard 2 (rollup-note invariant) — a zero-tokens-with-_note event in EVERY role block (conductor + delegate + reviewer), driven end-to-end through account-run.sh's FINAL accounting.json, keeps each block partial (never exact), surfaces the event _note, and leaves processed==0 — PLUS a block-agnostic walk that catches a FUTURE block's exact-wash without naming it, PLUS a non-zero note-less negative half that stays exact
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT

  # ── CLASS FRAMING (read before adding a role block to account-tokens.sh) ──────
  # This is the CLASS guard for rollup class 2 ("silent exact-wash of a zeroed
  # bucket / a dropped _note"). It is NOT a copy of the per-instance fixtures
  # 169/170/171 — those pin the three CURRENT blocks in account-tokens.sh's stdout.
  # This fixture proves the invariant END-TO-END through the FINAL accounting.json
  # produced by account-run.sh (the round-1 lesson: assert on the file the run
  # actually emits, not just account-tokens.sh stdout), across ALL THREE role
  # blocks at once, AND adds a BLOCK-AGNOSTIC walk that catches a FUTURE 4th role
  # block's exact-wash WITHOUT this fixture naming that block.
  #
  # THE INVARIANT (per role block, in accounting.json):
  #   a block that rolled up to ZERO tokens while >=1 of its events carried a
  #   `._note` MUST NOT read "exact", that event `_note` MUST surface on the block,
  #   and the block's `processed` MUST stay 0 (the number is unchanged — only
  #   confidence/breadcrumb move; the shipped don't-bless-a-zeroed-value rule).
  #
  # IF YOU ADD A ROLE BLOCK (e.g. witness_tokens): add its zero-with-note row to
  # the corpus below and a per-block assertion for the SURFACE half (a dropped note
  # leaves nothing in the json to assert on, so the "note must surface" half is
  # per-named-block and needs extension). The DANGEROUS half (exact-washing a
  # zeroed bucket) is covered for your new block automatically by the block-agnostic
  # walk in Assertion 4 — you do not need to name it there.

  # A valid YYYYMMDD-slug run dir basename (account-run.sh calendar-validates it)
  # and a valid state.json (account-run.sh hard-fails on a missing one).
  RP="$TMPF/20260711-rollup-note-invariant"; mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{}}' > "$RP/state.json"

  # Corpus: a zero-tokens event carrying a _note in EVERY role block.
  #  - conductor: a final clamp-to-zero (compute_delta_line writes this _note shape)
  #  - delegate:  a final clamp-to-zero on a different leg
  #  - reviewer:  a missing-.usage fallback (append-reviewer-tokens.sh's exact shape)
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"c1","at":"2026-07-11T00:01:00Z","turns":0,"tokens":{"input":0,"cache_creation":0,"cache_read":0,"processed":0,"output":0},"final":true,"baseline":{"session_id":"c1","input":999,"cache_creation":0,"cache_read":0,"processed":999,"output":0,"turns":0},"_note":"clamped input (raw 100 < baseline 999) to 0"}' \
    'DELEGATE-TOKEN-EVENT: {"session_id":"d1","at":"2026-07-11T00:02:00Z","turns":0,"tokens":{"input":0,"cache_creation":0,"cache_read":0,"processed":0,"output":0},"final":true,"baseline":{"session_id":"d1","input":0,"cache_creation":0,"cache_read":99,"processed":99,"output":0,"turns":0},"_note":"clamped cache_read (raw 5 < baseline 99) to 0"}' \
    'REVIEWER-TOKEN-EVENT: {"checkpoint":"06","at":"2026-07-11T00:03:00Z","turns":0,"tokens":{"input":0,"cache_creation":0,"cache_read":0,"processed":0,"output":0},"spawn_id":"06-1","_note":"reviewer envelope had no .usage block — emitted zero-token event so the spawn is not silently uncounted"}' \
    > "$RP/log.md"

  # Drive the FINAL accounting.json (NOT account-tokens.sh stdout — the round-1 lesson).
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { echo "FAIL: account-run.sh exited nonzero on the zero-with-note corpus"; exit 1; }
  ACC="$RP/accounting.json"
  [ -f "$ACC" ] || { echo "FAIL: no accounting.json written"; exit 1; }

  # ── Assertions 1–3: per-named-block, end-to-end (conductor, delegate, reviewer) ─
  # Each block: (a) confidence != exact (is partial), (b) event _note surfaces,
  # (c) processed still 0.
  for pair in \
    'conductor_tokens|clamped input' \
    'delegate_tokens|clamped cache_read' \
    'reviewer_tokens|no .usage block' ; do
    block="${pair%%|*}"; needle="${pair#*|}"
    jq -e --arg b "$block" '.[$b].confidence == "partial"' "$ACC" > /dev/null \
      || { echo "FAIL: $block should be partial (not exact), got $(jq -r --arg b "$block" '.[$b].confidence' "$ACC")"; exit 1; }
    jq -e --arg b "$block" --arg n "$needle" '.[$b]._note | test($n)' "$ACC" > /dev/null \
      || { echo "FAIL: $block event _note did not surface (needle: $needle): $(jq -c --arg b "$block" '.[$b]' "$ACC")"; exit 1; }
    jq -e --arg b "$block" '.[$b].tokens.processed == 0' "$ACC" > /dev/null \
      || { echo "FAIL: $block processed should stay 0, got $(jq -r --arg b "$block" '.[$b].tokens.processed' "$ACC")"; exit 1; }
  done

  # ── Assertion 4: BLOCK-AGNOSTIC exact-wash walk (the load-bearing class guard) ─
  # No object ANYWHERE in accounting.json may be BOTH confidence=="exact" AND have
  # tokens.processed==0 AND carry a _note. A FUTURE role block that forgets the
  # downgrade produces exactly {confidence:"exact", tokens:{processed:0,...}, _note}
  # — caught here WITHOUT this fixture naming the new block. This is what makes the
  # guard block-agnostic for the dangerous half.
  jq -e '[.. | objects | select(has("confidence") and has("tokens"))
          | select(.confidence == "exact" and (.tokens.processed // 1) == 0 and has("_note"))]
         | length == 0' "$ACC" > /dev/null \
    || { echo "FAIL: an exact-washed zero-with-note block exists in accounting.json: $(jq -c '[.. | objects | select(has("confidence") and has("tokens")) | select(.confidence == "exact" and (.tokens.processed // 1) == 0 and has("_note"))]' "$ACC")"; exit 1; }

  # Self-check the walk is not vacuous: injecting a synthetic future-block object
  # that forgot the downgrade MUST trip the walk (>=1). This proves the walk would
  # catch a real future omission, not just that today's tree happens to be clean.
  jq '.witness_tokens = {tokens:{input:0,cache_creation:0,cache_read:0,processed:0,output:0},confidence:"exact",_note:"synthetic: a future block forgot to downgrade a zeroed-with-note bucket"}' "$ACC" > "$TMPF/mutated.json"
  mlen=$(jq -c '[.. | objects | select(has("confidence") and has("tokens")) | select(.confidence == "exact" and (.tokens.processed // 1) == 0 and has("_note"))] | length' "$TMPF/mutated.json")
  [ "$mlen" -ge 1 ] || { echo "FAIL: the block-agnostic walk is vacuous — a synthetic exact-with-note-on-zero object was NOT caught (len=$mlen)"; exit 1; }

  # ── Assertion 5: NEGATIVE HALF (false-positive guard, mirrors fixture 171) ─────
  # A non-zero, note-LESS corpus for all three blocks stays exact with NO _note and
  # trips the walk length 0. The downgrade must be narrow: it must NOT false-fire on
  # real data.
  RPC="$TMPF/20260711-clean-noteless"; mkdir -p "$RPC"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{}}' > "$RPC/state.json"
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"c1","at":"2026-07-11T00:01:00Z","turns":5,"tokens":{"input":100,"cache_creation":50,"cache_read":25,"processed":175,"output":10},"final":true}' \
    'DELEGATE-TOKEN-EVENT: {"session_id":"d1","at":"2026-07-11T00:02:00Z","turns":3,"tokens":{"input":40,"cache_creation":20,"cache_read":10,"processed":70,"output":8},"final":true}' \
    'REVIEWER-TOKEN-EVENT: {"checkpoint":"05","at":"2026-07-11T00:03:00Z","turns":2,"tokens":{"input":30,"cache_creation":15,"cache_read":5,"processed":50,"output":6},"spawn_id":"05-1"}' \
    > "$RPC/log.md"
  bash "$ROOT/scripts/account-run.sh" "$RPC" >/dev/null 2>&1 || { echo "FAIL: account-run.sh exited nonzero on the clean corpus"; exit 1; }
  ACCC="$RPC/accounting.json"
  jq -e '
    .conductor_tokens.confidence == "exact" and (.conductor_tokens | has("_note") | not) and
    .delegate_tokens.confidence  == "exact" and (.delegate_tokens  | has("_note") | not) and
    .reviewer_tokens.confidence  == "exact" and (.reviewer_tokens  | has("_note") | not)
  ' "$ACCC" > /dev/null || { echo "FAIL: a clean non-zero note-less block was perturbed: $(jq -c '{c:.conductor_tokens,d:.delegate_tokens,r:.reviewer_tokens}' "$ACCC")"; exit 1; }
  jq -e '[.. | objects | select(has("confidence") and has("tokens"))
          | select(.confidence == "exact" and (.tokens.processed // 1) == 0 and has("_note"))]
         | length == 0' "$ACCC" > /dev/null || { echo "FAIL: the walk false-fired on the clean corpus"; exit 1; }

  echo "PASS"
  # Mutation note (proves the guard, not just the current tree): in a scratch copy of
  # scripts/account-tokens.sh, revert ONE block's zero-with-note downgrade (drop the
  # $..._zero_with_note term so its $..._conf branch returns "exact" when all legs are
  # final) → that block comes back "exact" on the zeroed-with-note bucket → Assertion
  # 1–3 fails for that block AND (because processed==0 and a _note is present) the
  # block-agnostic walk in Assertion 4 trips → the fixture fails. Restore → passes.
  # The Assertion-4 self-check (synthetic witness_tokens) additionally proves the walk
  # is live even for a block that does not exist today.
expected: exit 0; stdout "PASS"; a zero-tokens-with-_note event in the conductor, delegate, AND reviewer blocks, driven through account-run.sh's FINAL accounting.json, keeps each block partial (not exact), surfaces the event _note, and leaves processed==0; a block-agnostic jq walk asserts NO object has confidence=="exact" with processed==0 and a present _note (self-checked non-vacuous against a synthetic future block); and a non-zero note-less corpus stays exact with no _note (no false-fire). Mutation-test: reverting any one block's zero-with-note downgrade fails the per-block assertions and the block-agnostic walk.
phase: 04 · feature — class-closure Guard 2 (rollup-note invariant meta-fixture)
owner: account-tokens.sh + account-run.sh rollup-note invariant (class 2 closure; block-agnostic exact-wash walk)
