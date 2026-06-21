name: Fixture lacking ROOT anchor is SKIP not-repo-relative and not copied
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TSRC=$(mktemp -d)
  TREPO=$(mktemp -d)
  mkdir -p "$TREPO/.bureau/regression"
  cp "$ROOT/.bureau/regression/run.sh" "$TREPO/.bureau/regression/run.sh"
  # Write a deliberately un-anchored (non-repo-relative) fixture to TSRC
  cat >"$TSRC/99-bad-fixture.md" <<'ENDFIXTURE'
  name: bad fixture lacking anchor
  command: echo "$RUN_DIR/some/path"
  expected: exit 0
  phase: test
  owner: test
  ENDFIXTURE
  out=$(sh "$ROOT/scripts/promote-fixtures.sh" --src "$TSRC" --repo "$TREPO" --apply 2>&1)
  echo "$out" | grep -q 'not-repo-relative' || { echo "FAIL: not-repo-relative not in output"; exit 1; }
  [ ! -f "$TREPO/.bureau/regression/99-bad-fixture.md" ] || { echo "FAIL: bad fixture was copied"; exit 1; }
expected: exit 0
phase: 03 · fixture-promotion-lifecycle
owner: scripts/promote-fixtures.sh
