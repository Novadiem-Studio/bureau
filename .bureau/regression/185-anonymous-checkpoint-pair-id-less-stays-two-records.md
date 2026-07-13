name: anonymous-checkpoint-pair-id-less-stays-two-records (A1 sibling / checkpoint)
phase: 01 · enforcement-relocation (FR 5 / checkpoint clause)
owner: scripts/account-tokens.sh checkpoint inline block — id absent/empty → synthetic key
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  RP="$TMPF/run"; mkdir -p "$RP"
  printf '%s\n' '{}' > "$RP/state.json"

  # Corpus: two CHECKPOINT-EVENT lines with no "id" field (absent), status:raised.
  # Pre-fix: group_by(null) collapsed both into one checkpoint record (A1 pattern).
  # Post-fix: each absent id isolates to a distinct synthetic key __malformed__id__<ord>
  # → two checkpoint records survive.
  printf '%s\n' \
    'CHECKPOINT-EVENT: {"status":"raised","at":"2026-07-12T00:01:00Z"}' \
    'CHECKPOINT-EVENT: {"status":"raised","at":"2026-07-12T00:02:00Z"}' \
    > "$RP/log.md"

  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP" 2>/dev/null)
  [ -n "$out" ] || { echo "FAIL: account-tokens.sh emitted nothing"; exit 1; }

  # Assertion: two anonymous checkpoint entries produce two distinct records
  cp_len=$(echo "$out" | jq '.checkpoints.entries | length // 0')
  [ "$cp_len" -eq 2 ] \
    || { echo "FAIL: checkpoints.entries length=$cp_len (expect 2 — two anonymous checkpoints must not collapse to one)"; exit 1; }

  # Verify both entries have DISTINCT synthetic ids (not both the same null key)
  distinct=$(echo "$out" | jq '[.checkpoints.entries[].id] | unique | length')
  [ "$distinct" -eq 2 ] \
    || { echo "FAIL: checkpoint entries have non-distinct ids (distinct=$distinct, expect 2)"; exit 1; }

  echo "PASS"
  # Mutation note: revert the checkpoint id null-branch in the $checkpoints binding
  # to keep null (remove the elif that checks (.value.id == null) or (.value.id == "")
  # and produces __malformed__id__\(.key)). Without this, both absent ids produce the
  # JSON null key → group_by(null) collapses them into one checkpoint record → entries
  # length == 1. Assertion fails.
