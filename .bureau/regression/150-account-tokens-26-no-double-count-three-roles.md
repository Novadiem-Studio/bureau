name: account-tokens #26 — three disjoint role buckets, no double-count; conductor_tokens byte-identical to a conductor-only run; output_total = sum of all roles (AC 14, 15, 17)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"; mkdir -p "$RP"
  echo '{}' > "$RP/state.json"

  # One conductor, one delegate, two reviewer (distinct spawn_ids) token events.
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"c1","at":"2026-07-11T00:01:00Z","turns":5,"tokens":{"input":100,"cache_creation":50,"cache_read":25,"processed":175,"output":10},"final":true}' \
    'DELEGATE-TOKEN-EVENT: {"session_id":"d1","at":"2026-07-11T00:02:00Z","turns":3,"tokens":{"input":40,"cache_creation":20,"cache_read":10,"processed":70,"output":8},"final":true}' \
    'REVIEWER-TOKEN-EVENT: {"checkpoint":"05","at":"2026-07-11T00:03:00Z","turns":2,"tokens":{"input":30,"cache_creation":15,"cache_read":5,"processed":50,"output":6},"spawn_id":"05-1"}' \
    'REVIEWER-TOKEN-EVENT: {"checkpoint":"05","at":"2026-07-11T00:04:00Z","turns":1,"tokens":{"input":20,"cache_creation":10,"cache_read":0,"processed":30,"output":4},"spawn_id":"05-2"}' \
    > "$RP/log.md"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }

  # Each bucket carries EXACTLY its own prefix's sum — no overlap.
  echo "$out" | jq -e '
    .conductor_tokens.tokens.processed == 175 and
    .conductor_tokens.tokens.output == 10 and
    .delegate_tokens.tokens.processed == 70 and
    .delegate_tokens.legs == 1 and
    .reviewer_tokens.tokens.processed == 80 and
    .reviewer_tokens.spawns == 2 and
    (.reviewer_tokens.tokens.output == 10)
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # output_total folds ALL roles: 0(spec) + 10(cond) + 8(del) + 10(rev) = 28.
  echo "$out" | jq -e '.tokens.output_total.value == 28' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  # processed_total stays BUILD-ONLY (spec + conductor) = 175 — delegate/reviewer
  # gating cost is NOT folded into the rework/loop denominator (OQ-1).
  echo "$out" | jq -e '.tokens.processed_total.value == 175' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # (AC 17) conductor_tokens block is BYTE-IDENTICAL to a conductor-only run —
  # adding the delegate/reviewer lines must not perturb it. Build a conductor-only
  # log and diff the conductor_tokens JSON.
  RP2="$TMPF/r2"; mkdir -p "$RP2"; echo '{}' > "$RP2/state.json"
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"c1","at":"2026-07-11T00:01:00Z","turns":5,"tokens":{"input":100,"cache_creation":50,"cache_read":25,"processed":175,"output":10},"final":true}' \
    > "$RP2/log.md"
  out2=$(bash "$ROOT/scripts/account-tokens.sh" "$RP2") || { rm -rf "$TMPF"; exit 1; }
  ct1=$(echo "$out"  | jq -cS '.conductor_tokens')
  ct2=$(echo "$out2" | jq -cS '.conductor_tokens')
  [ "$ct1" = "$ct2" ] || { echo "conductor_tokens differ: $ct1 vs $ct2"; rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: route DELEGATE lines into the conductor bucket (change the
  # DELEGATE-TOKEN-EVENT case arm dest="$de_f" -> dest="$ct_f") → conductor_tokens
  # inflates to processed 245 and the byte-identity diff (ct1 == ct2) fails; the
  # per-bucket assertion also fails. This proves the disjoint-prefix partition is
  # the anti-double-count invariant.
expected: exit 0; stdout "PASS"; conductor 175 / delegate 70 / reviewer 80 each in its own bucket; output_total=28 (all four roles); processed_total=175 (build-only); conductor_tokens byte-identical to a conductor-only run
phase: 04 · feature
owner: account-tokens.sh three-bucket rollup no-double-count (#26)
