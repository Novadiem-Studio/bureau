name: Fixture whose command value is the none sentinel is SKIP none and not copied
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TSRC=$(mktemp -d)
  TREPO=$(mktemp -d)
  mkdir -p "$TREPO/.bureau/regression"
  cp "$ROOT/.bureau/regression/run.sh" "$TREPO/.bureau/regression/run.sh"
  # Write a temp fixture whose command: VALUE IS EXACTLY the <none> sentinel
  cat >"$TSRC/99-none-fixture.md" <<'ENDFIXTURE'
  name: none sentinel fixture
  command: <none — phase accepted on visual inspection>
  expected: n/a
  phase: test
  owner: test
  ENDFIXTURE
  out=$(sh "$ROOT/scripts/promote-fixtures.sh" --src "$TSRC" --repo "$TREPO" --apply 2>&1)
  echo "$out" | grep -q 'SKIP none' || { echo "FAIL: SKIP none not in output"; exit 1; }
  [ ! -f "$TREPO/.bureau/regression/99-none-fixture.md" ] || { echo "FAIL: none fixture was copied"; exit 1; }
expected: exit 0
phase: 03 · fixture-promotion-lifecycle
owner: scripts/promote-fixtures.sh
