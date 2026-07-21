name: build-diff-bug-regression-gate
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  SLICE="$ROOT/agents/critic/build-diff.md"

  grep -qF 'Bug-fix regression-test gate' "$SLICE" \
    || { echo "FAIL: bug-fix regression-test gate missing"; exit 1; }
  grep -qF 'committed regression test is a **Blocker**' "$SLICE" \
    || { echo "FAIL: missing-test Blocker missing"; exit 1; }
  grep -qF 'pre-fix red evidence' "$SLICE" \
    || { echo "FAIL: pre-fix red evidence gate missing"; exit 1; }
  grep -qF 'post-fix green evidence' "$SLICE" \
    || { echo "FAIL: post-fix green evidence gate missing"; exit 1; }
  grep -qF 'Regression test: none — no correct seam' "$SLICE" \
    || { echo "FAIL: no-correct-seam escape missing from review gate"; exit 1; }
  grep -qF 'at least a Standards warning' "$SLICE" \
    || { echo "FAIL: no-correct-seam warning severity missing"; exit 1; }
  grep -qF 'mutation-verify when' "$SLICE" \
    || { echo "FAIL: ambiguous-evidence mutation verification missing"; exit 1; }
  echo "PASS"
  # Mutation note: deleting the gate, Blocker severity, red/green evidence checks,
  # no-correct-seam escape, warning severity, or mutation-verify instruction makes
  # this fixture fail.
expected: exit 0; stdout "PASS"; build-diff review blocks bug fixes without genuine red/green regression-test evidence.
phase: 01 · feature (Bundle 36)
owner: agents/critic/build-diff.md bug-fix regression-test gate
