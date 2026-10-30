name: F319 · integration-gate.sh records a regression runner the branch removed or broke as red, never absent (issue #115)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  gate() { O="$TMP/ctx.$1"; mkdir -p "$O"; printf '{"scope":{}}\n' > "$TMP/state.json"
    "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
      --claimed-gates '[]' --state-json "$TMP/state.json" --out "$O" 2>/dev/null
    R="$O/integration-results.json"; }
  red_missing() { jq -e --arg why "$1" '.gates[] | select(.name=="regression")
    | .result=="red" and .exit_code_branch==127 and .runner_source=="missing"
      and (.missing_reason|contains($why))' "$R" >/dev/null; }
  new_repo() { W="$TMP/wt.$1"; mkdir -p "$W/.bureau/regression"
    git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
    printf '{"scripts":{"test":"true"}}\n' > "$W/package.json"; }
  # (a) The base commits a runner; the branch deletes it. A green manifest gate
  #     sits beside it, so "absent" here would have let the checkpoint proceed.
  new_repo a; printf '#!/bin/sh\nexit 1\n' > "$W/.bureau/regression/run.sh"
  git -C "$W" add -A; git -C "$W" commit -qm base; BASE=$(git -C "$W" rev-parse HEAD)
  git -C "$W" rm -q .bureau/regression/run.sh; git -C "$W" commit -qm "drop runner"
  gate a; red_missing "not on the branch"
  jq -e '(.gates[] | select(.name=="npm-test") | .result=="green")' "$R" >/dev/null
  # (b) A dangling symlink where the runner should be.
  new_repo b; git -C "$W" add -A; git -C "$W" commit -qm base; BASE=$(git -C "$W" rev-parse HEAD)
  ln -s nowhere "$W/.bureau/regression/run.sh"; git -C "$W" add -A; git -C "$W" commit -qm link
  gate b; red_missing "not a regular file"
  # (c) Committed fixtures with no runner beside them.
  new_repo c; git -C "$W" add -A; git -C "$W" commit -qm base; BASE=$(git -C "$W" rev-parse HEAD)
  printf 'name: x\n' > "$W/.bureau/regression/01-x.md"; git -C "$W" add -A; git -C "$W" commit -qm fx
  gate c; red_missing "no run.sh beside them"
  # The paired final gate cannot pair on any of these.
  for x in a b c; do
    if sh "$ROOT/scripts/terminal-pairing.sh" --gate "$TMP/ctx.$x/integration-results.json" \
         --review-sha "$(jq -r .branch_tip "$TMP/ctx.$x/integration-results.json")" >/dev/null 2>&1; then
      echo "FAIL: case $x paired"; exit 1; fi
  done
  echo PASS
expected: exit 0; stdout "PASS". A worktree runner missing because the branch deleted it (it exists at --base-ref), a dangling symlink at .bureau/regression/run.sh, and committed NN-*.md fixtures with no run.sh beside them each record the regression gate red, exit_code_branch 127, runner_source "missing", with a missing_reason naming the case; a green manifest gate beside it does not change that, and terminal-pairing.sh refuses to pair. MUTATION - removing the missing_reason checks turns all three into result "absent" (case a then proceeds on the green npm-test gate alone), so the fixture fails.
phase: 115 · integration gate regression runner resolution
owner: scripts/integration-gate.sh (fail-closed runner resolution)
