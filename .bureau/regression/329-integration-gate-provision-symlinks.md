name: F329 · provisioning cannot follow destination symlinks into tracked or external files (PR #102)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  M="$TMP/main"; W="$TMP/wt"; mkdir -p "$M/.bureau/regression"
  git -C "$M" init -q; git -C "$M" config user.email t@t; git -C "$M" config user.name t
  printf '.bureau/\n' > "$M/.gitignore"; printf 'protected\n' > "$M/protected.txt"
  git -C "$M" add -A; git -C "$M" commit -qm base; BASE=$(git -C "$M" rev-parse HEAD)
  git -C "$M" worktree add -q -b build "$W" "$BASE"
  printf '#!/bin/sh\nexit 0\n' > "$M/.bureau/regression/run.sh"
  printf '{"scope":{}}\n' > "$TMP/state.json"
  gate() {
    OUT="$TMP/$1"; mkdir "$OUT"
    "$ROOT/scripts/integration-gate.sh" --checkpoint-type integration --worktree-path "$W" \
      --base-ref "$BASE" --claimed-gates '[]' --state-json "$TMP/state.json" --out "$OUT"
    R="$OUT/integration-results.json"
  }
  mkdir -p "$W/.bureau/regression"; ln -s ../../protected.txt "$W/.bureau/regression/run.sh"
  gate leaf
  test "$(cat "$W/protected.txt")" = protected
  test ! -L "$W/.bureau/regression/run.sh"
  jq -e '.gates[] | select(.name=="regression") | .result=="green"' "$R" >/dev/null
  for kind in parent suite; do
    rm -rf "$W/.bureau"
    mkdir -p "$TMP/external-$kind/regression"
    printf '#!/bin/sh\nexit 9\n' > "$TMP/external-$kind/regression/run.sh"
    if [ "$kind" = parent ]; then
      ln -s "$TMP/external-$kind" "$W/.bureau"
    else
      mkdir "$W/.bureau"; ln -s "$TMP/external-$kind/regression" "$W/.bureau/regression"
    fi
    gate "$kind"
    jq -e '.escalate_marker | contains("symlink")' "$R" >/dev/null
    test "$(tail -1 "$TMP/external-$kind/regression/run.sh")" = 'exit 9'
  done
  rm -rf "$W/.bureau"
  rm "$M/.bureau/regression/run.sh"; ln -s ../../protected.txt "$M/.bureau/regression/run.sh"
  gate source
  jq -e '.escalate_marker | contains("symlink")' "$R" >/dev/null
  test "$(cat "$M/protected.txt")" = protected
  test ! -e "$W/.bureau"
  echo PASS
expected: exit 0; stdout "PASS". A leaf runner symlink is replaced without changing its tracked target. Symlinked .bureau or regression parents and source symlinks escalate without changing their targets. MUTATION - restoring copy2 into existing destinations overwrites protected.txt and fails the first assertion.
phase: 99 · PR 102 review fixes
owner: scripts/integration-gate.sh (safe provisioning)
