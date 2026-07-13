name: absent-record-when-attempt-id-named-fails (AC-6)
phase: 04 · verdict-binding (FR 11)
owner: scripts/verdict-gate.sh — named attempt_id requires a verdict record
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
  RUN_DIR="$TMPD/run"
  mkdir -p "$RUN_DIR/verdicts"
  out=$(bash "$ROOT/scripts/verdict-gate.sh" "$RUN_DIR" challenger-1 2>&1); rc=$?
  [ "$rc" -eq 1 ] || { echo "FAIL: verdict-gate exited $rc (expected 1): $out"; exit 1; }
  printf '%s\n' "$out" | grep -q "absent record" || { echo "FAIL: expected absent record DEFECT, got: $out"; exit 1; }
  echo "PASS"
  # Mutation note: create the missing challenger-1.json record with valid content. The gate
  # exits 0, so the grep for the absent-record DEFECT fails.
expected: PASS
