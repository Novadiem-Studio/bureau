name: F327 · integration-gate.sh preserves absence but escalates on unsafe provisioning (issue #99)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  printf '{"scope":{}}\n' > "$TMP/state.json"
  # Case A: .bureau/ is gitignored and the main checkout has no runner either.
  M="$TMP/a-main"; W="$TMP/a-wt"; mkdir -p "$M" "$TMP/a-ctx"
  git -C "$M" init -q; git -C "$M" config user.email t@t; git -C "$M" config user.name t
  printf '.bureau/\n' > "$M/.gitignore"; git -C "$M" add -A; git -C "$M" commit -qm base
  BASE=$(git -C "$M" rev-parse HEAD)
  git -C "$M" worktree add -q -b build "$W" "$BASE"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$TMP/a-ctx"
  R="$TMP/a-ctx/integration-results.json"
  jq -e '.escalate_marker == "" and .canonical_source == "regression-absent"' "$R"
  jq -e '.gates | length == 1 and .[0].result == "absent" and .[0].exit_code_branch == null' "$R"
  # Case B: the main checkout has an untracked runner, but .bureau/ is NOT
  # ignored, so copying it would add untracked files to the build branch.
  M="$TMP/b-main"; W="$TMP/b-wt"; mkdir -p "$M" "$TMP/b-ctx"
  git -C "$M" init -q; git -C "$M" config user.email t@t; git -C "$M" config user.name t
  printf 'x\n' > "$M/x.txt"; git -C "$M" add -A; git -C "$M" commit -qm base
  BASE=$(git -C "$M" rev-parse HEAD)
  mkdir -p "$M/.bureau/regression"; printf '#!/bin/sh\nexit 0\n' > "$M/.bureau/regression/run.sh"
  git -C "$M" worktree add -q -b build "$W" "$BASE"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$TMP/b-ctx"
  R="$TMP/b-ctx/integration-results.json"
  jq -e '.escalate_marker | startswith("regression runner absent from worktree")' "$R"
  jq -e '(.gates | length == 0) and (.under_declaration | length == 0)' "$R"
  test ! -e "$W/.bureau"
expected: exit 0. No runner anywhere records regression absent, preserving issue #115. A main-checkout runner whose copy would add unignored files instead escalates, with no gate records or worktree files created. MUTATION - escalating for ordinary absence fails A; removing the ignored-path preflight fails B.
phase: issue #99 · integration-gate runner provisioning
owner: scripts/integration-gate.sh (provision_regression_runner)
