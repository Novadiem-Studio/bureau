name: Idempotent rerun of already-present identical fixture is SKIP identical + exit 0
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TSRC=$(mktemp -d)
  TREPO=$(mktemp -d)
  mkdir -p "$TREPO/.bureau/regression"
  cp "$ROOT/.bureau/regression/run.sh" "$TREPO/.bureau/regression/run.sh"
  # Mint a trivial always-pass fixture in TSRC
  cat >"$TSRC/50-dogfood-trivial.md" <<'ENDFIXTURE'
  name: dogfood trivial always-pass
  command: |
    ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
    true
  expected: exit 0
  phase: 03 · fixture-promotion-lifecycle
  owner: scripts/promote-fixtures.sh
  ENDFIXTURE
  # First --apply: should COPY the fixture
  out1=$(sh "$ROOT/scripts/promote-fixtures.sh" --src "$TSRC" --repo "$TREPO" --apply 2>&1)
  echo "$out1" | grep -q '^COPY' || { echo "FAIL: first run did not COPY"; exit 1; }
  # Second --apply: identical content, should SKIP identical and exit 0
  out2=$(sh "$ROOT/scripts/promote-fixtures.sh" --src "$TSRC" --repo "$TREPO" --apply 2>&1); rc2=$?
  echo "$out2" | grep -q 'SKIP identical' || { echo "FAIL: second run did not SKIP identical"; exit 1; }
  [ "$rc2" -eq 0 ] || { echo "FAIL: second run rc2=$rc2"; exit 1; }
expected: exit 0
phase: 03 · fixture-promotion-lifecycle
owner: scripts/promote-fixtures.sh
