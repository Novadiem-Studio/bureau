name: class-closure Guard 5 (no exact bucket absorbed a malformed/isolated id) — two REVIEWER-TOKEN-EVENTs with a malformed (object) spawn_id stay TWO distinct spawns (not collapsed to one), the block reads "partial" not "exact" with a note naming the isolated records, and a BLOCK-AGNOSTIC walk proves NO role block anywhere in accounting.json wears confidence:"exact" while its input set contained an isolated record; the negative (all-valid) half keeps every block exact and mints no isolate note
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT

  # ── CLASS FRAMING (read before adding a value used as a group_by/object key) ───
  # This is the CLASS guard for the F1 collapse-and-wash ("a malformed id that
  # coerces to null makes group_by(null) COLLAPSE two distinct records into one, and
  # the survivor wears exact"). The confirmed F1 reproduction, inverted: two malformed-
  # spawn_id reviewers (processed 10 and 20) both coerced to null pre-fix, group_by
  # collapsed them to ONE bucket (summed 20, a distinct 10 vanished), confidence
  # "exact", no note. account-tokens.sh now ISOLATES each malformed id to a DISTINCT
  # synthetic key __malformed__spawn_id__<ord>, so the two stay two AND the _isolated
  # flag forces the block off exact.
  #
  # IF YOU ADD A NEW per-key-summed stream (a new group_by(.<id>) whose buckets are
  # summed and blessed as exact), add a malformed-id row here so "two malformed records
  # stay two, and no exact bucket absorbed an isolated record" is proven for it too.

  fail() { echo "FAIL: $*"; exit 1; }

  RP="$TMPF/20260712-no-exact-collapse"; mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{"mage":1}}' > "$RP/state.json"

  # Corpus: two REVIEWER-TOKEN-EVENTs with an OBJECT spawn_id (the F1 vector, a present-
  # but-wrong-typed key) processed 10 and 20, plus one CLEAN reviewer processed 30.
  printf '%s\n' \
    'REVIEWER-TOKEN-EVENT: {"checkpoint":"05","spawn_id":{"bad":"obj-a"},"at":"2026-07-12T00:01:00Z","turns":1,"tokens":{"input":5,"cache_creation":3,"cache_read":2,"processed":10,"output":1}}' \
    'REVIEWER-TOKEN-EVENT: {"checkpoint":"05","spawn_id":{"bad":"obj-b"},"at":"2026-07-12T00:02:00Z","turns":1,"tokens":{"input":10,"cache_creation":6,"cache_read":4,"processed":20,"output":2}}' \
    'REVIEWER-TOKEN-EVENT: {"checkpoint":"06","spawn_id":"06-1","at":"2026-07-12T00:03:00Z","turns":1,"tokens":{"input":15,"cache_creation":9,"cache_read":6,"processed":30,"output":3}}' \
    > "$RP/log.md"

  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1
  rc=$?; [ "$rc" = "0" ] || fail "account-run.sh exited $rc on the malformed-spawn_id corpus (must be 0)"
  ACC="$RP/accounting.json"
  [ -f "$ACC" ] || fail "no accounting.json written"

  # ── Assertion 1 (cardinality — the F1 core): the two malformed stay TWO ────────
  # clean(1) + two-distinct-malformed(2) = 3 spawns; processed = 10+20+30 = 60
  # (NOT 20+30=50 from a collapse that dropped the distinct 10).
  jq -e '.reviewer_tokens.spawns == 3 and .reviewer_tokens.tokens.processed == 60' "$ACC" >/dev/null \
    || fail "the two malformed reviewers collapsed: spawns=$(jq -r .reviewer_tokens.spawns "$ACC") (expect 3), processed=$(jq -r .reviewer_tokens.tokens.processed "$ACC") (expect 60)"

  # ── Assertion 2 (not exact): the block absorbed isolated records → NOT exact ───
  jq -e '.reviewer_tokens.confidence != "exact"
         and ((.reviewer_tokens._note // "") | test("isolated|malformed"))' "$ACC" >/dev/null \
    || fail "reviewer block wears exact or has no isolate note: conf=$(jq -r .reviewer_tokens.confidence "$ACC") note=$(jq -r '.reviewer_tokens._note // "(none)"' "$ACC")"

  # ── Assertion 3 (block-agnostic walk — the load-bearing class guard) ───────────
  # NO role block (conductor/delegate/reviewer + processed_total) may read exact while
  # its _note names an isolated/malformed record. accounting.json does not expose
  # _isolated directly, so assert the surrogate over every block that has a confidence.
  jq -e '
    [ .conductor_tokens, .delegate_tokens, .reviewer_tokens, .tokens.processed_total ]
    | map(select(type == "object" and has("confidence")))
    | all( if ((._note // "") | test("isolated|malformed")) then .confidence != "exact" else true end )
  ' "$ACC" >/dev/null \
    || fail "a block wears exact while its _note names an isolated/malformed record: $(jq -c '[.conductor_tokens,.delegate_tokens,.reviewer_tokens,.tokens.processed_total]|map({c:.confidence,n:._note})' "$ACC")"

  # ── Assertion 3 self-check (non-vacuous): inject a synthetic block with an isolate ─
  # note + exact and assert the SAME walk trips, so the walk is not passing vacuously.
  echo '{"reviewer_tokens":{"confidence":"exact","_note":"one or more reviewer record(s) had a malformed spawn_id"}}' \
    | jq -e '
        [ .reviewer_tokens ]
        | all( if ((._note // "") | test("isolated|malformed")) then .confidence != "exact" else true end )
      ' >/dev/null \
    && fail "the block-agnostic walk is VACUOUS — a synthetic exact+isolate-note block did NOT trip it"

  # ── Assertion 4 (negative half — byte-clean): an all-valid corpus stays exact ──
  RPN="$TMPF/20260712-no-exact-clean"; mkdir -p "$RPN"
  printf '%s\n' '{}' > "$RPN/state.json"
  printf '%s\n' \
    'REVIEWER-TOKEN-EVENT: {"checkpoint":"05","spawn_id":"05-1","at":"2026-07-12T00:01:00Z","turns":1,"tokens":{"input":5,"cache_creation":3,"cache_read":2,"processed":10,"output":1}}' \
    'REVIEWER-TOKEN-EVENT: {"checkpoint":"06","spawn_id":"06-1","at":"2026-07-12T00:02:00Z","turns":1,"tokens":{"input":10,"cache_creation":6,"cache_read":4,"processed":20,"output":2}}' \
    > "$RPN/log.md"
  outn=$(bash "$ROOT/scripts/account-tokens.sh" "$RPN") || fail "account-tokens exited nonzero on the clean corpus"
  echo "$outn" | jq -e '.reviewer_tokens.confidence == "exact"
                        and (.reviewer_tokens | has("_note") | not)
                        and .reviewer_tokens.spawns == 2
                        and .reviewer_tokens.tokens.processed == 30' >/dev/null \
    || fail "the isolate perturbed a clean corpus: $(echo "$outn" | jq -c '.reviewer_tokens')"

  echo "PASS"
  # Mutation note (the confirmed F1 reproduction, inverted): in a scratch copy of
  # scripts/account-tokens.sh, revert the isolate primitive — map a non-string
  # attempt_id/agent_id/session_id/spawn_id back to null instead of a synthetic key
  # (and drop the _isolated flag). Then group_by(.spawn_id) collapses the two malformed
  # reviewers (both null) into ONE bucket → spawns==2 (should be 3) and processed==50
  # (should be 60) → Assertion 1 fails; and the collapsed survivor wears "exact" with no
  # isolate note → Assertions 2/3 fail. Restore → passes.
expected: exit 0; stdout "PASS"; two REVIEWER-TOKEN-EVENTs with a malformed (object) spawn_id stay TWO distinct spawns (reviewer_tokens.spawns == 3 with one clean, processed == 60 not 50), the block reads not-"exact" with a _note naming the isolated records, and a block-agnostic walk proves no role block anywhere in accounting.json wears exact while its _note names an isolated/malformed record (self-checked non-vacuous); the all-valid negative half keeps the block exact with no note. Mutation-test: reverting the isolate primitive to coerce-to-null collapses the two malformed reviewers into one exact bucket and fails the cardinality + not-exact assertions.
phase: 04 · feature — class-closure Guard 5 (no-exact-bucket-absorbed-malformed-id meta-fixture)
owner: account-tokens.sh isolate primitive (synthetic per-record keys + _isolated confidence gates; F1 no-collapse-no-wash)
