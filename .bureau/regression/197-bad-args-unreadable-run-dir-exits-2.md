name: bad-args-unreadable-run-dir-exits-2 (AC-7)
phase: 04 · verdict-binding (FR 11)
owner: scripts/verdict-gate.sh — bad arguments exit 2
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  out_a=$(bash "$ROOT/scripts/verdict-gate.sh" 2>&1); rc_a=$?
  [ "$rc_a" -eq 2 ] || { echo "FAIL: no-arg call exited $rc_a (expected 2): $out_a"; exit 1; }
  TMPD=$(mktemp -d); rm -rf "$TMPD"
  out_b=$(bash "$ROOT/scripts/verdict-gate.sh" "$TMPD" challenger-1 2>&1); rc_b=$?
  [ "$rc_b" -eq 2 ] || { echo "FAIL: unreadable RUN_DIR call exited $rc_b (expected 2): $out_b"; exit 1; }
  echo "PASS"
  # Mutation note: remove the argument-validation block from verdict-gate.sh. The missing-arg
  # call exits 1 or 0 instead of 2, so the exit-code assertions fail.
expected: PASS
