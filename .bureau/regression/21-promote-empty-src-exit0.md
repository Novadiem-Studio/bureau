name: Empty --src dir produces exit 0 with nothing copied
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TSRC=$(mktemp -d)
  TREPO=$(mktemp -d)
  mkdir -p "$TREPO/.bureau/regression"
  cp "$ROOT/.bureau/regression/run.sh" "$TREPO/.bureau/regression/run.sh"
  # TSRC is empty — no fixtures to process
  sh "$ROOT/scripts/promote-fixtures.sh" --src "$TSRC" --repo "$TREPO" --apply 2>&1; rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: expected exit 0, got $rc"; exit 1; }
  # No NN-*.md files should have been copied
  count=$(ls "$TREPO/.bureau/regression"/[0-9][0-9]-*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 0 ] || { echo "FAIL: unexpected files copied: $count"; exit 1; }
expected: exit 0
phase: 03 · fixture-promotion-lifecycle
owner: scripts/promote-fixtures.sh
