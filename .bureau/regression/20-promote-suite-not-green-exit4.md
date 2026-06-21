name: Post-copy suite failure with broken fixture in repo prints SUITE FAILED and exits 4
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TSRC=$(mktemp -d)
  TREPO=$(mktemp -d)
  mkdir -p "$TREPO/.bureau/regression"
  cp "$ROOT/.bureau/regression/run.sh" "$TREPO/.bureau/regression/run.sh"
  # Pre-place a deliberately-broken fixture in TREPO (command exits 1, expected exit 0)
  cat >"$TREPO/.bureau/regression/70-broken.md" <<'ENDFIXTURE'
  name: deliberately broken fixture
  command: |
    exit 1
  expected: exit 0
  phase: test
  owner: test
  ENDFIXTURE
  # Mint a trivial always-pass conformant fixture in TSRC (fresh slug)
  cat >"$TSRC/51-dogfood-trivial-b.md" <<'ENDFIXTURE'
  name: dogfood trivial always-pass b
  command: |
    ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
    true
  expected: exit 0
  phase: 03 · fixture-promotion-lifecycle
  owner: scripts/promote-fixtures.sh
  ENDFIXTURE
  out=$(sh "$ROOT/scripts/promote-fixtures.sh" --src "$TSRC" --repo "$TREPO" --apply 2>&1); rc=$?
  [ "$rc" -eq 4 ] || { echo "FAIL: expected exit 4, got $rc"; exit 1; }
  echo "$out" | grep -q 'SUITE FAILED' || { echo "FAIL: SUITE FAILED not in output"; exit 1; }
expected: exit 0
phase: 03 · fixture-promotion-lifecycle
owner: scripts/promote-fixtures.sh
