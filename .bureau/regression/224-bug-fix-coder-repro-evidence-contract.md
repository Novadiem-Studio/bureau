name: bug-fix-coder-repro-evidence-contract
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  for AGENT in "$ROOT/agents/frontend.md" "$ROOT/agents/backend.md" "$ROOT/agents/sysadmin.md"; do
    grep -qF 'docs/conventions/diagnosing-bugs.md in bug-fix mode' "$AGENT" \
      || { echo "FAIL: $(basename "$AGENT") missing diagnosing-bugs input"; exit 1; }
    grep -qF 'run it red on pre-fix code' "$AGENT" \
      || { echo "FAIL: $(basename "$AGENT") missing pre-fix red obligation"; exit 1; }
    grep -qF 'red/green command evidence back to `RUN_DIR/repro.md`' "$AGENT" \
      || { echo "FAIL: $(basename "$AGENT") missing red/green evidence obligation"; exit 1; }
    grep -qF 'RUN_DIR/repro.md regression-test evidence in bug-fix mode' "$AGENT" \
      || { echo "FAIL: $(basename "$AGENT") handoff missing repro evidence"; exit 1; }
    grep -qF 'Regression test: none — no correct seam' "$AGENT" \
      || { echo "FAIL: $(basename "$AGENT") missing no-correct-seam stop"; exit 1; }
  done
  echo "PASS"
  # Mutation note: deleting the bug-fix-mode load, red/green obligation, repro.md
  # evidence handoff, or no-correct-seam stop from any build-party persona fails.
expected: exit 0; stdout "PASS"; all build-party personas carry the bug-fix regression evidence contract.
phase: 01 · feature (Bundle 36)
owner: agents/frontend.md + agents/backend.md + agents/sysadmin.md
