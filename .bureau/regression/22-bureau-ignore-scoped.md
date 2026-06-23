name: ensure-bureau-ignored.sh adds scoped entries and leaves .bureau/regression/ unignored
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TREPO=$(mktemp -d)
  git -C "$TREPO" init -q
  "$ROOT/scripts/ensure-bureau-ignored.sh" "$TREPO"
  if ! git -C "$TREPO" check-ignore --quiet "$TREPO/.bureau/runs/x"; then
    echo "FAIL: .bureau/runs/ should be ignored"; rm -rf "$TREPO"; exit 1
  fi
  if ! git -C "$TREPO" check-ignore --quiet "$TREPO/.bureau/archive/x"; then
    echo "FAIL: .bureau/archive/ should be ignored"; rm -rf "$TREPO"; exit 1
  fi
  if git -C "$TREPO" check-ignore --quiet "$TREPO/.bureau/regression/x"; then
    echo "FAIL: regression should not be ignored"; rm -rf "$TREPO"; exit 1
  fi
  rm -rf "$TREPO"
expected: exit 0
phase: Prompt 2 · feature/20260622-bureau-file-location-hygiene
owner: scripts/ensure-bureau-ignored.sh
