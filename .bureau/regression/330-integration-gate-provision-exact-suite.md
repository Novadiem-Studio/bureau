name: F330 · provisioning removes stale ignored files and protects tracked destination content (PR #102)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  M="$TMP/main"; W="$TMP/wt"; mkdir -p "$M/.bureau/regression"
  git -C "$M" init -q; git -C "$M" config user.email t@t; git -C "$M" config user.name t
  printf '.bureau/\n' > "$M/.gitignore"; git -C "$M" add -A; git -C "$M" commit -qm base
  BASE=$(git -C "$M" rev-parse HEAD); git -C "$M" worktree add -q -b build "$W" "$BASE"
  printf '#!/bin/sh\nfor f in .bureau/regression/[0-9]*.sh; do sh "$f" || exit $?; done\n' > "$M/.bureau/regression/run.sh"
  printf 'exit 0\n' > "$M/.bureau/regression/01-clean.sh"
  mkdir -p "$W/.bureau/regression/nested"
  printf 'touch extra-ran\nexit 7\n' > "$W/.bureau/regression/99-extra.sh"
  printf 'stale\n' > "$W/.bureau/regression/nested/stale.txt"
  printf '{"scope":{}}\n' > "$TMP/state.json"
  gate() {
    OUT="$TMP/$1"; mkdir "$OUT"
    "$ROOT/scripts/integration-gate.sh" --checkpoint-type integration --worktree-path "$W" \
      --base-ref "$BASE" --claimed-gates '[]' --state-json "$TMP/state.json" --out "$OUT"
    R="$OUT/integration-results.json"
  }
  gate clean
  jq -e '.gates[] | select(.name=="regression") | .result=="green"' "$R" >/dev/null
  test ! -e "$W/extra-ran"; test ! -e "$W/.bureau/regression/99-extra.sh"
  test ! -e "$W/.bureau/regression/nested"
  rm "$M/.bureau/regression/01-clean.sh"; printf 'exit 0\n' > "$M/.bureau/regression/02-new.sh"
  gate refresh
  test ! -e "$W/.bureau/regression/01-clean.sh"; test -f "$W/.bureau/regression/02-new.sh"
  printf '.bureau/*\n!.bureau/regression/\n.bureau/regression/*\n!.bureau/regression/keep.txt\n' > "$W/.gitignore"
  git -C "$W" add .gitignore; git -C "$W" commit -qm selective-ignore
  printf 'unignored\n' > "$W/.bureau/regression/keep.txt"
  gate unignored
  jq -e '.escalate_marker | contains("unignored")' "$R" >/dev/null
  test "$(cat "$W/.bureau/regression/keep.txt")" = unignored
  rm "$W/.bureau/regression/keep.txt"
  printf 'tracked\n' > "$W/.bureau/regression/protected.txt"
  git -C "$W" add -f .bureau/regression/protected.txt; git -C "$W" commit -qm protected
  gate tracked
  jq -e '.escalate_marker | contains("tracked")' "$R" >/dev/null
  test "$(cat "$W/.bureau/regression/protected.txt")" = tracked
  echo PASS
expected: exit 0; stdout "PASS". Extra ignored files and directories do not survive provisioning, old source fixtures disappear on refresh, and unignored or tracked destination files absent from the source prevent replacement. MUTATION - overlay-copying the source preserves 99-extra.sh, runs it, and fails the green assertion; removing the destination guards loses keep.txt or protected.txt.
phase: 99 · PR 102 review fixes
owner: scripts/integration-gate.sh (exact suite refresh)
