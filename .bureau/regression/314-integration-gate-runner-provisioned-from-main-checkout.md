name: F314 · integration-gate.sh runs a gitignored regression runner from the main checkout inside the worktree (issue #99)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  M="$TMP/main"; W="$TMP/wt"; mkdir -p "$M/.bureau/regression" "$TMP/ctx"
  git -C "$M" init -q; git -C "$M" config user.email t@t; git -C "$M" config user.name t
  printf '.bureau/\n' > "$M/.gitignore"
  git -C "$M" add -A; git -C "$M" commit -qm base
  BASE=$(git -C "$M" rev-parse HEAD)
  printf '#!/bin/sh\ncd "$(dirname "$0")/../.." || exit 2\ntest -f branch-only.txt\n' > "$M/.bureau/regression/run.sh"
  printf 'fixture\n' > "$M/.bureau/regression/01-sample.md"
  git -C "$M" worktree add -q -b build "$W" "$BASE"
  printf 'b\n' > "$W/branch-only.txt"; git -C "$W" add -A; git -C "$W" commit -qm build
  printf '{"scope":{}}\n' > "$TMP/state.json"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[{"name":"regression","command":"sh .bureau/regression/run.sh","result":"green"}]' \
    --state-json "$TMP/state.json" --out "$TMP/ctx"
  R="$TMP/ctx/integration-results.json"
  jq -e '.escalate_marker == ""' "$R"
  jq -e '[.gates[] | select(.name == "regression")][0] | .exit_code_branch == 0 and .result == "green"' "$R"
  jq -e '.under_declaration | map(select(.result == "red")) | length == 0' "$R"
  jq -e '.regression_runner.source == "main-checkout-copy" and .regression_runner.copied_files == 2' "$R"
  test -f "$W/.bureau/regression/01-sample.md"
  test -z "$(git -C "$W" status --porcelain --untracked-files=all)"
expected: exit 0 — the target repo gitignores .bureau/, so the build worktree has no runner; the gate copies the main checkout's .bureau/regression/ into the worktree (still ignored, worktree status clean) and runs it there. The runner passes only when its root is the worktree (branch-only.txt exists only on the build branch), so running main's copy in place would go red. regression is green, escalate_marker is empty, nothing red in under_declaration, and regression_runner records the copy. Nonzero on the old behaviour (regression red with exit_code_branch 127).
phase: issue #99 · integration-gate runner provisioning
owner: scripts/integration-gate.sh (provision_regression_runner)
