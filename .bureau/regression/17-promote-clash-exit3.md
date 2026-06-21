name: Same-slug changed-content fixture prints CLASH and exits 3 without overwriting
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TSRC=$(mktemp -d)
  TREPO=$(mktemp -d)
  mkdir -p "$TREPO/.bureau/regression"
  cp "$ROOT/.bureau/regression/run.sh" "$TREPO/.bureau/regression/run.sh"
  # Pre-place a fixture in TREPO with expected: exit 0
  cat >"$TREPO/.bureau/regression/60-clash.md" <<'ENDFIXTURE'
  name: clash fixture original
  command: |
    ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
    true
  expected: exit 0
  phase: 03 · fixture-promotion-lifecycle
  owner: scripts/promote-fixtures.sh
  ENDFIXTURE
  # Put a version of the SAME slug in TSRC but with different expected: (exit 1)
  cat >"$TSRC/60-clash.md" <<'ENDFIXTURE'
  name: clash fixture modified
  command: |
    ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
    true
  expected: exit 1
  phase: 03 · fixture-promotion-lifecycle
  owner: scripts/promote-fixtures.sh
  ENDFIXTURE
  out=$(sh "$ROOT/scripts/promote-fixtures.sh" --src "$TSRC" --repo "$TREPO" --apply 2>&1); rc=$?
  # Assert exit 3 and CLASH in output
  [ "$rc" -eq 3 ] || { echo "FAIL: expected exit 3, got $rc"; exit 1; }
  echo "$out" | grep -q 'CLASH' || { echo "FAIL: CLASH not in output"; exit 1; }
  # Assert the TREPO copy is unchanged (original expected: exit 0)
  grep -qF 'expected: exit 0' "$TREPO/.bureau/regression/60-clash.md" || { echo "FAIL: original file was overwritten"; exit 1; }
expected: exit 0
phase: 03 · fixture-promotion-lifecycle
owner: scripts/promote-fixtures.sh
