name: F331 · run-directory runners and absent manifest-only gates remain available in linked worktrees (PR #102)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  M="$TMP/main"; W="$TMP/wt"; RUN="$TMP/run"
  mkdir -p "$M/.bureau/regression" "$RUN/regression"
  git -C "$M" init -q; git -C "$M" config user.email t@t; git -C "$M" config user.name t
  printf '.bureau/\n' > "$M/.gitignore"
  printf '{"scripts":{"test":"true"}}\n' > "$M/package.json"
  git -C "$M" add -A; git -C "$M" commit -qm base; BASE=$(git -C "$M" rev-parse HEAD)
  git -C "$M" worktree add -q -b build "$W" "$BASE"
  printf '#!/bin/sh\nexit 3\n' > "$M/.bureau/regression/run.sh"
  printf '#!/bin/sh\ntest -f package.json\n' > "$RUN/regression/run.sh"
  printf '{"scope":{}}\n' > "$RUN/state.json"
  gate() {
    OUT="$TMP/$1"; mkdir "$OUT"
    "$ROOT/scripts/integration-gate.sh" --checkpoint-type integration --worktree-path "$W" \
      --base-ref "$BASE" --claimed-gates '[]' --state-json "$RUN/state.json" --out "$OUT"
    R="$OUT/integration-results.json"
  }
  gate run-dir
  jq -e '.gates[] | select(.name=="regression") | .result=="green" and .runner_source=="run-dir"' "$R" >/dev/null
  test ! -e "$W/.bureau"
  rm "$RUN/regression/run.sh" "$M/.bureau/regression/run.sh"
  gate absent
  jq -e '.escalate_marker=="" and .canonical_source=="manifest-only"
    and (.gates[] | select(.name=="regression") | .result=="absent")
    and (.gates[] | select(.name=="npm-test") | .result=="green")' "$R" >/dev/null
  echo PASS
expected: exit 0; stdout "PASS". A valid run-directory runner is selected before optional main-checkout provisioning, even when main has a red runner. With no runner anywhere, regression is absent and manifest tests still execute. MUTATION - provisioning before canonical resolution selects main's exit-3 runner or escalates on absence, failing the assertions.
phase: 99 · PR 102 review fixes
owner: scripts/integration-gate.sh (provisioning order)
