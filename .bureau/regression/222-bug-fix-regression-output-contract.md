name: bug-fix-regression-output-contract
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  BUGFIX="$ROOT/workflows/bug-fix.md"
  INDEX="$ROOT/workflows/index.md"

  grep -qF 'pre-fix red evidence' "$BUGFIX" \
    || { echo "FAIL: bug-fix output missing pre-fix red evidence"; exit 1; }
  grep -qF 'post-fix green evidence' "$BUGFIX" \
    || { echo "FAIL: bug-fix output missing post-fix green evidence"; exit 1; }
  grep -qF '.bureau/regression/NNN-slug.md' "$BUGFIX" \
    || { echo "FAIL: bureau regression fixture home missing"; exit 1; }
  grep -qF "app targets use the app's" "$BUGFIX" \
    || { echo "FAIL: app-suite home rule prefix missing"; exit 1; }
  grep -qF 'own test suite named by the local `testing` skill' "$BUGFIX" \
    || { echo "FAIL: app-suite home rule missing"; exit 1; }
  grep -qF 'Regression test: none — no correct seam' "$BUGFIX" \
    || { echo "FAIL: no-correct-seam workflow escape missing"; exit 1; }
  grep -qF 'regression-test record is present' "$BUGFIX" \
    || { echo "FAIL: close-out verification does not require regression-test record"; exit 1; }
  grep -qF 'committed regression test' "$INDEX" \
    || { echo "FAIL: workflow registry missing committed regression test summary"; exit 1; }
  echo "PASS"
  # Mutation note: deleting pre/post evidence, either per-repo home, the no-seam escape,
  # close-out requirement, or the registry summary makes this fixture fail.
expected: exit 0; stdout "PASS"; bug-fix workflow requires red/green regression-test evidence with a per-repo home rule.
phase: 01 · feature (Bundle 36)
owner: workflows/bug-fix.md regression-test output contract
