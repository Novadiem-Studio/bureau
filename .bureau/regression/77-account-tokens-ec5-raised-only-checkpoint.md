name: account-tokens EC 5 — raised-only checkpoint (wait_s null/unavailable, excluded from total)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  mkdir -p "$RP"
  printf '%s\n' '{}' > "$RP/state.json"
  # One raised checkpoint, no matching resolved line (run died while blocked).
  printf '%s\n' \
    'CHECKPOINT-EVENT: {"id":"solo","status":"raised","at":"2026-07-05T00:02:00Z"}' \
    > "$RP/log.md"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { rm -rf "$TMPF"; exit 1; }
  echo "$out" | jq -e '
    (.checkpoints.entries | length) == 1 and
    .checkpoints.entries[0].id == "solo" and
    .checkpoints.entries[0].wait_s.value == null and
    .checkpoints.entries[0].wait_s.confidence == "unavailable" and
    .checkpoints.human_wait_total_s.value == 0 and
    .checkpoints.human_wait_total_s.confidence == "partial"
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: fold a raised-only wait_s into the total and human_wait_total_s
  # would move off 0 (or the entry would carry a non-null wait) -> fixture fails.
expected: exit 0; stdout "PASS"; raised-only entry wait_s={value:null,confidence:"unavailable"}, human_wait_total_s=0/partial
phase: 04 · feature
owner: Prompt 4 / account-tokens.sh EC 5 raised-only checkpoint
