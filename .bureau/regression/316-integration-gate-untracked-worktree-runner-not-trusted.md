name: F316 · integration-gate.sh replaces an untracked runner in the build worktree with the main checkout's (issue #99)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  M="$TMP/main"; W="$TMP/wt"; mkdir -p "$M/.bureau/regression" "$TMP/ctx"
  git -C "$M" init -q; git -C "$M" config user.email t@t; git -C "$M" config user.name t
  printf '.bureau/\n' > "$M/.gitignore"; git -C "$M" add -A; git -C "$M" commit -qm base
  BASE=$(git -C "$M" rev-parse HEAD)
  printf '#!/bin/sh\nexit 3\n' > "$M/.bureau/regression/run.sh"
  git -C "$M" worktree add -q -b build "$W" "$BASE"
  # The build writes its own ignored runner that always passes. It never shows in the diff.
  mkdir -p "$W/.bureau/regression"; printf '#!/bin/sh\nexit 0\n' > "$W/.bureau/regression/run.sh"
  printf '{"scope":{}}\n' > "$TMP/state.json"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$TMP/ctx"
  R="$TMP/ctx/integration-results.json"
  jq -e '[.gates[] | select(.name == "regression")][0].exit_code_branch == 3' "$R"
  jq -e '.regression_runner.source == "main-checkout-copy" and .regression_runner.replaced_worktree_runner == true' "$R"
expected: exit 0 — an untracked runner in the build worktree is writable by the build and invisible in its diff, so the gate re-syncs .bureau/regression/ from the main checkout and runs the owner's runner (exit 3, red), recording that it replaced the worktree copy. Nonzero if the gate trusts the worktree's untracked runner (regression green, exit 0).
phase: issue #99 · integration-gate runner provisioning
owner: scripts/integration-gate.sh (provision_regression_runner)
