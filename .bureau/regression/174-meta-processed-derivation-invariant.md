name: class-closure Guard 3 (processed-derivation invariant) — an INCONSISTENT (inflated) stated processed in EVERY role block (conductor + delegate + reviewer + specialist), driven end-to-end through account-run.sh's FINAL accounting.json, is DERIVED back to input+cache_creation+cache_read (never trusted verbatim), the F3 identity _note surfaces, AND a block-agnostic jq walk asserts NO tokens object anywhere has processed != input+cache_creation+cache_read — self-checked non-vacuous against a synthetic future block, with a consistent negative half that stays byte-clean
retired: 07 · execute-plan — FR4 REPLACE retired this live-rail token-rollup assertion; post-hoc aggregation is the sole per-leg source
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT

  # ── CLASS FRAMING (read before adding a role block / a tokens-shaped field) ────
  # This is the CLASS guard for derivation class 3 ("a stated `processed` is
  # trusted verbatim / a bucket forgets to derive"). It is NOT a copy of the
  # per-instance fixture 158 (which pins the specialist+conductor identity note in
  # account-tokens.sh's stdout). This fixture proves the invariant END-TO-END through
  # the FINAL accounting.json produced by account-run.sh (the round-1 lesson: assert
  # on the file the run actually emits), across ALL role blocks at once, AND adds a
  # BLOCK-AGNOSTIC walk that catches a FUTURE bucket's un-derived processed WITHOUT
  # this fixture naming that block.
  #
  # THE INVARIANT (everywhere in accounting.json): NO object with a tokens sub-object
  # carrying all four component fields (input, cache_creation, cache_read, processed)
  # may have processed != input+cache_creation+cache_read. account-tokens.sh's ingest
  # normalize_event DERIVES processed authoritatively at ingest, so every downstream
  # bucket, the totals, and the spawn_tokens map inherit a derived processed for free.
  #
  # IF YOU ADD A ROLE BLOCK, its `processed` is derived at ingest automatically — this
  # walk covers it with NO extension needed. IF YOU ADD A NEW tokens-shaped field with
  # its own component fields, it is covered too (the walk is `..`-recursive over the
  # whole json). You only need a new corpus line here if you want the DERIVE-AND-NOTE
  # half (Assertions 1-2) proven for your new block specifically.

  # A valid YYYYMMDD-slug run dir basename (account-run.sh calendar-validates it)
  # and a valid state.json (account-run.sh hard-fails on a missing one).
  RP="$TMPF/20260712-processed-derivation-invariant"; mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{"mage":1}}' > "$RP/state.json"

  # Corpus: an INFLATED (inconsistent) stated processed in EVERY role block plus a
  # matched specialist spawn. Each stated processed >> its component sum:
  #  - specialist: comp 200+300+500=1000 but states 9999
  #  - conductor:  comp 40+30+30=100     but states 8888
  #  - delegate:   comp 10+20+30=60      but states 7777
  #  - reviewer:   comp 5+10+15=30       but states 6666
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-12T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-12T00:01:00Z","started_at":"2026-07-12T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-m1","at":"2026-07-12T00:01:00Z","turns":2,"tokens":{"input":200,"cache_creation":300,"cache_read":500,"processed":9999,"output":5}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"c1","at":"2026-07-12T00:02:00Z","turns":5,"tokens":{"input":40,"cache_creation":30,"cache_read":30,"processed":8888,"output":2},"final":true}' \
    'DELEGATE-TOKEN-EVENT: {"session_id":"d1","at":"2026-07-12T00:03:00Z","turns":3,"tokens":{"input":10,"cache_creation":20,"cache_read":30,"processed":7777,"output":8},"final":true}' \
    'REVIEWER-TOKEN-EVENT: {"spawn_id":"05-1","checkpoint":"05","at":"2026-07-12T00:04:00Z","turns":2,"tokens":{"input":5,"cache_creation":10,"cache_read":15,"processed":6666,"output":6}}' \
    > "$RP/log.md"

  # Drive the FINAL accounting.json (NOT account-tokens.sh stdout — the round-1 lesson).
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { echo "FAIL: account-run.sh exited nonzero on the inflated corpus"; exit 1; }
  ACC="$RP/accounting.json"
  [ -f "$ACC" ] || { echo "FAIL: no accounting.json written"; exit 1; }

  # ── Assertion 1: each block's processed is DERIVED, not the inflated stated value ─
  # conductor derives to 100 (not 8888), delegate to 60 (not 7777), reviewer to 30
  # (not 6666); processed_total is the derived spec 1000 + conductor 100 = 1100 (not
  # 9999+8888=18887); the spawn_tokens map carries the derived spec 1000 (not 9999).
  jq -e '
    .conductor_tokens.tokens.processed == 100 and
    .delegate_tokens.tokens.processed  == 60  and
    .reviewer_tokens.tokens.processed  == 30  and
    .tokens.processed_total.value      == 1100 and
    (.specialist_spawns[0].tokens.processed.value == 1000)
  ' "$ACC" > /dev/null \
    || { echo "FAIL: a stated processed was trusted verbatim instead of derived: $(jq -c '{c:.conductor_tokens.tokens.processed,d:.delegate_tokens.tokens.processed,r:.reviewer_tokens.tokens.processed,pt:.tokens.processed_total.value,sp:.specialist_spawns[0].tokens.processed.value}' "$ACC")"; exit 1; }

  # ── Assertion 2: the F3 identity mismatch _note SURFACES (the disagreement is visible) ─
  jq -e '((.tokens.processed_total._note // "") | test("disagrees with input")) or
         (((._notes // []) | join(" ")) | test("disagrees with input"))' "$ACC" > /dev/null \
    || { echo "FAIL: the F3 identity mismatch _note did not surface on the inflated corpus"; exit 1; }

  # ── Assertion 3: BLOCK-AGNOSTIC derivation walk (the load-bearing class guard) ─
  # NO object ANYWHERE in accounting.json whose tokens sub-object carries all four
  # NUMBER-valued component fields may have processed != input+cache_creation+
  # cache_read. A FUTURE bucket that forgets to derive produces exactly such an
  # object — caught here WITHOUT this fixture naming the new block. The
  # `(.processed|type)=="number"` guard scopes the walk to the RAW block-level
  # tokens (plain numbers); it deliberately skips account-run.sh's ENRICHED
  # specialist_spawns[].tokens form, where every field is wrapped as
  # {value,confidence} (a non-number) — that form reads the ALREADY-DERIVED value
  # from account-tokens.sh's spawn_tokens map, so it is derived-correct by
  # construction (Assertion 1 proves specialist_spawns[0].tokens.processed.value).
  jq -e '[.. | objects
          | select((.tokens? | type) == "object")
          | .tokens
          | select(has("input") and has("cache_creation") and has("cache_read") and has("processed"))
          | select((.processed | type) == "number")
          | select(.processed != ((.input // 0) + (.cache_creation // 0) + (.cache_read // 0)))]
         | length == 0' "$ACC" > /dev/null \
    || { echo "FAIL: a tokens object with processed != input+cache_creation+cache_read exists in accounting.json: $(jq -c '[.. | objects | select((.tokens? | type)=="object") | .tokens | select(has("input") and has("cache_creation") and has("cache_read") and has("processed")) | select((.processed|type)=="number") | select(.processed != ((.input//0)+(.cache_creation//0)+(.cache_read//0)))]' "$ACC")"; exit 1; }

  # Self-check the walk is not vacuous: injecting a synthetic future-block object
  # that forgot to derive (processed 999 != 1+1+1) MUST trip the walk (>=1). Proves
  # the walk would catch a real future omission, not just that today's tree is clean.
  jq '.witness_tokens = {tokens:{input:1,cache_creation:1,cache_read:1,processed:999,output:0}}' "$ACC" > "$TMPF/mutated.json"
  mlen=$(jq -c '[.. | objects | select((.tokens? | type)=="object") | .tokens | select(has("input") and has("cache_creation") and has("cache_read") and has("processed")) | select((.processed|type)=="number") | select(.processed != ((.input//0)+(.cache_creation//0)+(.cache_read//0)))] | length' "$TMPF/mutated.json")
  [ "$mlen" -ge 1 ] || { echo "FAIL: the block-agnostic derivation walk is vacuous — a synthetic un-derived object was NOT caught (len=$mlen)"; exit 1; }

  # ── Assertion 4: NEGATIVE HALF (byte-clean guard, mirrors 173 Assertion 5) ─────
  # A consistent (processed == components) corpus keeps the walk at 0 AND changes no
  # value — the derivation is a no-op on valid data, so the identity note does NOT
  # false-fire.
  RPC="$TMPF/20260712-processed-derivation-clean"; mkdir -p "$RPC"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{"mage":1}}' > "$RPC/state.json"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-12T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-12T00:01:00Z","started_at":"2026-07-12T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-m1","at":"2026-07-12T00:01:00Z","turns":2,"tokens":{"input":200,"cache_creation":300,"cache_read":500,"processed":1000,"output":5}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"c1","at":"2026-07-12T00:02:00Z","turns":5,"tokens":{"input":40,"cache_creation":30,"cache_read":30,"processed":100,"output":2},"final":true}' \
    'DELEGATE-TOKEN-EVENT: {"session_id":"d1","at":"2026-07-12T00:03:00Z","turns":3,"tokens":{"input":10,"cache_creation":20,"cache_read":30,"processed":60,"output":8},"final":true}' \
    'REVIEWER-TOKEN-EVENT: {"spawn_id":"05-1","checkpoint":"05","at":"2026-07-12T00:04:00Z","turns":2,"tokens":{"input":5,"cache_creation":10,"cache_read":15,"processed":30,"output":6}}' \
    > "$RPC/log.md"
  bash "$ROOT/scripts/account-run.sh" "$RPC" >/dev/null 2>&1 || { echo "FAIL: account-run.sh exited nonzero on the clean corpus"; exit 1; }
  ACCC="$RPC/accounting.json"
  jq -e '
    .conductor_tokens.tokens.processed == 100 and
    .tokens.processed_total.value == 1100 and
    ((.tokens.processed_total._note // "") | test("disagrees with input") | not) and
    (((._notes // []) | join(" ")) | test("disagrees with input") | not)
  ' "$ACCC" > /dev/null || { echo "FAIL: the derivation perturbed a clean corpus or false-fired the identity note: $(jq -c '{c:.conductor_tokens.tokens.processed,pt:.tokens.processed_total.value,note:.tokens.processed_total._note}' "$ACCC")"; exit 1; }
  jq -e '[.. | objects | select((.tokens? | type)=="object") | .tokens | select(has("input") and has("cache_creation") and has("cache_read") and has("processed")) | select((.processed|type)=="number") | select(.processed != ((.input//0)+(.cache_creation//0)+(.cache_read//0)))] | length == 0' "$ACCC" > /dev/null \
    || { echo "FAIL: the derivation walk false-fired on the clean corpus"; exit 1; }

  echo "PASS"
  # Mutation note (proves the guard, not just the current tree): in a scratch copy of
  # scripts/account-tokens.sh, revert the ingest derivation (in coerce_tokens read the
  # stated `.processed` instead of `$in + $cc + $cr` as `processed`) → the inflated
  # corpus emits objects with processed != components (8888/7777/6666/9999) → the
  # block-agnostic walk in Assertion 3 trips AND Assertion 1's derived values fail →
  # the fixture fails. Restore → passes. The Assertion-3 self-check (synthetic
  # witness_tokens) additionally proves the walk is live even for a block that does
  # not exist today.
expected: exit 0; stdout "PASS"; an inflated stated processed in the conductor, delegate, reviewer, AND specialist blocks, driven through account-run.sh's FINAL accounting.json, is DERIVED back to input+cache_creation+cache_read (conductor 100, delegate 60, reviewer 30, processed_total 1100, spawn_tokens spec 1000 — never the inflated 8888/7777/6666/9999); the F3 identity _note surfaces; a block-agnostic jq walk asserts NO tokens object has processed != components (self-checked non-vacuous against a synthetic future block); and a consistent corpus stays byte-clean with no false-fired note. Mutation-test: reverting the ingest derivation trips the walk and the derived-value assertions.
phase: 04 · feature — class-closure Guard 3 (processed-derivation invariant meta-fixture)
owner: account-tokens.sh + account-run.sh processed-derivation invariant (class 3 closure; block-agnostic derivation walk)
